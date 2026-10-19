package com.lumen.vpn

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.net.VpnService
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.lumen.core.noxcore.Host
import com.lumen.vpn.toggle.VpnTileService
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Called by the Go engine (any thread). */
class NoxHost(private val ctx: Context) : Host {
    override fun startService(tun: Boolean) {
        if (tun && VpnService.prepare(ctx) != null) {
            throw Exception("Нет разрешения на VPN — откройте Nox и подтвердите системный запрос")
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

    override fun protect(fd: Int): Boolean = NoxVpnService.instance?.protect(fd) ?: false

    override fun startNetMonitor() = NetMonitor.start(ctx)

    override fun stopNetMonitor() {}

    override fun getInterfaces(): String = NetMonitor.interfaces(ctx)

    override fun installApk(path: String) {
        // Android 8+: without «Install unknown apps» the system installer shows a dialog that
        // leads to Settings and drops the install on return. Ask for the permission first and
        // resume the install when the user comes back (MainActivity.onResume).
        if (Build.VERSION.SDK_INT >= 26 && !ctx.packageManager.canRequestPackageInstalls()) {
            pendingApk = path
            try {
                ctx.startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + ctx.packageName))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                return
            } catch (_: Exception) {
                pendingApk = null // some TV builds have no such screen: fall back to the installer
            }
        }
        launchInstaller(ctx, path)
    }

    companion object {
        @Volatile var pendingApk: String? = null

        fun launchInstaller(ctx: Context, path: String) {
            val uri = FileProvider.getUriForFile(ctx, "com.lumen.vpn.files", File(path))
            ctx.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            )
        }

        /** Back from the permission screen: continue the update if it was granted. */
        fun resumePending(ctx: Context) {
            val p = pendingApk ?: return
            if (Build.VERSION.SDK_INT >= 26 && !ctx.packageManager.canRequestPackageInstalls()) return
            pendingApk = null
            if (File(p).exists()) launchInstaller(ctx, p)
        }
    }

    override fun onStatus(status: String, server: String) {
        Core.status = status
        Core.server = server
        NoxVpnService.instance?.updateNotification()
        VpnTileService.refresh(ctx)
    }
}
