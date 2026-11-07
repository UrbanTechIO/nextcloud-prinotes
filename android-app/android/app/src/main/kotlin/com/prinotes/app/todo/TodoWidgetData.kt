package com.prinotes.app.todo

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Widget data layer. Flutter writes the snapshot (`todo_tree`, `todo_tasks`) into the
 * shared HomeWidget preferences; the widget only reads it, so it never needs the network.
 * Taps are applied optimistically to the snapshot and queued (`todo_queue`) for Flutter,
 * which writes them to the real database and syncs. The native side never touches SQLite.
 */
object TodoWidgetData {
    private const val PREFS = "HomeWidgetPreferences"

    data class Row(
        val id: Int,
        val title: String,
        val path: String,
        val dueDate: String?,
        val remindAt: Long?,
        val important: Boolean,
        val overdue: Boolean,
    )

    fun prefs(c: Context): SharedPreferences = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun arr(c: Context, key: String): JSONArray =
        try { JSONArray(prefs(c).getString(key, "[]")) } catch (e: Exception) { JSONArray() }

    fun tree(c: Context) = arr(c, "todo_tree")
    fun tasks(c: Context) = arr(c, "todo_tasks")

    fun today(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    // ── Per-widget configuration ───────────────────────────────────────────────

    fun config(c: Context, widgetId: Int): JSONObject {
        val raw = prefs(c).getString("widget_$widgetId", null)
        return try { JSONObject(raw!!) } catch (e: Exception) {
            JSONObject().put("sources", JSONArray().put("smart:today")).put("includeSub", true)
        }
    }

    fun saveConfig(c: Context, widgetId: Int, cfg: JSONObject) {
        prefs(c).edit().putString("widget_$widgetId", cfg.toString()).apply()
    }

    fun deleteConfig(c: Context, widgetId: Int) {
        prefs(c).edit().remove("widget_$widgetId").apply()
    }

    private fun sources(cfg: JSONObject): List<String> {
        val a = cfg.optJSONArray("sources") ?: return listOf("smart:today")
        return (0 until a.length()).map { a.getString(it) }
    }

    private fun listTitle(c: Context, id: Int): String? {
        val t = tree(c)
        for (i in 0 until t.length()) if (t.getJSONObject(i).getInt("id") == id) return t.getJSONObject(i).getString("title")
        return null
    }

    private fun smartLabel(key: String) = when (key) {
        "today" -> "Today"; "important" -> "Important"; "planned" -> "Planned"; else -> "All tasks"
    }

    private fun sourceName(c: Context, s: String): String? =
        if (s.startsWith("smart:")) smartLabel(s.removePrefix("smart:"))
        else listTitle(c, s.removePrefix("list:").toIntOrNull() ?: -1)

    fun header(c: Context, widgetId: Int): String {
        val names = sources(config(c, widgetId)).mapNotNull { sourceName(c, it) }
        if (names.isEmpty()) return "To-Do"
        return if (names.size == 1) names[0] else "${names[0]} +${names.size - 1}"
    }

    /** True when every list source the widget was set to has disappeared (deleted category). */
    fun allSourcesMissing(c: Context, widgetId: Int): Boolean {
        val s = sources(config(c, widgetId))
        return s.isNotEmpty() && s.none { sourceName(c, it) != null }
    }

    /** Ids of the given list and, if [includeSub], its sub-lists. */
    private fun listIds(c: Context, id: Int, includeSub: Boolean): Set<Int> {
        val ids = mutableSetOf(id)
        if (includeSub) {
            val t = tree(c)
            for (i in 0 until t.length()) {
                val o = t.getJSONObject(i)
                if (!o.isNull("parentId") && o.getInt("parentId") == id) ids.add(o.getInt("id"))
            }
        }
        return ids
    }

    fun rows(c: Context, widgetId: Int): List<Row> {
        val cfg = config(c, widgetId)
        val srcs = sources(cfg)
        val includeSub = cfg.optBoolean("includeSub", true)
        val today = today()
        val listSet = mutableSetOf<Int>()
        for (s in srcs) if (s.startsWith("list:")) s.removePrefix("list:").toIntOrNull()?.let { listSet += listIds(c, it, includeSub) }

        val all = tasks(c)
        val seen = mutableSetOf<Int>()
        val out = mutableListOf<Row>()
        for (i in 0 until all.length()) {
            val t = all.getJSONObject(i)
            val id = t.getInt("id")
            val due = if (t.isNull("dueDate")) null else t.getString("dueDate")
            val match = srcs.any { s ->
                when (s) {
                    "smart:today" -> due != null && due <= today
                    "smart:important" -> t.optBoolean("important")
                    "smart:planned" -> due != null
                    "smart:all" -> true
                    else -> t.optInt("listId", -1) in listSet
                }
            }
            if (!match || !seen.add(id)) continue
            out += Row(
                id, t.getString("title"), t.optString("listPath", ""), due,
                if (t.isNull("remindAt")) null else t.getLong("remindAt"),
                t.optBoolean("important"), due != null && due < today,
            )
        }
        return out.sortedWith(
            compareBy<Row>({ !it.overdue }, { it.dueDate ?: "9999-99-99" }, { it.path }),
        )
    }

    // ── Optimistic actions + hand-off to Flutter ───────────────────────────────

    private fun appendQueue(c: Context, op: JSONObject) {
        val q = arr(c, "todo_queue")
        q.put(op)
        prefs(c).edit().putString("todo_queue", q.toString()).apply()
    }

    fun queueComplete(c: Context, taskId: Int) {
        val t = tasks(c)
        val kept = JSONArray()
        for (i in 0 until t.length()) if (t.getJSONObject(i).getInt("id") != taskId) kept.put(t.getJSONObject(i))
        prefs(c).edit().putString("todo_tasks", kept.toString()).apply()
        appendQueue(c, JSONObject().put("op", "complete").put("id", taskId))
        refreshAll(c)
    }

    fun queueAdd(c: Context, title: String, listId: Int, dueToday: Boolean, widgetId: Int) {
        val due: String? = if (dueToday) today() else null
        val tempId = -((System.currentTimeMillis() % 1_000_000_000L).toInt() + 1)
        val path = listPathOf(c, listId)
        val t = tasks(c)
        t.put(
            JSONObject().put("id", tempId).put("title", title).put("listId", listId)
                .put("listPath", path).put("dueDate", due ?: JSONObject.NULL)
                .put("remindAt", JSONObject.NULL).put("important", false),
        )
        prefs(c).edit().putString("todo_tasks", t.toString()).apply()
        appendQueue(c, JSONObject().put("op", "add").put("title", title).put("listId", listId).put("due", due ?: JSONObject.NULL))
        if (widgetId > 0) {
            val cfg = config(c, widgetId).put("lastAddListId", listId)
            saveConfig(c, widgetId, cfg)
        }
        refreshAll(c)
    }

    fun listPathOf(c: Context, id: Int): String {
        val t = tree(c)
        for (i in 0 until t.length()) {
            val o = t.getJSONObject(i)
            if (o.getInt("id") == id) {
                if (o.isNull("parentId")) return o.getString("title")
                val parent = listTitle(c, o.getInt("parentId"))
                return if (parent != null) "$parent › ${o.getString("title")}" else o.getString("title")
            }
        }
        return ""
    }

    /** Redraws every To-Do widget and asks Flutter to apply the queued actions. */
    fun refreshAll(c: Context) {
        val mgr = AppWidgetManager.getInstance(c)
        for (cls in listOf(TodoWidgetMedium::class.java, TodoWidgetLarge::class.java)) {
            val ids = mgr.getAppWidgetIds(ComponentName(c, cls))
            if (ids.isNotEmpty()) {
                val intent = android.content.Intent(c, cls).setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                c.sendBroadcast(intent)
                mgr.notifyAppWidgetViewDataChanged(ids, com.prinotes.app.R.id.list)
            }
        }
        try {
            HomeWidgetBackgroundIntent.getBroadcast(c, Uri.parse("todo://apply")).send()
        } catch (e: Exception) {
            // Flutter will pick the queue up the next time the app runs or syncs.
        }
    }
}
