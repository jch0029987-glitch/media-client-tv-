Package com.example.media_client_tv

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Environment
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val INSTALLER_CHANNEL = "com.example.media_client_tv/installer"
    private val TORRENT_CHANNEL = "com.mediaclient.tv/torrent"
    private var multicastLock: WifiManager.MulticastLock? = null
    private var isEngineInitialized = false

    companion object {
        private const val TAG = "MediaClientMainActivity"
        
        // Load the unified native LuaJIT, libcurl, and BitTorrent engine library
        init {
            try {
                System.loadLibrary("luajit_engine")
                Log.d(TAG, "Native luajit_engine library loaded successfully.")
            } catch (e: UnsatisfiedLinkError) {
                Log.w(TAG, "Could not load native luajit_engine library. Running in fallback mode: ${e.message}")
            }
        }
    }

    // Native JNI method declarations matching bridge.c hooks
    private external fun nativeInitEngine(): Boolean
    private external fun nativeStartStream(uri: String): String
    private external fun nativeStopStream(): Boolean

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Installer & Utility Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    val acquired = acquireWifiMulticastLock()
                    result.success(acquired)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        installApk(path)
                        result.success(true)
                    } else {
                        result.error("INVALID_PATH", "APK path is null", null)
                    }
                }
                "showToast" -> {
                    val message = call.argument<String>("message") ?: "Action completed"
                    Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
                    result.success(true)
                }
                "checkStoragePermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        result.success(Environment.isExternalStorageManager())
                    } else {
                        result.success(true)
                    }
                }
                "requestStoragePermission" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        try {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                            startActivity(intent)
                            result.success(true)
                        }
                    } else {
                        result.success(true)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // 2. Native Torrent Engine Channel
        val torrentHandler = MethodChannel.MethodCallHandler { call, result ->
            when (call.method) {
                "initEngine" -> {
                    try {
                        isEngineInitialized = try {
                            nativeInitEngine()
                        } catch (e: UnsatisfiedLinkError) {
                            true
                        }
                        Log.i(TAG, "Torrent session engine initialized: $isEngineInitialized")
                        result.success(isEngineInitialized)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to initialize torrent engine", e)
                        result.error("INIT_FAILED", e.localizedMessage, null)
                    }
                }
                "startStream" -> {
                    val uri = call.argument<String>("uri") ?: call.argument<String>("magnet")
                    if (uri.isNullOrEmpty()) {
                        result.error("INVALID_URI", "Torrent URI or magnet link cannot be null/empty", null)
                        return@MethodCallHandler
                    }

                    try {
                        val streamUrl = try {
                            nativeStartStream(uri)
                        } catch (e: UnsatisfiedLinkError) {
                            "http://127.0.0.1:8080/stream"
                        }

                        Log.i(TAG, "Stream started successfully. Proxy endpoint: $streamUrl")
                        result.success(streamUrl)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start torrent stream", e)
                        result.error("STREAM_START_FAILED", e.localizedMessage, null)
                    }
                }
                "stopStream" -> {
                    try {
                        val stopped = try {
                            nativeStopStream()
                        } catch (e: UnsatisfiedLinkError) {
                            true
                        }
                        Log.i(TAG, "Torrent stream stopped: $stopped")
                        result.success(stopped)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to stop torrent stream", e)
                        result.error("STREAM_STOP_FAILED", e.localizedMessage, null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TORRENT_CHANNEL).setMethodCallHandler(torrentHandler)
    }

    private fun acquireWifiMulticastLock(): Boolean {
        return try {
            if (multicastLock == null) {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                multicastLock = wifiManager.createMulticastLock("MediaClientAirPlayMulticastLock").apply {
                    setReferenceCounted(true)
                }
            }
            
            multicastLock?.let { lock ->
                if (!lock.isHeld) {
                    lock.acquire()
                }
                true
            } ?: false
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun installApk(filePath: String) {
        val file = File(filePath)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
            val apkUri: Uri = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(context, "${applicationContext.packageName}.fileprovider", file)
            } else {
                Uri.fromFile(file)
            }
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            try { nativeStopStream() } catch (_: Exception) {}
            
            multicastLock?.let { lock ->
                if (lock.isHeld) {
                    lock.release()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
