package com.prinotes.app.todo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.prinotes.app.R

abstract class BaseTodoWidget(private val layout: Int, private val hasAddRow: Boolean) : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, build(context, id))
        manager.notifyAppWidgetViewDataChanged(ids, R.id.list)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        for (id in ids) TodoWidgetData.deleteConfig(context, id)
    }

    private fun activity(context: Context, id: Int, offset: Int, cls: Class<*>): PendingIntent =
        PendingIntent.getActivity(
            context, id * 10 + offset,
            Intent(context, cls).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun build(context: Context, id: Int): RemoteViews {
        val rv = RemoteViews(context.packageName, layout)
        rv.setTextViewText(R.id.header_title, TodoWidgetData.header(context, id))
        rv.setTextViewText(
            R.id.empty,
            if (TodoWidgetData.allSourcesMissing(context, id)) "Category not found.\nTap the title to choose again."
            else "Nothing to do",
        )

        val adapter = Intent(context, TodoWidgetService::class.java)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        adapter.data = Uri.parse(adapter.toUri(Intent.URI_INTENT_SCHEME))
        rv.setRemoteAdapter(R.id.list, adapter)
        rv.setEmptyView(R.id.list, R.id.empty)

        // Row taps: one mutable template, each row fills in what it needs (op + task id).
        rv.setPendingIntentTemplate(
            R.id.list,
            PendingIntent.getActivity(
                context, id * 10,
                Intent(context, TodoWidgetActionActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            ),
        )
        rv.setOnClickPendingIntent(R.id.header_title, activity(context, id, 1, TodoWidgetConfigActivity::class.java))
        rv.setOnClickPendingIntent(R.id.add_btn, activity(context, id, 2, TodoWidgetQuickAddActivity::class.java))
        if (hasAddRow) rv.setOnClickPendingIntent(R.id.add_row, activity(context, id, 3, TodoWidgetQuickAddActivity::class.java))
        return rv
    }
}

class TodoWidgetMedium : BaseTodoWidget(R.layout.todo_widget_medium, false)
class TodoWidgetLarge : BaseTodoWidget(R.layout.todo_widget_large, true)
