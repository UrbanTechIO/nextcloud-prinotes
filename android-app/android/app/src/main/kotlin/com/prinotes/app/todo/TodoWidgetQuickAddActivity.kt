package com.prinotes.app.todo

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.graphics.Color
import android.os.Bundle
import android.view.WindowManager
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.TextView

/** Quick add from a widget: title, category (skipped when the widget shows one category), due today. */
class TodoWidgetQuickAddActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE)
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0)
        val tree = TodoWidgetData.tree(this)
        val dp = resources.displayMetrics.density
        fun px(v: Int) = (v * dp).toInt()

        val ids = mutableListOf<Int>()
        val labels = mutableListOf<String>()
        var inbox = -1
        for (i in 0 until tree.length()) {
            val o = tree.getJSONObject(i)
            ids += o.getInt("id")
            labels += TodoWidgetData.listPathOf(this, o.getInt("id"))
            if (o.optBoolean("isSystem")) inbox = o.getInt("id")
        }

        val cfg = TodoWidgetData.config(this, widgetId)
        val srcs = cfg.optJSONArray("sources")
        val listSources = mutableListOf<Int>()
        var hasSmart = false
        if (srcs != null) for (i in 0 until srcs.length()) {
            val s = srcs.getString(i)
            if (s.startsWith("list:")) s.removePrefix("list:").toIntOrNull()?.let { if (it in ids) listSources += it } else hasSmart = true
        }
        val singleList = if (listSources.size == 1 && !hasSmart) listSources[0] else null

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(px(20), px(20), px(20), px(12))
        }
        root.addView(TextView(this).apply { text = "New task"; textSize = 18f; setTextColor(Color.WHITE) })
        val title = EditText(this).apply { hint = "Add a task…"; setTextColor(Color.WHITE); setHintTextColor(0xFF94A3B8.toInt()); setSingleLine() }
        root.addView(title)

        val spinner = Spinner(this)
        if (ids.isEmpty()) {
            root.addView(TextView(this).apply { text = "Open PriNotes once so your lists load."; setTextColor(0xFFFCA5A5.toInt()) })
        } else if (singleList == null) {
            spinner.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, labels)
            val last = cfg.optInt("lastAddListId", -1)
            val pre = when {
                last in ids -> last
                listSources.isNotEmpty() -> listSources[0]
                inbox != -1 -> inbox
                else -> ids[0]
            }
            spinner.setSelection(ids.indexOf(pre).coerceAtLeast(0))
            root.addView(spinner)
        }

        val due = CheckBox(this).apply {
            text = "Due today"
            setTextColor(Color.WHITE)
            isChecked = srcs?.let { a -> (0 until a.length()).any { a.getString(it) == "smart:today" } } ?: false
        }
        root.addView(due)

        val buttons = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = android.view.Gravity.END }
        buttons.addView(Button(this).apply { text = "Cancel"; setOnClickListener { finish() } })
        buttons.addView(Button(this).apply {
            text = "Add"
            isEnabled = ids.isNotEmpty()
            setOnClickListener {
                val t = title.text.toString().trim()
                if (t.isEmpty()) return@setOnClickListener
                val listId = singleList ?: ids[spinner.selectedItemPosition.coerceAtLeast(0)]
                TodoWidgetData.queueAdd(this@TodoWidgetQuickAddActivity, t, listId, due.isChecked, widgetId)
                finish()
            }
        })
        root.addView(buttons)
        setContentView(root)
    }
}
