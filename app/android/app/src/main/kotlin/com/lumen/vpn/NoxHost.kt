package com.lumen.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
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

    override fun resolve(host: String): String = NetMonitor.resolve(ctx, host)

    override fun installApk(path: String) {
        // REQUEST_INSTALL_PACKAGES made Play Protect treat this VPN as an installer and,
        // together with a 187 MB native-lib extract, hung the OxygenOS installer. The
        // verified APK is published to Downloads; the system Files app installs it.
        val src = File(path)
        if (!src.isFile) throw Exception("файл обновления не найден")
        val name = if (src.name.endsWith(".apk")) src.name else "Nox-update.apk"
        if (Build.VERSION.SDK_INT >= 29) {
            publishDownloads(ctx, src, name)
            return
        }
        launchInstaller(ctx, path)
    }

    private fun publishDownloads(ctx: Context, src: File, name: String) {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, "application/vnd.android.package-archive")
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = ctx.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw Exception("не удалось сохранить обновление в «Загрузки»")
        ctx.contentResolver.openOutputStream(uri)?.use { out -> src.inputStream().use { it.copyTo(out) } }
            ?: throw Exception("не удалось записать обновление в «Загрузки»")
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        ctx.contentResolver.update(uri, values, null, null)
        val note = notifyDownload(ctx, name)
        val opened = try {
            ctx.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            )
            true
        } catch (_: Exception) {
            false
        }
        if (!opened && !note) {
            throw Exception("обновление сохранено в «Загрузки» ($name). Откройте файл и подтвердите установку")
        }
    }

    private fun notifyDownload(ctx: Context, name: String): Boolean = try {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return false
        val ch = "update-ready"
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(ch) == null) {
            nm.createNotificationChannel(NotificationChannel(ch, "Файл обновления", NotificationManager.IMPORTANCE_HIGH))
        }
        val open = PendingIntent.getActivity(
            ctx, 3,
            Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, ch) else @Suppress("DEPRECATION") Notification.Builder(ctx)
        nm.notify(8, b.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Обновление Nox скачано")
            .setContentText("Откройте $name в «Загрузках» и подтвердите установку")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build())
        true
    } catch (_: Exception) {
        false
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
