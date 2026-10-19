package com.lumen.vpn.toggle

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.lumen.vpn.Core
import com.lumen.vpn.MainActivity
import kotlin.concurrent.thread

/** Quick-settings tile (same component name as in Nox 0.7.x, so an added tile keeps working). */
class VpnTileService : TileService() {
    companion object {
        /** The tile while the shade shows it (status pushes must repaint it directly then). */
        @Volatile private var live: VpnTileService? = null

        fun refresh(ctx: Context) {
            val t = live
            if (t != null) {
                android.os.Handler(android.os.Looper.getMainLooper()).post { t.update() }
                return
            }
            try {
                requestListeningState(ctx, ComponentName(ctx, VpnTileService::class.java))
            } catch (_: Exception) {}
        }
    }

    override fun onStartListening() {
        live = this
        update()
    }

    override fun onStopListening() {
        if (live === this) live = null
    }

    override fun onTileAdded() = update()

    override fun onClick() {
        Core.boot(this)
        if (Core.status == "connected" || Core.status == "connecting") {
            show("disconnecting")
            thread { Core.call("Disconnect") }
            return
        }
        // VPN permission not granted yet, or nothing selected: the app shows the system dialog / list
        if (VpnService.prepare(this) != null || Core.server.isEmpty()) {
            openApp()
            return
        }
        show("connecting")
        thread {
            val r = Core.call("Connect")
            if (r.contains("\"e\"")) android.os.Handler(mainLooper).post { openApp() }
        }
    }

    private fun openApp() {
        val i = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(i)
        }
    }

    private fun update() {
        Core.boot(this) // tile may be the first thing to start the process: status + server come within ~1 s
        show(Core.status)
    }

    private fun show(st: String) {
        val t = qsTile ?: return
        val on = st == "connected" || st == "connecting"
        t.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        t.label = "Nox"
        val sub = when (st) {
            "connecting" -> "Подключение…"
            "disconnecting" -> "Отключение…"
            "connected" -> Core.server.ifEmpty { "Подключено" }
            else -> Core.server.ifEmpty { "Отключено" }
        }
        if (Build.VERSION.SDK_INT >= 29) t.subtitle = sub
        t.contentDescription = "Nox: " + sub
        t.updateTile()
    }
}
