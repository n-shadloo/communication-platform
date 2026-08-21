package com.example.communication_platform

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android side of the message alert, bound to a Context.
 *
 * This side holds no policy and keeps no state about messages. It reports what
 * Android says, posts the one reviewed sentence Dart hands it, and withdraws
 * it. Nothing that identifies a conversation, a sender, or a message ever
 * crosses the channel, so nothing of the sort can reach the system notification
 * service, a notification listener, or a lock screen.
 *
 * It is Context-bound rather than Activity-bound because a deferred catch-up
 * runs in a headless engine with no activity, and an alert that only existed
 * while an activity did would announce nothing at exactly the moment it
 * matters. The two operations that genuinely need an activity - showing the
 * runtime permission dialog and opening the settings screen - are supplied by
 * [activity] and are absent in a headless engine, which is why the reconciler
 * asks for permission only while the application is foregrounded.
 */
internal class MessageAlertChannel(
    private val context: Context,
    private val activity: Activity? = null,
    private val requestPermission: ((MethodChannel.Result) -> Unit)? = null,
) {
    companion object {
        const val NAME = "communication_platform/message_alerts"

        // Stable for the life of the installation. The channel id keys the
        // user's own sound and importance settings, so changing it would
        // silently discard them; the tag and id are what make show and hide
        // address one notification rather than accumulate a shade full of them.
        const val CHANNEL_ID = "messages"
        const val TAG = "message-alert"
        const val ID = 1
    }

    fun attach(messenger: BinaryMessenger): MethodChannel =
        MethodChannel(messenger, NAME).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (!handle(call, result)) {
                    result.notImplemented()
                }
            }
        }

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "platformState" -> result.success(platformState())
            "requestPermission" -> {
                val request = requestPermission
                if (request == null) {
                    // No activity to host the dialog. Reporting the current
                    // state is the truthful answer, and the reconciler only
                    // asks while the application is foregrounded anyway.
                    result.success(platformState())
                } else {
                    request(result)
                }
            }
            "show" -> {
                val title = call.argument<String>("title")
                if (title.isNullOrEmpty()) {
                    result.error("invalid_argument", null, null)
                } else {
                    show(
                        title = title,
                        channelName = call.argument<String>("channelName").orEmpty(),
                        channelDescription = call.argument<String>("channelDescription").orEmpty(),
                    )
                    result.success(null)
                }
            }
            "hide" -> {
                NotificationManagerCompat.from(context).cancel(TAG, ID)
                result.success(null)
            }
            "openSystemSettings" -> {
                openSystemSettings()
                result.success(null)
            }
            else -> return false
        }
        return true
    }

    fun platformState(): Map<String, Any> {
        val runtimePermission = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
        val host = activity
        return mapOf(
            "enabled" to NotificationManagerCompat.from(context).areNotificationsEnabled(),
            "runtimePermission" to runtimePermission,
            // True in exactly one situation: the user has refused once and not
            // yet twice. Dart uses it to make sure an automatic prompt is never
            // the refusal that makes the denial permanent. Without an activity
            // the platform cannot answer, and false is the answer that
            // withholds the prompt rather than risking it.
            "rationale" to (
                runtimePermission &&
                    host != null &&
                    ActivityCompat.shouldShowRequestPermissionRationale(
                        host,
                        Manifest.permission.POST_NOTIFICATIONS,
                    )
                ),
        )
    }

    private fun show(title: String, channelName: String, channelDescription: String) {
        val notifications = NotificationManagerCompat.from(context)
        if (!notifications.areNotificationsEnabled()) {
            return
        }
        notifications.createNotificationChannel(
            NotificationChannelCompat
                .Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_HIGH)
                // Name and description are re-supplied on every post so a change
                // of device language reaches the system settings screen. The
                // importance is only honoured at creation: the user owns it
                // afterwards, which is the correct division.
                .setName(channelName)
                .setDescription(channelDescription)
                .setVibrationEnabled(true)
                .build(),
        )
        notifications.notify(TAG, ID, alert(title))
    }

    private fun alert(title: String): Notification =
        alertBuilder(title)
            .setContentIntent(launchPendingIntent())
            .setAutoCancel(true)
            // Android 15 and above replaces notification content during screen
            // sharing with the public version when one exists, and redacts it
            // without any context when one does not. The public version here is
            // the same sentence, because the sentence was written to be safe in
            // front of anyone.
            .setPublicVersion(alertBuilder(title).build())
            .build()

    private fun alertBuilder(title: String): NotificationCompat.Builder =
        NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_message_alert)
            .setContentTitle(title)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            // The arrival time is not shown. It is not needed to act on the
            // alert, and it is one more thing a lock screen would tell someone
            // holding the phone.
            .setShowWhen(false)

    private fun launchPendingIntent(): PendingIntent {
        // Deliberately the launcher intent and nothing else: no destination, no
        // extras, no identifier. Tapping the alert opens the application exactly
        // as its icon would, and the routing guards already in the application
        // decide what may be shown, so there is no payload for a notification
        // listener to read and none for anything to forge.
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

    private fun openSystemSettings() {
        val intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", context.packageName, null))
            }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            (activity ?: context).startActivity(intent)
        } catch (_: Exception) {
            // A device with no settings activity for this leaves the user where
            // they were rather than crashing the application.
        }
    }
}
