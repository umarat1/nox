package com.lumen.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Starts the engine after boot / update; it connects by itself if «Автоподключение» is on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Core.boot(context)
    }
}
