#!/usr/bin/env bash
# Run from the project root AFTER `flutter create --platforms=android`.
# Patches the generated Android project for the V2Ray/Xray VPN core.
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"

# 1) App name
sed -i 's/android:label="[^"]*"/android:label="Tulip VPN"/' "$MANIFEST"

# 2) INTERNET permission (main manifest does not include it by default)
if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application#' "$MANIFEST"
fi

# 2b) Camera permission for QR scanning
if ! grep -q 'android.permission.CAMERA' "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.CAMERA"/>\n    <uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application#' "$MANIFEST"
fi

# 2c) Allow the app to list launcher apps (per-app proxy)
LAUNCHER_Q='<intent><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent>'
if grep -q '<queries>' "$MANIFEST"; then
  sed -i "s#<queries>#<queries>\n        $LAUNCHER_Q#" "$MANIFEST"
else
  sed -i "s#<application#<queries>$LAUNCHER_Q</queries>\n    <application#" "$MANIFEST"
fi

# 3) Native libs must be extracted for the Xray core binaries.
#    New Android Gradle Plugin wants this in the build script, not the manifest.
for f in android/app/build.gradle android/app/build.gradle.kts; do
  if [ -f "$f" ] && ! grep -q 'useLegacyPackaging' "$f"; then
    sed -i '0,/^android {/s//android {\n    packaging {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n    }/' "$f"
  fi
done

# 4) minSdk 24 (plugin needs >= 23) - works for both Groovy and Kotlin DSL
for f in android/app/build.gradle android/app/build.gradle.kts; do
  if [ -f "$f" ]; then
    sed -i -E 's/minSdk(Version)?[[:space:]]*=?[[:space:]]*(flutter\.minSdkVersion|[0-9]+)/minSdk = 24/' "$f"
  fi
done

# 5) Native side: per-app list + widget/tile bridge (MainActivity), Quick Settings
#    tile, home-screen widget
MAIN=$(find android/app/src/main -name 'MainActivity.kt' | head -1 || true)
if [ -z "$MAIN" ]; then
  echo "MainActivity.kt not found - patch aborted"; exit 1
fi
PKG=$(grep -m1 '^package ' "$MAIN" | sed 's/^package //' | tr -d '\r ')
KDIR=$(dirname "$MAIN")
RES="android/app/src/main/res"
mkdir -p "$RES/drawable" "$RES/layout" "$RES/xml"

# ---- OakState: shared state between the app, the tile and the widget ----
cat > "$KDIR/OakState.kt" <<'KT'
package PKG_PLACEHOLDER

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.service.quicksettings.TileService

object OakState {
    const val ACTION_TOGGLE = "oak.action.TOGGLE"
    const val ACTION_BG_TOGGLE = "oak.action.BG_TOGGLE"
    private const val PREFS = "oak_native"

    fun save(ctx: Context, connected: Boolean, name: String) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("connected", connected)
            .putString("name", name)
            .apply()
        refresh(ctx)
    }

    /** Android reports an active VPN network (any VPN app). */
    fun vpnActive(ctx: Context): Boolean {
        return try {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        } catch (e: Exception) {
            false
        }
    }

    /** Real state = app says connected AND Android reports an active VPN. */
    fun connected(ctx: Context): Boolean {
        val said = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean("connected", false)
        return said && vpnActive(ctx)
    }

    fun name(ctx: Context): String =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("name", "") ?: ""

    fun refresh(ctx: Context) {
        try {
            TileService.requestListeningState(
                ctx, ComponentName(ctx, OakTileService::class.java)
            )
        } catch (e: Exception) {
        }
        try {
            val mgr = AppWidgetManager.getInstance(ctx)
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, OakWidgetProvider::class.java))
            if (ids.isNotEmpty()) OakWidgetProvider.update(ctx, mgr, ids)
        } catch (e: Exception) {
        }
    }
}
KT

# ---- Background toggle: runs the Dart side headless (no app UI) ----
cat > "$KDIR/OakBackground.kt" <<'KT'
package PKG_PLACEHOLDER

import android.content.Context
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

object OakBackground {
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var onDone: (() -> Unit)? = null
    private var timeout: Runnable? = null

