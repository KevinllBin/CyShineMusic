package com.cyshine.music_home_widget;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.util.SizeF;
import android.widget.RemoteViews;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.HashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

public final class MusicWidgetProvider extends AppWidgetProvider {
    private static final String CONTROL = "com.cyshine.music_home_widget.CONTROL";
    private static final ExecutorService RENDERER = Executors.newSingleThreadExecutor();

    @Override
    public void onReceive(Context context, Intent intent) {
        if (CONTROL.equals(intent.getAction())) {
            String action = intent.getStringExtra("control");
            if (!"toggle".equals(action) && !"previous".equals(action) && !"next".equals(action)) return;
            PendingResult pending = goAsync();
            AtomicBoolean finished = new AtomicBoolean();
            Runnable finish = () -> { if (finished.compareAndSet(false, true)) pending.finish(); };
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                if (!finished.get()) Log.w("MusicHomeWidget", "control startup timed out=" + action);
                finish.run();
            }, 9000);
            MusicHomeWidgetPlugin.control(context, action, finish);
            return;
        }
        // Keep the process alive until the launcher has received its bitmap.
        if (AppWidgetManager.ACTION_APPWIDGET_UPDATE.equals(intent.getAction())
                || AppWidgetManager.ACTION_APPWIDGET_OPTIONS_CHANGED.equals(intent.getAction())) {
            PendingResult pending = goAsync();
            RENDERER.execute(() -> {
                try { renderAll(context); }
                finally { pending.finish(); }
            });
            return;
        }
        super.onReceive(context, intent);
    }

    @Override public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        updateAll(context);
    }

    @Override public void onAppWidgetOptionsChanged(Context context, AppWidgetManager manager,
            int id, Bundle options) {
        updateAll(context);
    }

    static void updateAll(Context context) {
        Context appContext = context.getApplicationContext();
        RENDERER.execute(() -> renderAll(appContext));
    }

    private static void renderAll(Context context) {
        renderAll(context, true, null);
    }

    // Called synchronously by the native observer before its last binding is
    // removed, so the launcher actually receives the stopped state.
    static void refreshAfterPlaybackExit(Context context, Bundle presentation) {
        Map<String, String> snapshot = null;
        if (presentation != null) {
            snapshot = new HashMap<>();
            for (String key : presentation.keySet()) {
                snapshot.put(key, presentation.getString(key, ""));
            }
        }
        renderAll(context, false, snapshot);
    }

    private static void renderAll(Context context, boolean allowArtwork, Map<String, ?> presentation) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, MusicWidgetProvider.class));
        if (ids.length == 0) return;
        if (allowArtwork) {
            MusicHomeWidgetPlugin.ensureStateObserver();
            MusicHomeWidgetPlugin.requestArtwork(context);
        }
        Map<String, ?> snapshot = presentation != null ? presentation
                : MusicHomeWidgetPlugin.preferences(context).getAll();
        if (allowArtwork) MusicHomeWidgetPlugin.syncStateObserver(snapshot);
        String title = (String) snapshot.getOrDefault("title", null);
        String artist = (String) snapshot.getOrDefault("artist", null);
        if (title == null) title = "";
        if (artist == null) artist = "";
        MusicHomeWidgetPlugin.Playback playback = MusicHomeWidgetPlugin.playback();
        boolean playing = playback.playing;
        boolean loading = playback.loading;
        Bitmap cover = null;
        synchronized (MusicHomeWidgetPlugin.ART_LOCK) {
            String source = (String) snapshot.get("cover");
            if (source != null && !source.isEmpty() && source.equals(snapshot.get("cachedCover"))) {
                cover = BitmapFactory.decodeFile(MusicHomeWidgetPlugin.artworkFile(context).getPath());
            }
        }
        try {
            for (int id : ids) {
                try {
                    Bundle options = manager.getAppWidgetOptions(id);
                    RemoteViews views;
                    ArrayList<SizeF> sizes = widgetSizes(options);
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && sizes != null && !sizes.isEmpty()) {
                        Map<SizeF, RemoteViews> layouts = new LinkedHashMap<>();
                        // A phone normally has two sizes, a foldable four.
                        for (SizeF size : sizes.subList(0, Math.min(4, sizes.size()))) {
                            layouts.put(size, views(context, id, size.getWidth(), size.getHeight(),
                                    title, artist, playing, loading, cover));
                        }
                        views = new RemoteViews(layouts);
                    } else {
                        boolean landscape = context.getResources().getConfiguration().orientation
                                == Configuration.ORIENTATION_LANDSCAPE;
                        float width = options.getInt(landscape ? AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH
                                : AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180);
                        float height = options.getInt(landscape ? AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT
                                : AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 180);
                        views = views(context, id, width, height, title, artist, playing, loading, cover);
                    }
                    manager.updateAppWidget(id, views);
                } catch (Exception error) {
                    Log.w("MusicHomeWidget", "Could not update widget " + id, error);
                }
            }
        } finally {
            if (cover != null) cover.recycle();
        }
    }

    private static ArrayList<SizeF> widgetSizes(Bundle options) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return options.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, SizeF.class);
        }
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? legacyWidgetSizes(options) : null;
    }

    // Android 12/12L have widget size lists but not the typed Bundle accessor.
    @SuppressWarnings("deprecation")
    private static ArrayList<SizeF> legacyWidgetSizes(Bundle options) {
        return options.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES);
    }

    private static RemoteViews views(Context context, int id, float width, float height,
            String title, String artist, boolean playing, boolean loading, Bitmap cover) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.music_widget);
        // Keep bitmap payloads bounded even when a launcher offers a very large size.
        float density = Math.min(2f, context.getResources().getDisplayMetrics().density);
        float scale = Math.min(density, 512f / Math.max(Math.max(width, height), 1f));
        int pixelsWide = Math.max(1, Math.round(width * scale));
        int pixelsHigh = Math.max(1, Math.round(height * scale));
        views.setImageViewBitmap(R.id.music_widget_card,
                MusicWidgetRenderer.render(pixelsWide, pixelsHigh, title, artist, playing, loading, cover));
        Intent launch = MusicHomeWidgetPlugin.launchIntent(context);
        if (launch != null) {
            PendingIntent open = PendingIntent.getActivity(context, id * 10, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            views.setOnClickPendingIntent(R.id.music_widget_card, open);
            views.setContentDescription(R.id.music_widget_card, title.isEmpty()
                    ? context.getString(R.string.music_widget_open)
                    : title + "，" + artist + "，" + context.getString(R.string.music_widget_open));
            bindControl(context, views, id, R.id.music_widget_previous, "previous", open, title.isEmpty());
            bindControl(context, views, id, R.id.music_widget_toggle, "toggle", open, title.isEmpty());
            bindControl(context, views, id, R.id.music_widget_next, "next", open, title.isEmpty());
        }
        views.setContentDescription(R.id.music_widget_toggle, context.getString(loading
                ? R.string.music_widget_loading : playing ? R.string.music_widget_pause : R.string.music_widget_play));
        return views;
    }

    private static void bindControl(Context context, RemoteViews views, int id, int view,
            String action, PendingIntent open, boolean empty) {
        if (empty) {
            views.setOnClickPendingIntent(view, open);
            return;
        }
        Intent intent = new Intent(context, MusicWidgetProvider.class).setAction(CONTROL)
                .putExtra("control", action).addFlags(Intent.FLAG_RECEIVER_FOREGROUND);
        int offset = "previous".equals(action) ? 1 : "toggle".equals(action) ? 2 : 3;
        PendingIntent control = PendingIntent.getBroadcast(context, id * 10 + offset, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        views.setOnClickPendingIntent(view, control);
    }
}
