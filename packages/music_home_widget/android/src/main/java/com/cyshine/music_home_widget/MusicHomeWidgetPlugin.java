package com.cyshine.music_home_widget;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Bundle;
import android.os.Message;
import android.os.Messenger;
import android.util.AtomicFile;
import android.util.Log;

import com.ryanheise.audioservice.AudioServicePlugin;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayDeque;
import java.util.Map;
import java.util.HashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import org.json.JSONObject;

/** Registered on the shared audio-service engine, including Activity-free starts. */
public final class MusicHomeWidgetPlugin implements FlutterPlugin, ActivityAware,
        MethodChannel.MethodCallHandler, PluginRegistry.NewIntentListener {
    static final String PREFERENCES = "music_home_widget";
    static final String OPEN_PLAYER = "cyshine.music_widget.open_player";
    static final Object ART_LOCK = new Object();
    private static final String TAG = "MusicHomeWidget";
    private static final ExecutorService ARTWORK = Executors.newSingleThreadExecutor();
    private static volatile MusicHomeWidgetPlugin instance;
    private static volatile String requestedCover;
    private static volatile Playback playback = Playback.IDLE;

    private Context context;
    private MethodChannel channel;
    private ActivityPluginBinding activityBinding;
    private volatile boolean ready;
    private boolean stateObserverBound;
    private volatile Messenger stateObserverMessenger;
    private final ServiceConnection stateObserver = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder service) {
            stateObserverMessenger = new Messenger(service);
            syncStateObserver(preferences(context).getAll());
            Log.i(TAG, "playback exit observer connected");
        }
        @Override public void onServiceDisconnected(ComponentName name) {
            stateObserverMessenger = null;
        }
    };
    private boolean pendingOpen;
    private final ArrayDeque<Control> pendingControls = new ArrayDeque<>();

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "cy_shine_music/home_widget");
        channel.setMethodCallHandler(this);
        instance = this;
        // Live transport state belongs to this process, never to disk cache.
        playback = Playback.IDLE;
        MusicWidgetProvider.updateAll(context);
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        ready = false;
        playback = Playback.IDLE;
        channel.setMethodCallHandler(null);
        while (!pendingControls.isEmpty()) pendingControls.remove().finish.run();
        if (instance == this) instance = null;
        if (stateObserverBound) {
            context.unbindService(stateObserver);
            stateObserverBound = false;
            stateObserverMessenger = null;
        }
        MusicWidgetProvider.updateAll(context);
    }

    static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
    }

    static Playback playback() {
        MusicHomeWidgetPlugin plugin = instance;
        return plugin != null && plugin.ready ? playback : Playback.IDLE;
    }

    static void ensureStateObserver() {
        new Handler(Looper.getMainLooper()).post(() -> {
            MusicHomeWidgetPlugin plugin = instance;
            if (plugin == null || !plugin.ready || plugin.stateObserverBound) return;
            if (AppWidgetManager.getInstance(plugin.context).getAppWidgetIds(
                    new ComponentName(plugin.context, MusicWidgetProvider.class)).length == 0) return;
            try {
                // A tiny native observer stays separate from the Flutter process
                // so its unbind callback can clear the launcher after that process
                // exits. It neither starts another player nor polls in a loop.
                plugin.stateObserverBound = plugin.context.bindService(
                        new Intent(plugin.context, MusicWidgetStateService.class),
                        plugin.stateObserver, Context.BIND_AUTO_CREATE);
            } catch (Exception error) {
                Log.w(TAG, "Could not bind playback exit observer", error);
            }
        });
    }

    static void syncStateObserver(Map<String, ?> snapshot) {
        MusicHomeWidgetPlugin plugin = instance;
        Messenger messenger = plugin == null ? null : plugin.stateObserverMessenger;
        if (messenger == null) return;
        Bundle data = new Bundle();
        for (String key : new String[]{"title", "artist", "cover", "cachedCover"}) {
            Object value = snapshot.get(key);
            data.putString(key, value instanceof String ? (String) value : "");
        }
        Message message = Message.obtain(null, MusicWidgetStateService.PRESENTATION);
        message.setData(data);
        try {
            messenger.send(message);
        } catch (Exception error) {
            Log.w(TAG, "Could not sync playback exit observer", error);
        }
    }

    static void control(Context context, String action, Runnable finish) {
        try {
            Log.i(TAG, "control=" + action + " engine=" + (instance != null)
                    + " ready=" + (instance != null && instance.ready));
            // Reuse audio_service's cached engine, never create a second player.
            AudioServicePlugin.getFlutterEngine(context);
            if (instance == null) {
                finish.run();
                return;
            }
            instance.pendingControls.add(new Control(action, finish));
            instance.drainControls();
        } catch (Exception error) {
            Log.w(TAG, "Could not start widget control", error);
            finish.run();
        }
    }

    private void drainControls() {
        if (!ready) return;
        while (!pendingControls.isEmpty()) {
            Control control = pendingControls.remove();
            channel.invokeMethod("control", control.action, new MethodChannel.Result() {
                @Override public void success(Object result) {
                    Log.i(TAG, "control accepted=" + control.action);
                    control.finish.run();
                }
                @Override public void error(String code, String message, Object details) {
                    Log.w(TAG, "Widget control failed: " + code + ": " + message);
                    control.finish.run();
                }
                @Override public void notImplemented() { control.finish.run(); }
            });
        }
        if (pendingOpen) {
            pendingOpen = false;
            channel.invokeMethod("openPlayer", null);
        }
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "ready":
                ready = true;
                Log.i(TAG, "bridge ready, pendingControls=" + pendingControls.size());
                result.success(null);
                ensureStateObserver();
                drainControls();
                break;
            case "update":
                update(call);
                result.success(null);
                break;
            case "updatePlayback":
                playback = new Playback(Boolean.TRUE.equals(call.argument("playing")),
                        Boolean.TRUE.equals(call.argument("loading")));
                Log.i(TAG, "playback playing=" + playback.playing + " loading=" + playback.loading);
                MusicWidgetProvider.updateAll(context);
                result.success(null);
                break;
            case "openApp":
                Intent launch = launchIntent(context);
                if (launch != null) context.startActivity(launch);
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    private void update(MethodCall call) {
        String cover = string(call.argument("cover"));
        Map<String, String> headers = call.argument("headers");
        preferences(context).edit()
                .putString("trackId", string(call.argument("trackId")))
                .putString("title", string(call.argument("title")))
                .putString("artist", string(call.argument("artist")))
                .putString("cover", cover)
                .putString("headers", headers == null ? "{}" : new JSONObject(headers).toString())
                .apply();
        MusicWidgetProvider.updateAll(context);
    }

    static synchronized void requestArtwork(Context appContext) {
        SharedPreferences saved = preferences(appContext);
        String cover = saved.getString("cover", "");
        if (cover.isEmpty() || cover.equals(requestedCover)) return;
        // Adding a widget later can populate its cover from persisted metadata
        // without starting Flutter or downloading covers during ordinary app use.
        if (AppWidgetManager.getInstance(appContext).getAppWidgetIds(
                new ComponentName(appContext, MusicWidgetProvider.class)).length == 0) return;
        requestedCover = cover;
        Map<String, String> headers = new HashMap<>();
        try {
            JSONObject json = new JSONObject(saved.getString("headers", "{}"));
            java.util.Iterator<String> keys = json.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                headers.put(key, json.getString(key));
            }
        } catch (Exception error) {
            Log.w(TAG, "Could not read cover headers", error);
        }
        ARTWORK.execute(() -> {
            SharedPreferences prefs = preferences(appContext);
            if (!cover.equals(prefs.getString("cover", ""))) return;
            synchronized (ART_LOCK) {
                if (cover.equals(prefs.getString("cachedCover", ""))
                        && artworkFile(appContext).isFile()) return;
            }
            Bitmap bitmap = null;
            try {
                bitmap = loadArtwork(appContext, cover, headers);
                if (bitmap == null || !cover.equals(prefs.getString("cover", ""))) return;
                synchronized (ART_LOCK) {
                    AtomicFile file = new AtomicFile(artworkFile(appContext));
                    FileOutputStream output = null;
                    try {
                        output = file.startWrite();
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output);
                        file.finishWrite(output);
                        prefs.edit().putString("cachedCover", cover).apply();
                    } catch (Exception error) {
                        if (output != null) file.failWrite(output);
                        throw error;
                    }
                }
                MusicWidgetProvider.updateAll(appContext);
            } catch (Exception error) {
                Log.w(TAG, "Could not cache widget cover", error);
                // Permit a retry on the next relevant playback-state update.
                new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                    if (cover.equals(requestedCover)) requestedCover = null;
                });
            } finally {
                if (bitmap != null) bitmap.recycle();
            }
        });
    }

    static File artworkFile(Context context) {
        return new File(context.getFilesDir(), "music_widget_cover.png");
    }

    private static Bitmap loadArtwork(Context context, String cover,
            Map<String, String> headers) throws Exception {
        Uri uri = Uri.parse(cover);
        HttpURLConnection connection = null;
        try {
            InputStream stream;
            if ("https".equals(uri.getScheme()) || "http".equals(uri.getScheme())) {
                connection = (HttpURLConnection) new URL(cover).openConnection();
                connection.setConnectTimeout(3000);
                connection.setReadTimeout(5000);
                if (headers != null) {
                    for (Map.Entry<String, String> header : headers.entrySet()) {
                        connection.setRequestProperty(header.getKey(), header.getValue());
                    }
                }
                stream = connection.getInputStream();
            } else {
                stream = context.getContentResolver().openInputStream(uri);
            }
            if (stream == null) return null;
            byte[] bytes;
            try (InputStream input = stream;
                    ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (output.size() + count > 4 * 1024 * 1024) {
                        throw new java.io.IOException("Artwork exceeds 4 MB");
                    }
                    output.write(buffer, 0, count);
                }
                bytes = output.toByteArray();
            }
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
            options.inSampleSize = 1;
            while (Math.max(options.outWidth, options.outHeight) / options.inSampleSize > 768) {
                options.inSampleSize *= 2;
            }
            options.inJustDecodeBounds = false;
            return BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    static Intent launchIntent(Context context) {
        Intent launch = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launch != null) {
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            launch.putExtra(OPEN_PLAYER, true);
        }
        return launch;
    }

    private void handleIntent(Intent intent) {
        if (intent == null || !intent.getBooleanExtra(OPEN_PLAYER, false)) return;
        intent.removeExtra(OPEN_PLAYER);
        pendingOpen = true;
        drainControls();
    }

    @Override public boolean onNewIntent(Intent intent) {
        handleIntent(intent);
        return false;
    }

    @Override public void onAttachedToActivity(ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addOnNewIntentListener(this);
        handleIntent(binding.getActivity().getIntent());
    }

    @Override public void onDetachedFromActivity() {
        if (activityBinding != null) activityBinding.removeOnNewIntentListener(this);
        activityBinding = null;
    }

    @Override public void onDetachedFromActivityForConfigChanges() { onDetachedFromActivity(); }
    @Override public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    private static String string(String value) { return value == null ? "" : value; }

    static final class Playback {
        static final Playback IDLE = new Playback(false, false);
        final boolean playing;
        final boolean loading;
        Playback(boolean playing, boolean loading) {
            this.playing = playing;
            this.loading = loading;
        }
    }

    private static final class Control {
        final String action;
        final Runnable finish;
        Control(String action, Runnable finish) { this.action = action; this.finish = finish; }
    }
}