    /** true when the VPN permission was already granted (no dialog needed). */
    fun vpnReady(ctx: Context): Boolean {
        return try {
            VpnService.prepare(ctx.applicationContext) == null
        } catch (e: Exception) {
            false
        }
    }

    private fun finish() {
        timeout?.let { main.removeCallbacks(it) }
        timeout = null
        try {
            engine?.destroy()
        } catch (e: Exception) {
        }
        engine = null
        val cb = onDone
        onDone = null
        cb?.invoke()
    }

    /** Connect or disconnect without opening the app. [done] is called once. */
    fun toggle(ctx: Context, done: () -> Unit) {
        val app = ctx.applicationContext
        main.post {
            if (engine != null) {
                done()
                return@post
            }
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(app)
                loader.ensureInitializationComplete(app, null)
                val e = FlutterEngine(app)
                GeneratedPluginRegistrant.registerWith(e)
                MethodChannel(e.dartExecutor.binaryMessenger, "oak/ctl")
                    .setMethodCallHandler { call, result ->
                        when (call.method) {
                            "connected" -> result.success(OakState.connected(app))
                            "vpnActive" -> result.success(OakState.vpnActive(app))
                            "state" -> {
                                OakState.save(
                                    app,
                                    call.argument<Boolean>("connected") ?: false,
                                    call.argument<String>("name") ?: ""
                                )
                                result.success(null)
                            }
                            "done" -> {
                                result.success(null)
                                main.post { finish() }
                            }
                            else -> result.notImplemented()
                        }
                    }
                engine = e
                onDone = done
                timeout = Runnable { finish() }
                main.postDelayed(timeout!!, 15000)
                e.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(), "oakBackgroundToggle"
                    )
                )
            } catch (ex: Exception) {
                engine = null
                done()
            }
        }
    }
}
KT

cat > "$KDIR/OakToggleReceiver.kt" <<'KT'
package PKG_PLACEHOLDER

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

class OakToggleReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val pr = goAsync()
        var finished = false
        val end = {
            if (!finished) {
                finished = true
                try {
                    pr.finish()
                } catch (e: Exception) {
                }
            }
        }
        Handler(Looper.getMainLooper()).postDelayed({ end() }, 8500)
        try {
            val mgr = AppWidgetManager.getInstance(ctx)
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, OakWidgetProvider::class.java))
            if (ids.isNotEmpty()) OakWidgetProvider.update(ctx, mgr, ids, true)
        } catch (e: Exception) {
        }
        OakBackground.toggle(ctx) {
            OakState.refresh(ctx)
            end()
        }
    }
}
KT

# ---- Quick Settings tile ----
cat > "$KDIR/OakTileService.kt" <<'KT'
package PKG_PLACEHOLDER

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class OakTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        render()
    }

    override fun onTileAdded() {
        super.onTileAdded()
        render()
    }

    private fun render() {
        val tile = qsTile ?: return
        val on = OakState.connected(this)
        tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Tulip VPN"
        if (Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = if (on) {
                OakState.name(this).ifEmpty { "Connected" }
            } else {
                "Tap to connect"
            }
        }
        tile.updateTile()
    }

    private fun working(on: Boolean) {
        val tile = qsTile ?: return
        tile.state = if (on) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
        if (Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = if (on) "Disconnecting…" else "Connecting…"
        }
        tile.updateTile()
    }

    @Suppress("DEPRECATION")
    private fun openApp() {
        val i = Intent(this, MainActivity::class.java).apply {
            action = OakState.ACTION_TOGGLE
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val pi = PendingIntent.getActivity(
                this, 1, i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pi)
        } else {
            startActivityAndCollapse(i)
        }
    }

    override fun onClick() {
        super.onClick()
        unlockAndRun {
            if (OakBackground.vpnReady(this)) {
                // No app UI: toggle in the background
                working(OakState.connected(this))
                OakBackground.toggle(this) { OakState.refresh(this) }
            } else {
                // First time: Android needs the VPN permission dialog
                openApp()
            }
        }
    }
}
KT

