package com.lumen.vpn

import android.app.Application
import android.content.Context
import android.os.Build
import com.lumen.core.noxcore.Noxcore
import java.io.File

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
        Noxcore.init(File(app.filesDir, "nox").path, app.applicationInfo.nativeLibraryDir, rules.path, NoxHost(app))
        booted = true
    }

    /** Engine RPC (blocking; never call on the main thread). */
    fun call(method: String, args: String = "[]"): String = Noxcore.call(method, args)
}
