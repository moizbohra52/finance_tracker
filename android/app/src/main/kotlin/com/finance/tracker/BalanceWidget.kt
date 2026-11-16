package com.finance.tracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.view.View
import android.widget.RemoteViews

// Home screen widget: current balance and this month's expense. The app
// sends ready-to-show text (HomeWidgetService.dart), already masked when App
// lock is on; until it has, the widget asks to open the app.
class BalanceWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        manager.updateAppWidget(ids, views(context))
    }

    companion object {
        private const val PREFS = "balance_widget"

        // Replaces what the widget shows; null clears it (signed out).
        fun save(context: Context, values: Map<*, *>?) {
            val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear()
            values?.forEach { (key, value) ->
                if (key is String && value is String) editor.putString(key, value)
            }
            editor.apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, BalanceWidget::class.java))
            if (ids.isNotEmpty()) manager.updateAppWidget(ids, views(context))
        }

        private fun views(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            fun text(key: String, fallback: Int) = prefs.getString(key, null) ?: context.getString(fallback)
            val note = text("note", R.string.widget_open_app)
            return RemoteViews(context.packageName, R.layout.balance_widget).apply {
                setTextViewText(R.id.balance_label, text("balanceLabel", R.string.widget_balance))
                setTextViewText(R.id.balance, text("balance", R.string.widget_no_value))
                setTextViewText(R.id.expense_label, text("expenseLabel", R.string.widget_expense))
                setTextViewText(R.id.expense, text("expense", R.string.widget_no_value))
                setTextViewText(R.id.note, note)
                setViewVisibility(R.id.note, if (note.isEmpty()) View.GONE else View.VISIBLE)
                val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
                setOnClickPendingIntent(
                    android.R.id.background,
                    PendingIntent.getActivity(
                        context,
                        0,
                        launch,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    ),
                )
            }
        }
    }
}
