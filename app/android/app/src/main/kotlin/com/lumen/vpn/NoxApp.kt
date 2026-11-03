package com.lumen.vpn

import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.lumen.core.noxcore.Noxcore
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipFile

class NoxApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Core.boot(this)
    }
}

/** One engine per process: Go (gomobile) behind Noxcore; Flutter, the tile and the service share it. */
object Core {
    @Volatile var status = "disconnected"
    @Volatile var server = ""
    private var booted = false

    fun boot(ctx: Context) = synchronized(this) {
        if (booted) return
        val app = ctx.applicationContext
        val rules = File(app.filesDir, "rules").apply { mkdirs() }
        app.assets.list("rules")?.forEach { n ->
            val dst = File(rules, n)
            app.assets.open("rules/$n").use { inp ->
                val bytes = inp.readBytes()
                if (!dst.exists() || dst.length() != bytes.size.toLong()) dst.writeBytes(bytes)
            }
        }
        NetMonitor.start(app) // system DNS + default interface before anything dials out
        if (Build.SUPPORTED_ABIS.isNotEmpty()) Noxcore.setABI(Build.SUPPORTED_ABIS[0])
        // extractNativeLibs=false: qwdtt/xray/naive are mmap'd inside the APK, not copied
        // to nativeLibraryDir. Materialise them once per version so the engine can exec
        // them (via the system linker — the app data dir is noexec on Android 10+).
        Noxcore.init(File(app.filesDir, "nox").path, binDir(app), rules.path, NoxHost(app))
        booted = true
    }

    private fun binDir(app: Context): String {
        val out = File(app.filesDir, "noxbin")
        out.mkdirs()
        val apk = app.applicationInfo.sourceDir ?: return app.applicationInfo.nativeLibraryDir
        val names = listOf("libqwdtt.so", "libxray.so", "libnaive.so")
        ZipFile(apk).use { zip ->
            val abi = Build.SUPPORTED_ABIS.firstOrNull { a -> zip.getEntry("lib/$a/libqwdtt.so") != null }
                ?: return app.applicationInfo.nativeLibraryDir
            val ver = try {
                val info = if (Build.VERSION.SDK_INT >= 33) {
                    app.packageManager.getPackageInfo(app.packageName, PackageManager.PackageInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION")
                    app.packageManager.getPackageInfo(app.packageName, 0)
                }
                val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
                "$code:$abi"
            } catch (_: Exception) {
                abi
            }
            val stamp = File(out, ".ver")
            val ready = stamp.isFile && stamp.readText() == ver && names.all { n ->
                val f = File(out, n)
                val e = zip.getEntry("lib/$abi/$n")
                f.isFile && e != null && f.length() == e.size
            }
            if (!ready) {
                for (n in names) {
                    val e = zip.getEntry("lib/$abi/$n") ?: continue
                    val dst = File(out, n)
                    zip.getInputStream(e).use { input -> FileOutputStream(dst).use { input.copyTo(it) } }
                    dst.setReadable(true, false)
                    dst.setExecutable(true, false)
                }
                stamp.writeText(ver)
            }
        }
        return out.path
    }

    /** Engine RPC (blocking; never call on the main thread). */
    fun call(method: String, args: String = "[]"): String = Noxcore.call(method, args)
}
