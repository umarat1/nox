package com.lumen.vpn

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream
import java.lang.ref.WeakReference
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Opens the system install confirm after an update download.
 * Success means the confirm activity was started from the resumed activity.
 * Starting it from the application context is dropped on Android 14 and used
 * to be reported as a finished update.
 */
object ApkInstall {
    private val activity = AtomicReference<WeakReference<Activity>?>(null)
    private val main = Handler(Looper.getMainLooper())
    @Volatile var pendingPath: String? = null

    fun attach(a: Activity) { activity.set(WeakReference(a)) }

    fun detach(a: Activity) {
        if (activity.get()?.get() === a) activity.set(null)
    }

    private fun foreground(): Activity? {
        val a = activity.get()?.get() ?: return null
        if (a.isFinishing || a.isDestroyed) return null
        return a
    }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
            return
        }
        val l = CountDownLatch(1)
        val box = AtomicReference<Exception?>(null)
        main.post {
            try {
                block()
            } catch (e: Exception) {
                box.set(e)
            } finally {
                l.countDown()
            }
        }
        if (!l.await(15, TimeUnit.SECONDS)) throw Exception("не удалось открыть установщик")
        box.get()?.let { throw it }
    }

    fun install(ctx: Context, path: String) {
        val file = File(path)
        if (!file.isFile) throw Exception("файл обновления не найден")
        if (file.length() < 4096) throw Exception("файл обновления повреждён (слишком маленький)")
        FileInputStream(file).use { inp ->
            val b = ByteArray(2)
            if (inp.read(b) != 2 || b[0] != 'P'.code.toByte() || b[1] != 'K'.code.toByte()) {
                throw Exception("файл обновления повреждён (это не APK)")
            }
        }
        if (Build.VERSION.SDK_INT >= 26 && !ctx.packageManager.canRequestPackageInstalls()) {
            pendingPath = path
            val settings = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + ctx.packageName))
            try {
                onMain {
                    val act = foreground()
                    if (act != null) act.startActivity(settings)
                    else ctx.startActivity(settings.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            } catch (e: Exception) {
                throw Exception("разрешите установку из этого источника")
            }
            throw Exception("разрешите установку из этого источника и нажмите «Повторить»")
        }
        val err = AtomicReference<String?>(null)
        val latch = CountDownLatch(1)
        var sessionId = -1
        var committed = false
        try {
            val installer = ctx.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setSize(file.length())
            params.setAppPackageName(ctx.packageName)
            if (Build.VERSION.SDK_INT >= 31) {
                params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
            }
            sessionId = installer.createSession(params)
            val session = installer.openSession(sessionId)
            try {
                session.openWrite("nox.apk", 0, file.length()).use { out ->
                    FileInputStream(file).use { it.copyTo(out) }
                    session.fsync(out)
                }
                var flags = PendingIntent.FLAG_UPDATE_CURRENT
                if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
                val pi = PendingIntent.getBroadcast(
                    ctx, sessionId, Intent(ctx, InstallStatusReceiver::class.java), flags
                )
                Waiter.arm(sessionId, latch, err)
                session.commit(pi.intentSender)
                committed = true
            } finally {
                try { session.close() } catch (_: Exception) {}
            }
            if (!latch.await(20, TimeUnit.SECONDS)) {
                throw Exception("система не открыла окно установки")
            }
            err.get()?.let { throw Exception(it) }
        } catch (e: Exception) {
            if (sessionId >= 0 && !committed) {
                try { ctx.packageManager.packageInstaller.abandonSession(sessionId) } catch (_: Exception) {}
            }
            val m = e.message ?: ""
            val hard = m.contains("не APK") || m.contains("не найден") || m.contains("повреждён") ||
                m.contains("разрешите") || m.contains("окно установки")
            if (hard) throw e
            val act = foreground() ?: throw Exception(if (m.isBlank()) "не удалось открыть установщик" else m)
            try {
                onMain { launchView(act, file) }
            } catch (e2: Exception) {
                throw Exception(e2.message ?: m.ifBlank { "не удалось открыть установщик" })
            }
        } finally {
            Waiter.clear(sessionId)
        }
    }

    fun onStatus(intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val sid = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                val act = foreground()
                if (confirm == null || act == null) {
                    Waiter.fail(sid, "система не открыла окно установки")
                    return
                }
                try {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    act.startActivity(confirm)
                    Waiter.ok(sid)
                } catch (e: Exception) {
                    Waiter.fail(sid, e.message ?: "не удалось открыть установщик")
                }
            }
            PackageInstaller.STATUS_SUCCESS -> Waiter.ok(sid)
            else -> {
                val text = msg?.takeIf { it.isNotBlank() } ?: "установщик вернул ошибку ($status)"
                Waiter.fail(sid, text)
            }
        }
    }

    /** Back from the unknown-sources screen. Caller must not be the UI thread. */
    fun resumePending(ctx: Context) {
        val p = pendingPath ?: return
        if (Build.VERSION.SDK_INT >= 26 && !ctx.packageManager.canRequestPackageInstalls()) return
        try {
            install(ctx, p)
            pendingPath = null
        } catch (_: Exception) {
        }
    }

    private fun launchView(act: Activity, file: File) {
        val uri = FileProvider.getUriForFile(act, "com.lumen.vpn.files", file)
        val view = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val seen = try {
            act.packageManager.queryIntentActivities(view, PackageManager.MATCH_DEFAULT_ONLY)
        } catch (_: Exception) {
            emptyList()
        }
        for (ri in seen) {
            act.grantUriPermission(ri.activityInfo.packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        act.startActivity(view)
    }

    private object Waiter {
        private val lock = Any()
        private var sid = -1
        private var latch: CountDownLatch? = null
        private var err: AtomicReference<String?>? = null

        fun arm(session: Int, l: CountDownLatch, e: AtomicReference<String?>) = synchronized(lock) {
            sid = session
            latch = l
            err = e
        }

        fun ok(session: Int) = finish(session, null)
        fun fail(session: Int, message: String) = finish(session, message)

        private fun finish(session: Int, message: String?) = synchronized(lock) {
            if (session != -1 && sid != -1 && sid != session) return
            err?.set(message)
            latch?.countDown()
        }

        fun clear(session: Int) = synchronized(lock) {
            if (sid == session) {
                sid = -1
                latch = null
                err = null
            }
        }
    }
}

class InstallStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ApkInstall.onStatus(intent)
    }
}
