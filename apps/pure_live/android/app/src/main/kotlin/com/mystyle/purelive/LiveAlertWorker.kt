package com.mystyle.purelive

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * "开播提醒" after Android froze or cleared the app (O01.2, in
 * docs/O-Android系统集成/O01-通知和前台服务; V01.1 L1, L14).
 *
 * WorkManager runs this every 15 minutes or later (the system decides;
 * with a network). It starts a Flutter engine of its own on
 * `liveAlertWorkerMain` (`lib/app/live_alert_worker.dart`), which reads the
 * file the app shares with it, asks for the covered follows, posts through
 * `pure_live/live_alerts` ([AppChannelsPlugin], [LiveAlerts]) and answers
 * `done`; the engine then ends. Four minutes at most.
 *
 * `pure_live/live_alert_worker` `schedule` (`on`) on the app's engine turns
 * the periodic work on (kept when already on) or off ([LiveAlertWorkerPlugin]).
 */
class LiveAlertWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result {
        val done = CompletableDeferred<Unit>()
        val engine = withContext(Dispatchers.Main) {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            FlutterEngine(applicationContext).also { engine ->
                if (!engine.plugins.has(AppChannelsPlugin::class.java)) engine.plugins.add(AppChannelsPlugin())
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
                    if (call.method == "done") done.complete(Unit)
                    result.success(null)
                }
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), LIBRARY, ENTRY),
                )
            }
        }
        return try {
            withTimeoutOrNull(TimeUnit.MINUTES.toMillis(4)) { done.await() }
            Result.success()
        } finally {
            withContext(Dispatchers.Main) { engine.destroy() }
        }
    }

    companion object {
        const val CHANNEL = "pure_live/live_alert_worker"
        private const val LIBRARY = "package:pure_live/app/live_alert_worker.dart"
        private const val ENTRY = "liveAlertWorkerMain"
        private const val WORK = "pure_live_live_alerts"

        /** Turns the periodic check on (kept as it is when on) or off. */
        fun schedule(context: Context, on: Boolean) {
            val manager = WorkManager.getInstance(context)
            if (!on) {
                manager.cancelUniqueWork(WORK)
                return
            }
            val request = PeriodicWorkRequestBuilder<LiveAlertWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            manager.enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}

/** `pure_live/live_alert_worker` on the app's engine: `schedule` (`on`). */
internal class LiveAlertWorkerPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, LiveAlertWorker.CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        try {
                            LiveAlertWorker.schedule(context, call.argument<Boolean>("on") == true)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("schedule", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
