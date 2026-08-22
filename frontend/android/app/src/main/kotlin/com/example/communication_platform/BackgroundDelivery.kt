package com.example.communication_platform

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The deferred catch-up: what makes this application take delivery of waiting
 * messages when nobody is using it.
 *
 * The mechanism is a periodic `JobScheduler` job with a connected-network
 * constraint, persisted across reboots. That is not a preference; it is the
 * only thing Android offers that needs no permission the user can refuse, no
 * exemption they must grant, and no per-manufacturer setting. What it is worth
 * is written down honestly in the decision record: the platform's floor is
 * fifteen minutes, Doze defers even that to maintenance windows that thin out,
 * the Android 16 job quota applies in every standby bucket, and the *rare* and
 * *restricted* buckets have no background network at all.
 *
 * ## One delivery owner, always
 *
 * A job runs in this application's own process, and a Flutter process has
 * exactly one Dart VM. Two Dart root isolates in it would be two token
 * coordinators against one *rotating* refresh token, and the loser presents a
 * token the server has already retired - a 401, and an ended session for a user
 * who did nothing wrong. So a tick is delivered to the isolate that already
 * exists whenever there is one, and only starts a headless engine when there is
 * not.
 *
 * That arbitration needs no lock, and nothing about it is durable. `JobService`
 * callbacks and `FlutterActivity` engine callbacks are both delivered on this
 * process's main looper, so every transition below happens on one thread, in
 * order; and every owner it arbitrates between lives inside this process, so
 * process death releases all of it at once and there is no stale holder to
 * detect, expire or displace.
 *
 * ## Who gives way
 *
 * The two owners are not symmetric. A catch-up runs precisely because nobody was
 * looking; the moment somebody is, the foreground drains the same mailbox within
 * seconds and this run has no reason left to exist. So the foreground does not
 * wait for a whole drain: attaching a foreground engine asks the run in flight
 * to stand down, and it gives way between units of work. It is asked rather than
 * killed, because abandoning a transaction or a call into the shared native
 * cryptographic core part-way is the one thing worse than waiting.
 */
internal object BackgroundDelivery {
    const val CHANNEL = "communication_platform/background_delivery"

    /** The Dart function each flavor's entry-point file exports. */
    const val ENTRYPOINT = "backgroundDelivery"

    /**
     * Stable for the life of the installation. It identifies one periodic job,
     * so re-arming replaces rather than accumulates.
     */
    const val JOB_ID = 0x63704431

    /**
     * How long a tick handed to a live foreground isolate may take.
     *
     * Longer than the deadline that isolate applies to itself, so the ordinary
     * end of a slow catch-up is the application's own answer rather than this.
     */
    private const val FOREGROUND_TICK_TIMEOUT_MS = 150_000L

    /**
     * How long a headless run may take before its engine is torn down.
     *
     * Well inside the platform's own limit, which from Android 12 stops a job
     * after ten minutes when the system wants the resources. An end this
     * application chose is better than one the system imposes, because the
     * system's arrives by killing work wherever it stands.
     */
    private const val HEADLESS_RUN_TIMEOUT_MS = 240_000L

    private val main = Handler(Looper.getMainLooper())

    private var foreground: MethodChannel? = null
    private var headless: HeadlessRun? = null
    private var abandonForeground: (() -> Unit)? = null
    private val ownershipWaiters = mutableListOf<MethodChannel.Result>()

    // ---------------------------------------------------------------------
    // Scheduling
    // ---------------------------------------------------------------------

    /**
     * Arms the periodic catch-up, or leaves an equivalent one alone.
     *
     * Re-registering a periodic job restarts its window, so an application that
     * armed on every transition would push the window past its own interval
     * forever. Checking first is what makes arming idempotent.
     */
    @Suppress("DEPRECATION")
    fun schedule(context: Context, requestedIntervalMillis: Long) {
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
        // The platform enforces its own floor and silently raises anything
        // shorter, so the clamp here is only so that what is compared below is
        // what the platform will actually store.
        val interval = maxOf(requestedIntervalMillis, JobInfo.getMinPeriodMillis())
        val pending = scheduler.getPendingJob(JOB_ID)
        if (pending != null &&
            pending.intervalMillis == interval &&
            pending.isPersisted &&
            pending.networkType == JobInfo.NETWORK_TYPE_ANY
        ) {
            return
        }
        val job = JobInfo.Builder(
            JOB_ID,
            ComponentName(context, DeferredDeliveryJobService::class.java),
        )
            .setPeriodic(interval)
            // Any network at all. Never a probe of a public host: the only
            // reachability that matters is the provisioned server's, and the
            // drain itself is what establishes it.
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            // Survives a restart with no boot receiver of this application's
            // own. A device that has not been unlocked since booting cannot run
            // it either way, because the database key is credential-encrypted.
            .setPersisted(true)
            .build()
        try {
            scheduler.schedule(job)
        } catch (_: Exception) {
            // A device that refuses the job leaves delivery exactly where it
            // was: nothing arrives until the application is opened, which is
            // what the artifact already tells its users can happen.
        }
    }

