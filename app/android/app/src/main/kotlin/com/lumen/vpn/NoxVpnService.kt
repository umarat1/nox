package com.lumen.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import com.lumen.core.noxcore.Noxcore
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import kotlin.concurrent.thread

/**
 * Foreground VpnService. sing-box (libbox, in the Go engine) asks for the TUN through
 * NoxHost.openTun; the app itself is excluded from the VPN so its own sockets (sing-box
 * outbounds, qwdtt, pings, subscription updates) use the physical network.
 */
class NoxVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.lumen.vpn.START"
        const val ACTION_STOP = "com.lumen.vpn.STOP"
        private const val CH = "vpn"
        private const val NID = 1
        @Volatile var instance: NoxVpnService? = null
        @Volatile var ready: CountDownLatch? = null
    }

    private var pfd: ParcelFileDescriptor? = null
    private val main = Handler(Looper.getMainLooper())
    private val stopper = Runnable {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Core.boot(this)
        when (intent?.action) {
            ACTION_STOP -> {
                thread { Core.call("Disconnect") }
                if (instance == null) stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                startFg()
                instance = this
                ready?.countDown()
                return START_NOT_STICKY
            }
            else -> { // always-on VPN / system restart
                startFg()
                instance = this
                thread { Core.call("Connect") }
                return START_NOT_STICKY
            }
        }
    }

    fun keep() = main.removeCallbacks(stopper)

    private fun startFg() {
        main.removeCallbacks(stopper)
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CH, "VPN", NotificationManager.IMPORTANCE_LOW))
        }
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NID, notification())
        }
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, NoxVpnService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        val text = when (Core.status) {
            "connected" -> if (Core.server.isNotEmpty()) "Подключено · ${Core.server}" else "Подключено"
            "connecting" -> "Подключение…"
            "disconnecting" -> "Отключение…"
            else -> "Nox"
        }
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CH) else @Suppress("DEPRECATION") Notification.Builder(this)
        return b.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Nox")
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .addAction(Notification.Action.Builder(null, "Отключить", stop).build())
            .build()
    }

    fun updateNotification() {
        if (instance === this) getSystemService(NotificationManager::class.java).notify(NID, notification())
    }

    private fun each(a: JSONArray?, f: (String) -> Unit) {
        if (a == null) return
        for (i in 0 until a.length()) f(a.getString(i))
    }

    private fun prefix(s: String): Pair<String, Int> {
        val i = s.lastIndexOf('/')
        return s.substring(0, i) to s.substring(i + 1).toInt()
    }

    fun openTun(o: JSONObject): Int {
        val b = Builder().setSession("Nox").setMtu(o.optInt("mtu", 9000))
        var v6 = false
        each(o.optJSONArray("addr4")) { val (a, p) = prefix(it); b.addAddress(a, p) }
        each(o.optJSONArray("addr6")) { val (a, p) = prefix(it); b.addAddress(a, p); v6 = true }
        var r4 = 0
        var r6 = 0
        each(o.optJSONArray("routes4")) { val (a, p) = prefix(it); b.addRoute(a, p); r4++ }
        if (v6) each(o.optJSONArray("routes6")) { val (a, p) = prefix(it); b.addRoute(a, p); r6++ }
        if (o.optBoolean("autoRoute")) {
            if (r4 == 0) b.addRoute("0.0.0.0", 0)
            if (v6 && r6 == 0) b.addRoute("::", 0)
        }
        each(o.optJSONArray("dns")) { b.addDnsServer(it) }
        // Per-app split: "include" = only these apps use the VPN (Nox itself is never in the
        // list, so it stays outside); otherwise everything except Nox and "exclude".
        val only = mutableListOf<String>()
        each(o.optJSONArray("include")) { if (it != packageName) only.add(it) }
        var allowed = 0
        for (p in only) try { b.addAllowedApplication(p); allowed++ } catch (_: Exception) {}
        if (allowed == 0) {
            val skip = mutableSetOf(packageName)
            each(o.optJSONArray("exclude")) { skip.add(it) }
            for (p in skip) try { b.addDisallowedApplication(p) } catch (_: Exception) {}
        }
        if (Build.VERSION.SDK_INT >= 29) {
            b.setMetered(false)
            if (o.optBoolean("httpProxy")) {
                val bypass = mutableListOf<String>()
                each(o.optJSONArray("bypass")) { bypass.add(it) }
                b.setHttpProxy(ProxyInfo.buildDirectProxy(o.getString("proxyHost"), o.getInt("proxyPort"), bypass))
            }
        }
        val p = b.establish() ?: throw Exception("Система не дала создать VPN (нет разрешения)")
        pfd?.close()
        pfd = p
        return p.fd
    }

    /** Tunnel down; the service lingers briefly so a reconnect does not restart it. */
    fun shutdown() {
        main.post {
            pfd?.close()
            pfd = null
            main.removeCallbacks(stopper)
            main.postDelayed(stopper, 1500)
        }
    }

    override fun onRevoke() {
        thread { Noxcore.vpnStopped("VPN отключён системой или другим VPN-приложением") }
        shutdown()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        pfd?.close()
        pfd = null
        super.onDestroy()
    }
}