# ---- Home-screen widget ----
cat > "$KDIR/OakWidgetProvider.kt" <<'KT'
package PKG_PLACEHOLDER

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class OakWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        update(ctx, mgr, ids)
    }

    companion object {
        fun update(ctx: Context, mgr: AppWidgetManager, ids: IntArray, working: Boolean = false) {
            val on = OakState.connected(ctx)
            val views = RemoteViews(ctx.packageName, R.layout.oak_widget)
            views.setInt(
                R.id.oak_root, "setBackgroundResource",
                if (on) R.drawable.oak_widget_bg_on else R.drawable.oak_widget_bg_off
            )
            views.setImageViewResource(
                R.id.oak_icon,
                if (on) R.drawable.oak_power_on else R.drawable.oak_power_off
            )
            views.setTextViewText(
                R.id.oak_title,
                if (working) "Working…" else if (on) "Connected" else "Tulip VPN"
            )
            views.setTextViewText(
                R.id.oak_sub,
                if (on) OakState.name(ctx).ifEmpty { "Tap to disconnect" } else "Tap to connect"
            )
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val pi = if (OakBackground.vpnReady(ctx)) {
                // Background toggle, app UI stays closed
                val b = Intent(ctx, OakToggleReceiver::class.java).apply {
                    action = OakState.ACTION_BG_TOGGLE
                }
                PendingIntent.getBroadcast(ctx, 3, b, flags)
            } else {
                // VPN permission not granted yet: open the app once
                val i = Intent(ctx, MainActivity::class.java).apply {
                    action = OakState.ACTION_TOGGLE
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                PendingIntent.getActivity(ctx, 2, i, flags)
            }
            views.setOnClickPendingIntent(R.id.oak_root, pi)
            for (id in ids) mgr.updateAppWidget(id, views)
        }
    }
}
KT

