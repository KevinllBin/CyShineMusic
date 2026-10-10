package com.cyshine.music_home_widget;

import android.app.Service;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Message;
import android.os.Messenger;
import android.util.Log;

/** Clears a cached pause icon after the actual playback process exits. */
public final class MusicWidgetStateService extends Service {
    static final int PRESENTATION = 1;
    private Bundle presentation;
    private final Messenger messenger = new Messenger(new Handler(Looper.getMainLooper()) {
        @Override public void handleMessage(Message message) {
            if (message.what == PRESENTATION) presentation = message.getData();
        }
    });
    private boolean refreshed;

    @Override public IBinder onBind(Intent intent) {
        refreshed = false;
        return messenger.getBinder();
    }

    @Override public boolean onUnbind(Intent intent) {
        refreshStoppedState();
        return false;
    }

    @Override public void onDestroy() {
        refreshStoppedState();
        super.onDestroy();
    }

    private void refreshStoppedState() {
        if (refreshed) return;
        refreshed = true;
        Log.i("MusicHomeWidget", "playback process detached; refreshing play icon");
        // This process has no Flutter engine or live playback. Metadata and
        // the cached album remain available, but transport state is idle.
        // Receive metadata through the binding, avoiding stale cross-process
        // SharedPreferences caches when the player is launched more than once.
        MusicWidgetProvider.refreshAfterPlaybackExit(this, presentation);
    }
}
