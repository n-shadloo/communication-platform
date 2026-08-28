package com.example.communication_platform

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Sustained delivery: the opt-in layer that keeps this application able to
 * receive while nobody is looking at it.
 *
 * ## What this actually buys, and what it does not
 *
 * A backgrounded process is cached, a cached process is frozen, and the system
 * terminates the TCP sockets of a frozen app. A running foreground service is
 * the documented way out of that: a process with a running service component is
 * not cached, and the platform's own power table gives an app running a
 * foreground service unrestricted network by app state. What it does *not*
 * remove is Doze, which suspends network access at the device level; only the
 * battery-optimization exemption does that, and the same exemption is what
 * removes the app-standby-bucket restrictions that disable background network
 * entirely in the *rare* and *restricted* buckets.
 *
 * So both are required, and neither is a guarantee. A manufacturer can end this
 * process at any moment, and nothing here or anywhere else prevents it.
 *
 * ## Why `specialUse`
 *
 * Holding an authenticated connection to this application's own self-hosted
 * server, in a deployment that cannot reach any push transport, is not any of
 * the other declared types. `dataSync` would be an overstatement *and* is
 * capped at six hours per day and forbidden from a boot receiver;
 * `remoteMessaging` describes device-to-device message continuity;
 * `systemExempted` is gated on roles this application does not have. The
 * subtype property below is where that reasoning is written down, and it is
 * written to be true rather than to be accepted.
 *
 * ## Nothing runs until it is chosen
 *
 * There is no automatic start of any kind here. The service is started by the
 * user turning the capability on, and afterwards only by a reconciliation that
 * has first read the durable choice out of the encrypted database — which means
 * a Dart isolate has already run and already decided. A build nobody turned it
 * on for never reaches any of this code.
 */
internal object SustainedDelivery {
    const val CHANNEL = "communication_platform/sustained_delivery"

    /** The Dart function each flavor's entry-point file exports. */
    const val ENTRYPOINT = "sustainedDelivery"

    /**
     * Stable for the life of the installation. The channel id keys the user's
     * own importance and sound settings for this entry, so changing it would
     * silently discard them.
     */
    const val NOTIFICATION_CHANNEL_ID = "sustained-delivery"
    const val NOTIFICATION_TAG = "sustained-delivery"
    const val NOTIFICATION_ID = 2

    /**
     * Localized text for the one entry this shows, supplied by Dart and carried
     * in the start intent.
     *
     * It travels in the intent rather than in a field of this object because the
     * platform may restart a killed service, and it restarts it with the
     * original intent redelivered - a static field would be gone with the
     * process it lived in, and the restarted service would have nothing it is
     * allowed to display.
     */
    const val EXTRA_TITLE = "title"
    const val EXTRA_CHANNEL_NAME = "channelName"
    const val EXTRA_CHANNEL_DESCRIPTION = "channelDescription"

    /**
     * How long a start or a stop may take before this stops waiting for it.
     *
     * Starting and stopping a service are *asynchronous*: `onStartCommand` and
     * `onDestroy` are posted to this looper, so they cannot have run by the
     * time the call that asked for them returns. Answering immediately would
     * report "not running" for every start, and the caller would read a service
     * that is about to appear as one the platform refused. So the answer waits
     * for the transition, and this bounds the wait - well inside the few
     * seconds the platform itself allows a `startForegroundService` before it
     * throws.
     */
    private const val TRANSITION_TIMEOUT_MS = 10_000L

    private val main = Handler(Looper.getMainLooper())

    private var run: SustainedRun? = null
    private var serviceRunning = false

    /** Callers waiting for a start or a stop they asked for to actually land. */
    private val transitionWaiters = mutableListOf<MethodChannel.Result>()

    private fun settleTransitions(context: Context) {
        if (transitionWaiters.isEmpty()) {
            return
        }
        val waiting = transitionWaiters.toList()
        transitionWaiters.clear()
        val answer = state(context)
        waiting.forEach { it.success(answer) }
    }

    // ---------------------------------------------------------------------
    // What the platform can be asked
    // ---------------------------------------------------------------------

