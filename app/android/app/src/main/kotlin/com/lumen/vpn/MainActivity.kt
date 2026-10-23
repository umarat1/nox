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
import com.google.zxing.client.android.Intents
import com.journeyapps.barcodescanner.ScanOptions
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val exec = Executors.newCachedThreadPool()
    private var vpnResult: MethodChannel.Result? = null
    private var askedNotif = false
    private var captchaResult: MethodChannel.Result? = null
    private var scanResult: MethodChannel.Result? = null
    private var channel: MethodChannel? = null
    private var pendingPair: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Core.boot(this)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nox/core")
        channel = ch
        ch.setMethodCallHandler { call, res ->
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
                "setHighRefresh" -> { setHighRefresh(); res.success(null) }
                "setCompactHeight" -> { setCompactHeight(call.argument<Double>("dp") ?: 0.0); res.success(null) }
                "listApps" -> exec.execute {
                    val r = listApps()
                    runOnUiThread { res.success(r) }
                }
                "solveCaptcha" -> solveCaptcha(call.argument<String>("url") ?: "", res)
                "openUrl" -> res.success(openUrl(call.argument<String>("url") ?: ""))
                "legacyState" -> exec.execute {
                    // Nox 0.7.x kept subscriptions/servers here (same package, same files dir)
                    val f = File(filesDir, "lumen-data.json")
                    val t = if (f.exists()) f.readText() else null
                    runOnUiThread { res.success(t) }
                }
                "hasCamera" -> res.success(packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY))
                "scanQr" -> scanQr(res)
                "takePair" -> { res.success(pendingPair); pendingPair = null }
                "updNotify" -> {
                    UpdNote.show(this, call.argument<String>("state") ?: "clear",
                        call.argument<Int>("pct") ?: -1, call.argument<String>("text") ?: "")
                    res.success(null)
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

    override fun onResume() {
        super.onResume()
        NoxHost.resumePending(this) // update APK waiting for «Install unknown apps»
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
        if (text.startsWith("nox://pair", ignoreCase = true)) { // TV QR scanned with the system camera
            pendingPair = text
            channel?.invokeMethod("pair", text)
            return
        }
        exec.execute { Core.call("Import", org.json.JSONArray().put(text).toString()) }
    }

    /** Launchable apps for the split-tunnelling picker: package, label, 48px PNG icon. */
    private fun listApps(): List<Map<String, Any>> {
        val pm = packageManager
        val seen = HashMap<String, Map<String, Any>>()
        for (cat in listOf(Intent.CATEGORY_LAUNCHER, Intent.CATEGORY_LEANBACK_LAUNCHER)) {
            val q = Intent(Intent.ACTION_MAIN).addCategory(cat)
            for (ri in try { pm.queryIntentActivities(q, 0) } catch (_: Exception) { emptyList() }) {
                val ai = ri.activityInfo?.applicationInfo ?: continue
                val pkg = ai.packageName
                if (pkg == packageName || seen.containsKey(pkg)) continue
                val m = HashMap<String, Any>()
                m["pkg"] = pkg
                m["label"] = try { ai.loadLabel(pm).toString() } catch (_: Exception) { pkg }
                try {
                    val d = ai.loadIcon(pm)
                    val bmp = android.graphics.Bitmap.createBitmap(48, 48, android.graphics.Bitmap.Config.ARGB_8888)
                    val c = android.graphics.Canvas(bmp)
                    d.setBounds(0, 0, 48, 48); d.draw(c)
                    val out = java.io.ByteArrayOutputStream()
                    bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                    m["icon"] = out.toByteArray()
                } catch (_: Exception) {}
                seen[pkg] = m
            }
        }
        return seen.values.sortedBy { (it["label"] as String).lowercase() }
    }

    private fun solveCaptcha(url: String, res: MethodChannel.Result) {
        if (captchaResult != null) { res.success("error:busy"); return }
        captchaResult = res
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(Intent(this, CaptchaActivity::class.java).putExtra("url", url), 44)
        } catch (_: Exception) {
            captchaResult = null
            res.success("error:webview")
        }
    }

    // Camera permission is requested only here, right before scanning.
    private fun scanQr(res: MethodChannel.Result) {
        if (scanResult != null) { res.success("error:busy"); return }
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) { res.success("error:nocamera"); return }
        scanResult = res
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), 45)
        } else startScan()
    }

    private fun startScan() {
        val o = ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE)
            .setPrompt("Наведите камеру на QR-код")
            .setBeepEnabled(false).setOrientationLocked(false)
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(o.createScanIntent(this), 46)
        } catch (_: Exception) {
            scanResult?.success("error:nocamera"); scanResult = null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 45) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) startScan()
            else { scanResult?.success("error:denied"); scanResult = null }
        }
    }

    private fun setCompactHeight(dp: Double) {
        if (isTv()) return
        try {
            val lp = window.attributes
            if (dp > 0.0) {
                if (Build.VERSION.SDK_INT >= 30) {
                    try { setTranslucent(true) } catch (_: Exception) {}
                }
                val density = resources.displayMetrics.density
                val screenH = resources.displayMetrics.heightPixels
                val targetPx = (dp * density).toInt().coerceIn((220 * density).toInt(), screenH)
                lp.height = targetPx
                lp.gravity = android.view.Gravity.TOP
                lp.dimAmount = 0.35f
                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT))
            } else {
                lp.height = android.view.WindowManager.LayoutParams.MATCH_PARENT
                lp.gravity = android.view.Gravity.FILL
                lp.dimAmount = 0f
                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
                if (Build.VERSION.SDK_INT >= 30) {
                    try { setTranslucent(false) } catch (_: Exception) {}
                }
            }
            window.attributes = lp
        } catch (_: Exception) {}
    }

    private fun setHighRefresh() {
        if (Build.VERSION.SDK_INT < 23) return
        try {
            val display = if (Build.VERSION.SDK_INT >= 30) display else @Suppress("DEPRECATION") windowManager.defaultDisplay
            val modes = display?.supportedModes ?: return
            val best = modes.maxByOrNull { it.refreshRate } ?: return
            if (best.refreshRate < 60.5f) return
            // preferredDisplayModeId (API 23+) unlocks 90/120 Hz for vsync / the graph ticker
            val lp = window.attributes
            lp.preferredDisplayModeId = best.modeId
            window.attributes = lp
        } catch (_: Exception) {}
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
        if (requestCode == 44) {
            captchaResult?.success(data?.getStringExtra("r") ?: "error:cancelled")
            captchaResult = null
        }
        if (requestCode == 46) {
            scanResult?.success(if (resultCode == RESULT_OK) data?.getStringExtra(Intents.Scan.RESULT) else null)
            scanResult = null
        }
        if (requestCode == 42) {
            vpnResult?.success(resultCode == RESULT_OK)
            vpnResult = null
            if (resultCode == RESULT_OK) askNotifications()
        }
    }
}
