package com.mystyle.purelive

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Foreground lifetime only. WebRTC requests fresh OS consent before start. */
class ScreenCapturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private val stopping = mutableListOf<MethodChannel.Result>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "pure_live/screen_capture")
        channel.setMethodCallHandler(this)
        ScreenCaptureService.stopped = { generation ->
            val completed = stopping.toList()
            stopping.clear()
            completed.forEach { it.success(null) }
            channel.invokeMethod("stopped", mapOf("generation" to generation))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                if (pending != null || ScreenCaptureService.running) {
                    result.error("capture_busy", "Screen capture is starting", null)
                    return
                }
                pending = result
                ScreenCaptureService.started = { success -> finish(success) }
                val intent = Intent(context, ScreenCaptureService::class.java)
                    .putExtra("generation", call.argument<Number>("generation")?.toLong() ?: 0L)
                    .putExtra("title", call.argument<String>("title")?.take(120) ?: "")
                    .putExtra("text", call.argument<String>("text")?.take(240) ?: "")
                    .putExtra("stop", call.argument<String>("stop")?.take(60) ?: "")
                try {
                    if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                    else context.startService(intent)
                    handler.postDelayed({ if (pending === result) finish(false) }, 10000)
                } catch (_: Exception) {
                    finish(false)
                }
            }
            "stop" -> {
                // Cancellation also wins while startService is still queued.
                if (pending != null) finish(false)
                if (!ScreenCaptureService.running) {
                    context.stopService(Intent(context, ScreenCaptureService::class.java))
                    result.success(null)
                }
                else {
                    stopping.add(result)
                    context.stopService(Intent(context, ScreenCaptureService::class.java))
                    handler.postDelayed({
                        if (stopping.remove(result)) result.error("capture_stop_timeout", "Screen capture is stopping", null)
                    }, 3000)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun finish(success: Boolean) {
        val result = pending ?: return
        pending = null
        ScreenCaptureService.started = null
        handler.removeCallbacksAndMessages(null)
        if (success) result.success(null)
        else {
            context.stopService(Intent(context, ScreenCaptureService::class.java))
            result.error("capture_service_failed", "Screen capture service unavailable", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        handler.removeCallbacksAndMessages(null)
        pending?.error("capture_closed", "Screen capture closed", null)
        pending = null
        stopping.forEach { it.success(null) }
        stopping.clear()
        ScreenCaptureService.started = null
        ScreenCaptureService.stopped = null
        context.stopService(Intent(context, ScreenCaptureService::class.java))
        channel.setMethodCallHandler(null)
    }
}

/** One visible, locally stoppable service, never restarted after process death. */
class ScreenCaptureService : Service() {
    companion object {
        private const val CHANNEL = "purelive_screen_capture"
        private const val NOTIFICATION = 428126
        private const val STOP = "purelive.screen_capture.stop"
        internal var started: ((Boolean) -> Unit)? = null
        internal var stopped: ((Long) -> Unit)? = null
        internal var running: Boolean = false
    }

    private var generation = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP || intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            generation = intent.getLongExtra("generation", 0L)
            val title = intent.getStringExtra("title") ?: ""
            val text = intent.getStringExtra("text") ?: ""
            val stop = intent.getStringExtra("stop") ?: ""
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_LOW))
            }
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
            val action = PendingIntent.getService(this, NOTIFICATION,
                Intent(this, ScreenCaptureService::class.java).setAction(STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val open = PendingIntent.getActivity(this, NOTIFICATION,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val notification = builder.setSmallIcon(R.drawable.ic_stat_recording)
                .setContentTitle(title).setContentText(text).setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE).setContentIntent(open)
                .addAction(Notification.Action.Builder(null, stop, action).build()).build()
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            } else startForeground(NOTIFICATION, notification)
            running = true
            started?.invoke(true)
        } catch (_: Exception) {
            started?.invoke(false)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        running = false
        stopped?.invoke(generation)
        super.onDestroy()
    }
}