    private fun isExempt(context: Context): Boolean {
        val power = context.getSystemService(PowerManager::class.java) ?: return false
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun state(context: Context): Map<String, Any> = mapOf(
        "running" to serviceRunning,
        // Read from the platform every time. The user can withdraw this in
        // system settings, and a manufacturer's battery management can withdraw
        // it during a system update, neither of which tells this application
        // anything.
        "exempt" to isExempt(context),
        "alertsEnabled" to NotificationManagerCompat.from(context).areNotificationsEnabled(),
    )

    // ---------------------------------------------------------------------
    // The channel
    // ---------------------------------------------------------------------

    /**
     * [activity] is supplied only by the activity's engine, and only because
     * the system exemption dialog is an activity that only an activity can
     * start. Its absence in a headless engine is why the enable flow is a
     * foreground flow: a run with no window reports the exemption it already
     * has and never asks for one.
     */
    fun attach(
        context: Context,
        messenger: BinaryMessenger,
        activity: android.app.Activity? = null,
    ): MethodChannel =
        MethodChannel(messenger, CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                handle(context.applicationContext, activity, call, result)
            }
        }

    private fun handle(
        context: Context,
        activity: android.app.Activity?,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "platformState" -> result.success(state(context))
            "requestExemption" -> {
                if (activity == null) {
                    // No window to host the dialog. Reporting the current state
                    // is the truthful answer, and the enable flow only runs with
                    // the user present anyway.
                    result.success(state(context))
                } else {
                    requestExemption(activity, context, result)
                }
            }
            "openVendorSettings" -> {
                openVendorSettings(activity ?: context)
                result.success(null)
            }
            "start" -> {
                // The reviewed, localized text this may display crosses with the
                // start itself, so a service can never run with text this project
                // did not write. Android string resources are deliberately not
                // used: one catalogue is reviewed, one catalogue is translated,
                // and the shade can never speak a different language from the
                // screen behind it.
                val requested = start(
                    context,
                    title = call.argument<String>(EXTRA_TITLE).orEmpty(),
                    channelName = call.argument<String>(EXTRA_CHANNEL_NAME).orEmpty(),
                    channelDescription =
                        call.argument<String>(EXTRA_CHANNEL_DESCRIPTION).orEmpty(),
                )
                awaitTransition(context, requested, result)
            }
            "stop" -> {
                awaitTransition(context, stop(context), result)
            }
            "finished" -> {
                run?.finish()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------------
    // Starting and stopping the service
    // ---------------------------------------------------------------------

    /**
     * Answers the caller once the transition it asked for has landed, or once
     * the bound above has passed.
     *
     * [requested] is false when there was nothing to do or nothing could be
     * asked for, and then the current state is already the answer.
     */
    private fun awaitTransition(
        context: Context,
        requested: Boolean,
        result: MethodChannel.Result,
    ) {
        if (!requested) {
            result.success(state(context))
            return
        }
        transitionWaiters.add(result)
        main.postDelayed({ settleTransitions(context) }, TRANSITION_TIMEOUT_MS)
    }

    /** Returns true when a start was asked for and its answer must be waited for. */
    private fun start(
        context: Context,
        title: String,
        channelName: String,
        channelDescription: String,
    ): Boolean {
        if (serviceRunning) {
            return false
        }
        if (title.isEmpty() || channelName.isEmpty()) {
            // Nothing to display, so nothing is started. A foreground service
            // must show a notification, and one assembled here would be text
            // this project never reviewed or translated.
            return false
        }
        return try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, SustainedDeliveryService::class.java)
                    .putExtra(EXTRA_TITLE, title)
                    .putExtra(EXTRA_CHANNEL_NAME, channelName)
                    .putExtra(EXTRA_CHANNEL_DESCRIPTION, channelDescription),
            )
            true
        } catch (_: Exception) {
            // Refused: a background start with no exemption, a manufacturer
            // restriction, or a battery setting of "Restricted". There is
            // nothing to wait for, and the state the caller reads says
            // `running` false - which is what it reports to the user.
            false
        }
    }

    /** Returns true when a stop was asked for and its answer must be waited for. */
    private fun stop(context: Context): Boolean {
        if (!serviceRunning) {
            return false
        }
        return try {
            context.stopService(Intent(context, SustainedDeliveryService::class.java))
            true
        } catch (_: Exception) {
            // A service that cannot be stopped is not a state this process can
            // repair. `serviceRunning` is corrected by onDestroy either way.
            false
        }
    }

    // ---------------------------------------------------------------------
    // The engine the service hosts
    // ---------------------------------------------------------------------

    /**
     * The service is up. Start the delivery isolate unless something else in
     * this process already owns delivery.
     *
     * Everything below runs on the main looper, which is also where
     * `FlutterActivity.configureFlutterEngine` and `JobService` callbacks are
     * delivered, so the three owners this process can produce are arbitrated on
     * one thread in order (ADR-050, extended by ADR-051).
     */
    internal fun onServiceStarted(context: Context) {
        serviceRunning = true
        // Before the engine is created, because creating one is slow and the
        // caller is waiting for an answer about the service, not about it.
        settleTransitions(context)
        BackgroundDelivery.onSustainedServiceStarted(context)
    }

    internal fun onServiceStopping(context: Context) {
        serviceRunning = false
        val active = run
        run = null
        active?.abandon()
        settleTransitions(context)
        BackgroundDelivery.onSustainedServiceStopped()
    }

    /** True while a sustained delivery isolate is running. */
    internal fun isRunning(): Boolean = run != null

    internal fun channelOfRun(): MethodChannel? = run?.channel

    /**
     * Starts the delivery isolate, and returns false when there is nothing to
     * start — the service is not up, or one already exists.
     */
    internal fun beginRun(context: Context, onDone: () -> Unit): Boolean {
        if (!serviceRunning || run != null) {
            return false
        }
        val applicationContext = context.applicationContext
        val started = SustainedRun(
            context = applicationContext,
            attachChannels = { messenger ->
                // A headless engine reaches only the plugins Flutter registers
                // automatically. Everything this application owns has to be put
                // on it here, and an engine without the protected-storage
                // channel could not open its database at all.
                ProtectedStorageChannel(applicationContext).attach(messenger)
                MessageAlertChannel(applicationContext).attach(messenger)
                BackgroundDelivery.attach(applicationContext, messenger)
                attach(applicationContext, messenger)
            },
            onDone = {
                run = null
                onDone()
            },
        )
        run = started
        if (!started.start()) {
            run = null
            return false
        }
        return true
    }

    /**
     * Asks the delivery isolate to give way, because a foreground engine is
     * attaching.
     *
     * Asked rather than killed, for the reason the deferred catch-up is asked:
     * abandoning a transaction or a call into the shared native cryptographic
     * core part-way is worse than waiting for a unit of work to end.
     */
    internal fun requestStandDown() {
        run?.requestStandDown()
    }

    /**
     * One long-lived engine, alive for as long as this process owns delivery
     * and nobody is looking at the application.
     *
     * Unlike a deferred catch-up there is no deadline here. The run ends
     * because a foreground engine displaced it, because the service stopped, or
     * because the Dart side concluded there is nothing to deliver to — never
     * because a timer expired, since the whole point is that it lasts.
     */
    private class SustainedRun(
        private val context: Context,
        private val attachChannels: (BinaryMessenger) -> MethodChannel,
        private val onDone: () -> Unit,
    ) {
        private var engine: FlutterEngine? = null
        var channel: MethodChannel? = null
            private set
        private var settled = false

        fun start(): Boolean {
            return try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(context)
                loader.ensureInitializationComplete(context, null)
                val created = FlutterEngine(context)
                engine = created
                channel = attachChannels(created.dartExecutor.binaryMessenger)
                created.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), ENTRYPOINT),
                )
                true
            } catch (_: Exception) {
                destroy()
                false
            }
        }

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
            channel = null
            destroy()
            onDone()
        }

        /**
         * The service is going away, so the process is about to be cached and
         * frozen. Tearing the engine down here is equivalent to the process
         * death the durable engine is already designed to survive.
         */
        fun abandon() = finish()

        private fun destroy() {
            engine?.destroy()
            engine = null
        }
    }

    // ---------------------------------------------------------------------
    // The notification, and the two settings screens
    // ---------------------------------------------------------------------

    /**
     * The permanent entry this capability displays while it is armed.
     *
     * Everything about it is chosen to reveal as little as a foreground service
     * can. `IMPORTANCE_LOW` because it must never make a sound or interrupt —
     * and never `IMPORTANCE_MIN`, which the platform documents as wrong for a
     * foreground service and answers by showing a *higher* priority notice
     * instead. `VISIBILITY_SECRET` so that no part of it appears on a locked
     * screen or while the screen is being shared. No timestamp, because the
     * moment this was armed is one more thing a bystander would otherwise
     * learn. The tap target is the launcher intent and nothing else: no
     * destination, no extras, no identifier.
     */
    internal fun notification(context: Context, intent: Intent?): Notification? {
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        val channelName = intent?.getStringExtra(EXTRA_CHANNEL_NAME).orEmpty()
        if (title.isEmpty() || channelName.isEmpty()) {
            return null
        }
        NotificationManagerCompat.from(context).createNotificationChannel(
            NotificationChannelCompat
                .Builder(NOTIFICATION_CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
                .setName(channelName)
                .setDescription(intent?.getStringExtra(EXTRA_CHANNEL_DESCRIPTION).orEmpty())
                .setVibrationEnabled(false)
                .setShowBadge(false)
                .build(),
        )
        return NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_message_alert)
            .setContentTitle(title)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setShowWhen(false)
            .setSilent(true)
            .setOngoing(true)
            .setContentIntent(launchPendingIntent(context))
            .build()
    }

    private fun launchPendingIntent(context: Context): PendingIntent {
        val intent =
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /**
     * Shows the system's own battery-optimization exemption dialog.
     *
     * The dialog's result is not read and is not readable: it reports refusal
     * and dismissal identically. What is reported back is
     * `isIgnoringBatteryOptimizations()` afterwards, which is the only answer
     * that is a fact rather than an inference.
     */
    internal fun requestExemption(
        activity: android.app.Activity,
        context: Context,
        result: MethodChannel.Result,
    ) {
        if (isExempt(context)) {
            result.success(state(context))
            return
        }
        try {
            @Suppress("BatteryLife")
            activity.startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    .setData(Uri.fromParts("package", context.packageName, null)),
            )
        } catch (_: Exception) {
            // A device with no such screen leaves the user where they were. The
            // state read below says the exemption is still absent, which is what
            // the surface reports.
        }
        // The activity does not report back, so the answer is read after the
        // user has had a moment to give one. Reading it too early would report
        // a refusal the user did not make; the surface re-reads on resume in any
        // case, so this only decides what the enable flow concludes right now.
        main.postDelayed({ result.success(state(context)) }, EXEMPTION_ANSWER_DELAY_MS)
    }

    private const val EXEMPTION_ANSWER_DELAY_MS = 400L

    /**
     * Opens the manufacturer's own background-restriction screen when the
     * manufacturer documents one, and this device's application-details screen
     * otherwise.
     *
     * Only one vendor screen is reached this way, and only because Samsung
     * publishes the intent for it in its own developer documentation. Nothing
     * here is derived from a forum post, and no attempt is made to detect the
     * manufacturer: the documented intent is tried, and the platform's own
     * screen is what happens when it does not exist. Neither outcome is
     * reported back, because this application cannot read any of those settings
     * and must never appear to have confirmed them.
     */
    internal fun openVendorSettings(context: Context) {
        val samsung = Intent("com.samsung.android.sm.ACTION_OPEN_CHECKABLE_LISTACTIVITY")
            .setPackage("com.samsung.android.lool")
            // 2 is the "never sleeping apps" list, per Samsung's published
            // deep-link API.
            .putExtra("activity_type", 2)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(samsung)
            return
        } catch (_: Exception) {
            // Not a device that has it.
        }
        try {
            context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", context.packageName, null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            // A device with no application-details screen leaves the user where
            // they were rather than crashing the application.
        }
    }
}