    fun cancel(context: Context) {
        context.getSystemService(JobScheduler::class.java)?.cancel(JOB_ID)
    }

    // ---------------------------------------------------------------------
    // Ownership, all on the main thread
    // ---------------------------------------------------------------------

    /**
     * Registers the isolate the user is looking at as the delivery owner.
     *
     * This is also the earliest moment this process can know a foreground
     * isolate is coming: it runs in `configureFlutterEngine`, before that
     * engine's Dart entry point does anything at all. A catch-up in flight is
     * asked to stand down here rather than when the foreground gets round to
     * asking, so that by the time Dart reaches its ownership question the run it
     * would otherwise wait for is already winding up.
     */
    fun attachForeground(channel: MethodChannel) {
        foreground = channel
        headless?.requestStandDown()
    }

    fun detachForeground(channel: MethodChannel) {
        if (foreground === channel) {
            foreground = null
        }
    }

    private fun releaseOwnershipWaiters() {
        val waiting = ownershipWaiters.toList()
        ownershipWaiters.clear()
        waiting.forEach { it.success(null) }
    }

    // ---------------------------------------------------------------------
    // The channel, registered on every engine this application starts
    // ---------------------------------------------------------------------

    fun attach(context: Context, messenger: BinaryMessenger): MethodChannel =
        MethodChannel(messenger, CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                handle(context.applicationContext, call, result)
            }
        }

    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "schedule" -> {
                val requested = when (val value = call.argument<Any>("minimumIntervalMillis")) {
                    is Int -> value.toLong()
                    is Long -> value
                    else -> 0L
                }
                schedule(context, requested)
                result.success(null)
            }
            "cancel" -> {
                cancel(context)
                result.success(null)
            }
            "awaitExclusiveOwnership" -> {
                if (headless == null) {
                    result.success(null)
                } else {
                    // A headless run is in flight. The foreground waits for it
                    // rather than racing it, and rather than killing it: an
                    // abandoned call into the shared native cryptographic core
                    // is a worse trade than a few seconds of waiting.
                    ownershipWaiters.add(result)
                }
            }
            "finished" -> {
                headless?.finish()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------------
    // Running one catch-up
    // ---------------------------------------------------------------------

    /**
     * Starts one catch-up and returns true when [onDone] will be called later.
     *
     * Returns false when there is nothing to do: another catch-up is already in
     * flight, or a live foreground isolate has no delivery owner listening, in
     * which case there is no session to deliver to anyway.
     */
    fun beginCatchUp(context: Context, onDone: () -> Unit): Boolean {
        if (headless != null) {
            return false
        }
        val live = foreground
        if (live != null) {
            return deliverToForeground(live, onDone)
        }
        val applicationContext = context.applicationContext
        val run = HeadlessRun(
            context = applicationContext,
            // A run started while an activity is already attaching is displaced
            // before it has done anything, which is the cheapest moment there
            // is. Both callbacks are on one looper, so this reads a value that
            // cannot change underneath it.
            standDownImmediately = foreground != null,
            attachChannels = { messenger ->
                // A headless engine reaches only the plugins Flutter registers
                // automatically. Everything this application owns has to be put
                // on it here, and an engine missing the protected-storage
                // channel could not open its database at all.
                ProtectedStorageChannel(applicationContext).attach(messenger)
                MessageAlertChannel(applicationContext).attach(messenger)
                attach(applicationContext, messenger)
            },
            onDone = {
                headless = null
                releaseOwnershipWaiters()
                onDone()
            },
        )
        headless = run
        if (!run.start()) {
            headless = null
            releaseOwnershipWaiters()
            return false
        }
        return true
    }

    /**
     * Abandons whatever is in flight, because the platform is stopping the job.
     *
     * `onStopJob` means the job's guarantees are already gone, so what matters
     * here is releasing what this object holds: a headless engine, or the
     * pending completion of a tick handed to the foreground. Neither leaves
     * anything inconsistent behind — every durable write is a transaction.
     */
    fun abandonCatchUp() {
        headless?.abandon()
        abandonForeground?.invoke()
    }

    private fun deliverToForeground(channel: MethodChannel, onDone: () -> Unit): Boolean {
        var settled = false
        lateinit var done: () -> Unit
        val timeout = Runnable { done() }
        done = {
            if (!settled) {
                settled = true
                main.removeCallbacks(timeout)
                abandonForeground = null
                onDone()
            }
        }
        abandonForeground = done
        main.postDelayed(timeout, FOREGROUND_TICK_TIMEOUT_MS)
        channel.invokeMethod(
            "runCatchUp",
            null,
            object : MethodChannel.Result {
                override fun success(value: Any?) = done()

                override fun error(code: String, message: String?, details: Any?) = done()

                // No delivery owner is listening in that isolate: it is not
                // signed in, or its session failed to compose. Either way there
                // is nothing this job can add.
                override fun notImplemented() = done()
            },
        )
        return true
    }

    /**
     * One headless engine, alive only for as long as the Dart entry point takes.
     *
     * The engine is what registers this application's own channels on itself.
     * Nothing about that is optional: a headless engine reaches only the plugins
     * Flutter registers automatically plus what is attached here, so an engine
     * missing the protected-storage channel could not open the database at all.
     */
    private class HeadlessRun(
        private val context: Context,
        private val standDownImmediately: Boolean,
        private val attachChannels: (BinaryMessenger) -> MethodChannel,
        private val onDone: () -> Unit,
    ) {
        private val handler = Handler(Looper.getMainLooper())
        private var engine: FlutterEngine? = null
        private var channel: MethodChannel? = null
        private var settled = false
        private val timeout = Runnable { finish() }

        fun start(): Boolean {
            return try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(context)
                loader.ensureInitializationComplete(context, null)
                val created = FlutterEngine(context)
                engine = created
                channel = attachChannels(created.dartExecutor.binaryMessenger)
                handler.postDelayed(timeout, HEADLESS_RUN_TIMEOUT_MS)
                created.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT),
                )
                if (standDownImmediately) {
                    requestStandDown()
                }
                true
            } catch (_: Exception) {
                handler.removeCallbacks(timeout)
                destroy()
                false
            }
        }

        /**
         * Tells this run it is no longer the delivery owner.
         *
         * Best-effort and deliberately unacknowledged: the Dart side latches the
         * request, reads it between units of work, and answers by reporting
         * finished — the same reply the ordinary path sends. If it never
         * arrives, the four-minute deadline above ends the run instead, and the
         * foreground has a deadline of its own for waiting.
         */
        fun requestStandDown() {
            if (settled) {
                return
            }
            channel?.invokeMethod("standDown", null)
        }

        /** The ordinary end: the Dart side reported that its run is over. */
        fun finish() {
            if (settled) {
                return
            }
            settled = true
            handler.removeCallbacks(timeout)
            channel = null
            destroy()
            onDone()
        }

        /**
         * The platform is stopping this job. Tearing the engine down here is
         * equivalent to the process death the durable engine is already
         * designed to survive: every write is a transaction, so an abandoned
         * drain leaves committed state consistent and the envelope it was
         * inspecting is picked up again next time.
         */
        fun abandon() = finish()

        private fun destroy() {
            engine?.destroy()
            engine = null
        }
    }
}

/**
 * The platform's entry point into a deferred catch-up.
 *
 * A plain service, not a foreground one: it shows no notification, holds no
 * connection, and is bound by the system with `BIND_JOB_SERVICE` so that only
 * the job scheduler can start it. `onStartJob` returns immediately and the work
 * completes asynchronously, because this callback runs on the application's
 * main thread and blocking it is an ANR from Android 14 onwards.
 */
class DeferredDeliveryJobService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        val started = BackgroundDelivery.beginCatchUp(applicationContext) {
            // `false` even on failure: this is a periodic job, so it is
            // rescheduled by its own periodic policy. Backing off a catch-up
            // that found no network would only delay the next attempt past the
            // interval that already governs it.
            jobFinished(params, false)
        }
        return started
    }

    override fun onStopJob(params: JobParameters): Boolean {
        BackgroundDelivery.abandonCatchUp()
        return false
    }
}
