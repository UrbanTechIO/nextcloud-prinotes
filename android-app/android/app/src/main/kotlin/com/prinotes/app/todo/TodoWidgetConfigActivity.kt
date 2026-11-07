package com.prinotes.app.todo

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import org.json.JSONArray

/** Source picker: any mix of smart lists and categories. Runs when a widget is added and from its header. */
class TodoWidgetConfigActivity : Activity() {

    private val boxes = mutableListOf<Pair<String, CheckBox>>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) { finish(); return }

        val cfg = TodoWidgetData.config(this, widgetId)
        val chosen = mutableSetOf<String>()
        cfg.optJSONArray("sources")?.let { a -> for (i in 0 until a.length()) chosen += a.getString(i) }

        val dp = resources.displayMetrics.density
        fun px(v: Int) = (v * dp).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(20), px(24), px(20), px(20))
            setBackgroundColor(0xFF0F172A.toInt())
        }
        fun label(text: String, big: Boolean = false) = TextView(this).apply {
            this.text = text
            setTextColor(if (big) Color.WHITE else 0xFF94A3B8.toInt())
            textSize = if (big) 18f else 12f
            setPadding(0, px(if (big) 0 else 14), 0, px(6))
        }
        fun box(text: String, key: String, indent: Int) = CheckBox(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            isChecked = key in chosen
            setPadding(px(indent), 0, 0, 0)
            boxes += key to this
        }

        root.addView(label("Choose what this widget shows", big = true))
        root.addView(label("SMART LISTS"))
        for ((k, t) in listOf("today" to "Today", "important" to "Important", "planned" to "Planned (has a due date)", "all" to "All open tasks")) {
            root.addView(box(t, "smart:$k", 0))
        }

        val tree: JSONArray = TodoWidgetData.tree(this)
        root.addView(label("YOUR CATEGORIES"))
        if (tree.length() == 0) {
            root.addView(TextView(this).apply {
                text = "No categories yet. Open PriNotes once so your lists load."
                setTextColor(0xFFFCA5A5.toInt())
            })
        }
        for (i in 0 until tree.length()) {
            val o = tree.getJSONObject(i)
            root.addView(box(o.getString("title"), "list:${o.getInt("id")}", if (o.isNull("parentId")) 0 else 28))
        }

        val sub = Switch(this).apply {
            text = "Include sub-categories"
            setTextColor(Color.WHITE)
            isChecked = cfg.optBoolean("includeSub", true)
            setPadding(0, px(16), 0, px(8))
        }
        root.addView(sub)

        root.addView(Button(this).apply {
            text = "Save"
            setOnClickListener {
                val picked = boxes.filter { it.second.isChecked }.map { it.first }
                cfg.put("sources", JSONArray(picked.ifEmpty { listOf("smart:today") }))
                cfg.put("includeSub", sub.isChecked)
                TodoWidgetData.saveConfig(this@TodoWidgetConfigActivity, widgetId, cfg)
                redraw()
                setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId))
                finish()
            }
        })

        setContentView(ScrollView(this).apply { addView(root); setBackgroundColor(0xFF0F172A.toInt()) })
    }

    private fun redraw() {
        val mgr = AppWidgetManager.getInstance(this)
        for (cls in listOf(TodoWidgetMedium::class.java, TodoWidgetLarge::class.java)) {
            val ids = mgr.getAppWidgetIds(ComponentName(this, cls))
            if (ids.isNotEmpty()) {
                sendBroadcast(Intent(this, cls).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids))
            }
        }
    }
}