# ---- MainActivity: apps list + widget/tile bridge ----
cat > "$MAIN" <<'KT'
package PKG_PLACEHOLDER

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var ctl: MethodChannel? = null
    private var pendingToggle = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null && intent?.action == OakState.ACTION_TOGGLE) {
            pendingToggle = true
            intent.action = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == OakState.ACTION_TOGGLE) {
            intent.action = null
            ctl?.invokeMethod("toggle", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "oak/apps").setMethodCallHandler { call, result ->
            if (call.method == "list") {
                Thread {
                    try {
                        val apps = listApps()
                        runOnUiThread { result.success(apps) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("ERR", e.message, null) }
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }

        ctl = MethodChannel(messenger, "oak/ctl")
        ctl!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "pending" -> {
                    val p = pendingToggle
                    pendingToggle = false
                    result.success(p)
                }
                "state" -> {
                    val connected = call.argument<Boolean>("connected") ?: false
                    val name = call.argument<String>("name") ?: ""
                    OakState.save(applicationContext, connected, name)
                    result.success(null)
                }
                "minimize" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun iconBytes(d: Drawable): ByteArray {
        val size = 72
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    private fun listApps(): List<Map<String, Any>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = HashSet<String>()
        val out = ArrayList<Map<String, Any>>()
        for (ri in pm.queryIntentActivities(intent, 0)) {
            val pkg = ri.activityInfo.packageName
            if (pkg == packageName || !seen.add(pkg)) continue
            val name = ri.loadLabel(pm).toString()
            val icon = try {
                iconBytes(ri.loadIcon(pm))
            } catch (e: Exception) {
                ByteArray(0)
            }
            out.add(mapOf("name" to name, "package" to pkg, "icon" to icon))
        }
        out.sortBy { (it["name"] as String).lowercase() }
        return out
    }
}
KT
sed -i "s/PKG_PLACEHOLDER/$PKG/" "$KDIR/MainActivity.kt" "$KDIR/OakState.kt" \
  "$KDIR/OakTileService.kt" "$KDIR/OakWidgetProvider.kt" \
  "$KDIR/OakBackground.kt" "$KDIR/OakToggleReceiver.kt"

# ---- resources ----
cat > "$RES/drawable/oak_widget_bg_off.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#E61B2142"/>
    <corners android:radius="24dp"/>
    <stroke android:width="1dp" android:color="#33FFFFFF"/>
</shape>
XML
cat > "$RES/drawable/oak_widget_bg_on.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#E60F766E"/>
    <corners android:radius="24dp"/>
    <stroke android:width="1dp" android:color="#554ADE80"/>
</shape>
XML
cat > "$RES/drawable/oak_power_off.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="40dp" android:height="40dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFF" android:fillAlpha="0.85"
        android:pathData="M13,3h-2v10h2V3zM17.83,5.17l-1.42,1.42C17.99,7.86 19,9.81 19,12c0,3.87 -3.13,7 -7,7s-7,-3.13 -7,-7c0,-2.19 1.01,-4.14 2.58,-5.42L6.17,5.17C4.23,6.82 3,9.26 3,12c0,4.97 4.03,9 9,9s9,-4.03 9,-9c0,-2.74 -1.23,-5.18 -3.17,-6.83z"/>
</vector>
XML
cat > "$RES/drawable/oak_power_on.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="40dp" android:height="40dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#4ADE80"
        android:pathData="M13,3h-2v10h2V3zM17.83,5.17l-1.42,1.42C17.99,7.86 19,9.81 19,12c0,3.87 -3.13,7 -7,7s-7,-3.13 -7,-7c0,-2.19 1.01,-4.14 2.58,-5.42L6.17,5.17C4.23,6.82 3,9.26 3,12c0,4.97 4.03,9 9,9s9,-4.03 9,-9c0,-2.74 -1.23,-5.18 -3.17,-6.83z"/>
</vector>
XML
# Quick Settings tile icon (must be a white vector)
cat > "$RES/drawable/oak_tile_icon.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M12,1L3,5v6c0,5.55 3.84,10.74 9,12 5.16,-1.26 9,-6.45 9,-12V5l-9,-4zM12,11.99h7c-0.53,4.12 -3.28,7.79 -7,8.94V12H5V6.3l7,-3.11v8.8z"/>
</vector>
XML
cat > "$RES/layout/oak_widget.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/oak_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/oak_widget_bg_off"
    android:gravity="center_vertical"
    android:orientation="horizontal"
    android:padding="14dp">

    <ImageView
        android:id="@+id/oak_icon"
        android:layout_width="40dp"
        android:layout_height="40dp"
        android:contentDescription="Tulip VPN"
        android:src="@drawable/oak_power_off"/>

    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_marginStart="12dp"
        android:layout_weight="1"
        android:orientation="vertical">

        <TextView
            android:id="@+id/oak_title"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:maxLines="1"
            android:text="Tulip VPN"
            android:textColor="#FFFFFF"
            android:textSize="16sp"
            android:textStyle="bold"/>

        <TextView
            android:id="@+id/oak_sub"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:ellipsize="end"
            android:maxLines="1"
            android:text="Tap to connect"
            android:textColor="#CCFFFFFF"
            android:textSize="12sp"/>
    </LinearLayout>
</LinearLayout>
XML
cat > "$RES/xml/oak_widget_info.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:initialLayout="@layout/oak_widget"
    android:minWidth="140dp"
    android:minHeight="56dp"
    android:targetCellWidth="2"
    android:targetCellHeight="1"
    android:resizeMode="horizontal"
    android:updatePeriodMillis="0"
    android:widgetCategory="home_screen"/>
XML

# ---- manifest: register tile service + widget receiver ----
if ! grep -q 'OakTileService' "$MANIFEST"; then
  BLOCK='        <service android:name=".OakTileService" android:exported="true" android:label="Tulip VPN" android:icon="@drawable/oak_tile_icon" android:permission="android.permission.BIND_QUICK_SETTINGS_TILE">\n            <intent-filter><action android:name="android.service.quicksettings.action.QS_TILE"/></intent-filter>\n        </service>\n        <receiver android:name=".OakWidgetProvider" android:exported="true" android:label="Tulip VPN">\n            <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter>\n            <meta-data android:name="android.appwidget.provider" android:resource="@xml/oak_widget_info"/>\n        </receiver>\n        <receiver android:name=".OakToggleReceiver" android:exported="false"/>'
  sed -i "s#</application>#$BLOCK\n    </application>#" "$MANIFEST"
fi

echo "Android project patched."
grep -n 'minSdk\|useLegacyPackaging' android/app/build.gradle* || true
grep -n 'OakTileService\|OakWidgetProvider' "$MANIFEST" || true
