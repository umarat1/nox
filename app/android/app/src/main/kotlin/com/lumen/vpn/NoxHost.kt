package com.lumen.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
import com.lumen.core.noxcore.Host
import com.lumen.vpn.toggle.VpnTileService
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Called by the Go engine (any thread). */
class NoxHost(private val ctx: Context) : Host {
    override fun startService(tun: Boolean) {
        if (tun && VpnService.prepare(ctx) != null) {
            throw Exception("Нет разрешения на VPN — откройте ПРОКСИ+ и подтвердите системный запрос")
        }
        NoxVpnService.instance?.let { it.keep(); return } // reconnect: keep the foreground service
        val latch = CountDownLatch(1)
        NoxVpnService.ready = latch
        ContextCompat.startForegroundService(ctx, Intent(ctx, NoxVpnService::class.java).setAction(NoxVpnService.ACTION_START))
        if (!latch.await(10, TimeUnit.SECONDS)) throw Exception("VPN-служба не запустилась")
    }

    override fun stopService() {
        NoxVpnService.instance?.shutdown()
    }

    override fun openTun(optionsJSON: String): Int {
        val s = NoxVpnService.instance ?: throw Exception("VPN-служба не запущена")
        return s.openTun(JSONObject(optionsJSON))
    }

    override fun protect(fd: Int): Boolean {
        NetMonitor.bindSocket(ctx, fd)
        return NoxVpnService.instance?.protect(fd) ?: false
    }

    override fun startNetMonitor() = NetMonitor.start(ctx)

    override fun stopNetMonitor() {}

    override fun getInterfaces(): String = NetMonitor.interfaces(ctx)

    override fun resolve(host: String): String = NetMonitor.resolve(ctx, host)

    override fun installApk(path: String) {
        ApkInstall.install(ctx, path)
    }

    override fun netMetered(): Int = NetMonitor.metered(ctx)

    /** 2.3.2: background download finished and verified — «Обновление готово». */
    override fun updateReady(version: String) {
        UpdNote.show(ctx, "ready", 100, "ПРОКСИ+ $version — нажмите, чтобы установить")
    }

    override fun onStatus(status: String, server: String) {
        Core.status = status
        Core.server = server
        NoxVpnService.instance?.updateNotification()
        VpnTileService.refresh(ctx)
    }
}