/**
 * The foreground service that keeps this process out of the cached state.
 *
 * It holds no data, opens no connection and makes no decision. Its only job is
 * to exist, because a process with a running service component is not cached
 * and therefore not frozen, and the platform does not terminate the sockets of
 * a process it has not frozen. Everything that decides *what* to do lives in
 * the Dart isolate this service hosts.
 */
class SustainedDeliveryService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = SustainedDelivery.notification(this, intent)
        if (notification == null) {
            // No reviewed text was handed over, so there is nothing this may
            // display, so it may not run. Stopping without ever promoting is the
            // fail-closed direction.
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            ServiceCompat.startForeground(
                this,
                SustainedDelivery.NOTIFICATION_ID,
                notification,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                } else {
                    0
                },
            )
        } catch (_: Exception) {
            // The platform refused to let this become a foreground service —
            // "Restricted" battery usage, a manufacturer restriction, or a
            // background start with no exemption. Stopping is what makes the
            // refusal visible to the user as a capability that did not start,
            // rather than as a service that quietly does nothing.
            stopSelf()
            return START_NOT_STICKY
        }
        SustainedDelivery.onServiceStarted(applicationContext)
        // Redelivered rather than sticky, because a sticky restart arrives with
        // a null intent and this service may display only text that crossed the
        // channel with the start. That restart is a background
        // foreground-service start, which is permitted because this capability
        // requires the battery-optimization exemption - and it is refused above
        // if the exemption has since gone, which is the fail-closed direction.
        // The isolate it starts re-reads the durable choice before it does
        // anything, so a restart can never resurrect a capability the user has
        // turned off.
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        SustainedDelivery.onServiceStopping(applicationContext)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    /**
     * The user swiped the application away from Recents.
     *
     * That is not a decision about this capability, and the platform keeps a
     * started service alive across it. Nothing is done here deliberately: the
     * capability ends when the user turns it off, or when the platform ends it.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
    }
}
