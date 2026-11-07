package com.prinotes.app.todo

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.prinotes.app.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class TodoWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0))

    private class Factory(private val ctx: Context, private val widgetId: Int) : RemoteViewsFactory {
        private var rows: List<TodoWidgetData.Row> = emptyList()

        override fun onCreate() {}
        override fun onDataSetChanged() { rows = TodoWidgetData.rows(ctx, widgetId) }
        override fun onDestroy() {}
        override fun getCount() = rows.size
        override fun getViewTypeCount() = 1
        override fun hasStableIds() = true
        override fun getItemId(position: Int) = rows[position].id.toLong()
        override fun getLoadingView(): RemoteViews? = null

        override fun getViewAt(position: Int): RemoteViews {
            val r = rows[position]
            val rv = RemoteViews(ctx.packageName, R.layout.todo_widget_row)
            rv.setTextViewText(R.id.title, r.title)

            val parts = mutableListOf<String>()
            if (r.path.isNotEmpty()) parts += r.path
            if (r.overdue) parts += "Overdue" else if (r.dueDate != null) parts += r.dueDate
            if (r.remindAt != null) parts += "⏰ " + SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(r.remindAt * 1000))
            rv.setTextViewText(R.id.sub, parts.joinToString(" · "))
            rv.setTextColor(R.id.sub, if (r.overdue) 0xFFFCA5A5.toInt() else 0xFF94A3B8.toInt())
            rv.setViewVisibility(R.id.star, if (r.important) android.view.View.VISIBLE else android.view.View.GONE)

            rv.setOnClickFillInIntent(R.id.check, Intent().putExtra("op", "complete").putExtra("id", r.id))
            rv.setOnClickFillInIntent(R.id.row_text, Intent().putExtra("op", "open").putExtra("id", r.id))
            return rv
        }
    }
}
