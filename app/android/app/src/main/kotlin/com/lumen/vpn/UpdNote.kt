package com.lumen.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/** Update progress in the shade (Загрузка 42% · 58 из 134 МБ, Проверка, Установка, ошибка). */
object UpdNote {
    private const val CH = "update"
    private const val ID = 7

    fun show(ctx: Context, state: String, pct: Int, text: String) {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (state == "clear" || state == "canceled") {
            nm.cancel(ID)
            return
        }
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CH) == null) {
            nm.createNotificationChannel(NotificationChannel(CH, "Обновления", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(ctx, 1,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, CH) else @Suppress("DEPRECATION") Notification.Builder(ctx)
        val title = when (state) {
            "download" -> if (pct >= 0) "Загрузка обновления · $pct%" else "Загрузка обновления"
            "verify" -> "Проверка обновления"
            "install", "done" -> "Установка обновления"
            "error" -> "Не удалось обновить Nox"
            else -> "Обновление Nox"
        }
        b.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setOnlyAlertOnce(true)
            .setOngoing(state == "download" || state == "verify" || state == "install")
            .setAutoCancel(state == "error" || state == "done")
        when (state) {
            "download" -> b.setProgress(100, pct.coerceAtLeast(0), pct < 0)
            "verify", "install" -> b.setProgress(0, 0, true)
        }
        try { nm.notify(ID, b.build()) } catch (_: SecurityException) {} // notifications off
    }
}
