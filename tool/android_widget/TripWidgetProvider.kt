package __PACKAGE__

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * TripKhata home screen widget: the active trip, what was spent, your balance,
 * and a mic button that opens straight into "speak to add".
 * Data comes from lib/features/widget/trip_widget.dart via home_widget.
 */
class TripWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val name = widgetData.getString("tk_trip_name", null) ?: "TripKhata"
        val line = widgetData.getString("tk_trip_line", null) ?: "Open the app once to set up"
        val hasTrip = widgetData.getBoolean("tk_has_trip", false)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.trip_widget).apply {
                setTextViewText(R.id.tk_label, if (hasTrip) "ACTIVE TRIP" else "TRIPKHATA")
                setTextViewText(R.id.tk_name, name)
                setTextViewText(R.id.tk_line, line)
                setViewVisibility(R.id.tk_type, if (hasTrip) View.VISIBLE else View.GONE)
                setOnClickPendingIntent(R.id.tk_root, launch(context, "open"))
                setOnClickPendingIntent(R.id.tk_mic, launch(context, "voice"))
                setOnClickPendingIntent(R.id.tk_type, launch(context, "type"))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun launch(context: Context, action: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("tripkhata://widget/$action"))
}
