package com.prinotes.app.todo

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.prinotes.app.MainActivity

/** Invisible activity that receives widget row taps (a RemoteViews list can only use one template). */
class TodoWidgetActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val op = intent.getStringExtra("op")
        val id = intent.getIntExtra("id", 0)
        when (op) {
            // Negative ids are tasks added from the widget that Flutter has not stored yet.
            "complete" -> if (id > 0) TodoWidgetData.queueComplete(this, id)
            "open" -> startActivity(
                Intent(this, MainActivity::class.java)
                    .setAction("es.antonborri.home_widget.action.LAUNCH")
                    .setData(Uri.parse("todo://open?id=$id"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            )
        }
        finish()
    }
}
