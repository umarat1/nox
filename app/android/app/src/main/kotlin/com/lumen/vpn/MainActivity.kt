package com.lumen.vpn

import android.Manifest
import android.app.UiModeManager
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val exec = Executors.newCachedThreadPool()
    private var vpnResult: MethodChannel.Result? = null
    private var askedNotif = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Core.boot(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nox/core").setMethodCallHandler { call, res ->
            when (call.method) {
                "call" -> {
                    val m = call.argument<String>("m") ?: ""
                    val a = call.argument<String>("a") ?: "[]"
                    exec.execute {
                        val r = try { Core.call(m, a) } catch (e: Throwable) { "{\"e\":\"${e.message?.replace("\"", "'")}\"}" }
                        runOnUiThread { res.success(r) }
                    }
                }
                "prepareVpn" -> prepareVpn(res)
                "isTv" -> res.success(isTv())
                "openUrl" -> res.success(openUrl(call.argument<String>("url") ?: ""))
                "legacyState" -> exec.execute {
                    // Nox 0.7.x kept subscriptions/servers here (same package, same files dir)
                    val f = File(filesDir, "lumen-data.json")
                    val t = if (f.exists()) f.readText() else null
                    runOnUiThread { res.success(t) }
                }
                "legacyDone" -> {
                    File(filesDir, "lumen-data.json").renameTo(File(filesDir, "lumen-data.json.migrated"))
                    res.success(null)
                }
                else -> res.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    /** vless://… links and shared text (subscription URL or links): import into the engine. */
    private fun handleShare(i: Intent?) {
        val text = when (i?.action) {
            Intent.ACTION_VIEW -> i.dataString
            Intent.ACTION_SEND -> i.getStringExtra(Intent.EXTRA_TEXT)
            else -> null
        }?.trim()
        if (text.isNullOrEmpty()) return
        i?.action = Intent.ACTION_MAIN // not again on rotation
        exec.execute { Core.call("Import", org.json.JSONArray().put(text).toString()) }
    }

    private fun isTv(): Boolean {
        val ui = getSystemService(UiModeManager::class.java)
        return ui?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
    }

    private fun openUrl(url: String): Boolean = try {
        if (!url.startsWith("http")) false else {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        }
    } catch (_: Exception) {
        false // no browser (common on Android TV): Dart copies the link instead
    }

    private fun askNotifications() {
        if (Build.VERSION.SDK_INT >= 33 && !askedNotif &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            askedNotif = true
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 43)
        }
    }

    // VPN consent first, then (once) the notification permission, so the two system dialogs never stack.
    private fun prepareVpn(res: MethodChannel.Result) {
        val i = try { VpnService.prepare(this) } catch (_: Exception) { null }
        if (i == null) {
            askNotifications()
            res.success(true)
            return
        }
        vpnResult = res
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(i, 42)
        } catch (_: Exception) {
            vpnResult = null
            res.success(false)
        }
    }

    @Deprecated("Activity result API is not used by FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 42) {
            vpnResult?.success(resultCode == RESULT_OK)
            vpnResult = null
            if (resultCode == RESULT_OK) askNotifications()
        }
    }
}
