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
        fun refresh(ctx: Context) = try {
            requestListeningState(ctx, ComponentName(ctx, VpnTileService::class.java))
        } catch (_: Exception) {}
    }

    override fun onStartListening() = update()

    override fun onClick() {
        Core.boot(this)
        if (Core.status == "connected" || Core.status == "connecting") {
            thread { Core.call("Disconnect") }
            return
        }
        if (VpnService.prepare(this) != null) { // permission dialog needs the app
            val i = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE))
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(i)
            }
            return
        }
        thread { Core.call("Connect") }
    }

    private fun update() {
        val t = qsTile ?: return
        t.state = if (Core.status == "connected") Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        t.label = "Nox"
        if (Build.VERSION.SDK_INT >= 29) t.subtitle = if (Core.status == "connected") Core.server else null
        t.updateTile()
    }
}
