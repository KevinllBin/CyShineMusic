package com.ryanheise.audioservice;

import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaSessionCompat;

import java.util.Locale;

/** Bridges whole-song LRC from MediaItem metadata into Vivo's session extras. */
final class VivoLyricsPublisher {
    static final String PACKAGE = "com.vivo.musicwidgetmix";
    static final String SERVICE_ACTION = "com.vivo.musicwidgetmix.support.service";
    // "meida" and "meidia" are intentional spellings in MusicWidgetMix's protocol.
    private static final String ACTION_KEY = "vivomusicmix.meida.extra.key.action";
    private static final String LRC_CHANGE = "vivomusicmix.extra.lrc_change";
    private static final String LYRIC_KEY = "vivomusicmix.extra.key.lyric";
    private static final String MEDIA_ID_KEY = "vivomusicmix.extra.key.meidia_id";
    private static final long RESEND_INTERVAL_MS = 25_000L;

    // Separate from AudioService's notification handler, whose callbacks are
    // cleared on metadata updates. All publisher state belongs to the main thread.
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final boolean supported;
    private MediaSessionCompat session;
    private boolean playing;
    private String mediaId;
    private String lyric;
    private final Runnable resend = () -> publishCurrentLyrics(true);
    private final Runnable browserRefresh = () -> publishCurrentLyrics(true);

    VivoLyricsPublisher(MediaSessionCompat session) {
        this.session = session;
        String manufacturer = Build.MANUFACTURER.toLowerCase(Locale.ROOT);
        supported = manufacturer.contains("vivo") || manufacturer.contains("iqoo");
    }

    void onMetadataChanged() {
        if (!supported) return;
        handler.post(() -> publishCurrentLyrics(false));
    }

    void onBrowserConnected() {
        if (!supported) return;
        // Give the remote browser time to register its MediaController callback.
        handler.removeCallbacks(browserRefresh);
        handler.postDelayed(browserRefresh, 500L);
    }

    void setPlaying(boolean playing) {
        if (!supported) return;
        boolean resumed = !this.playing && playing;
        this.playing = playing;
        if (resumed) {
            publishCurrentLyrics(true);
        } else if (!playing) {
            handler.removeCallbacks(resend);
        }
    }

    private void publishCurrentLyrics(boolean force) {
        if (session == null) return;
        // Metadata arrives on worker threads. Read the session's current value
        // here rather than replaying a captured value from a previous song.
        MediaMetadataCompat metadata = session.getController().getMetadata();
        if (metadata == null) return;
        String nextId = metadata.getString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID);
        if (nextId == null || nextId.isEmpty()) return;
        String nextLyric = metadata.getString(LYRIC_KEY);
        if (nextLyric == null) nextLyric = "";
        if (!force && nextId.equals(mediaId) && nextLyric.equals(lyric)) return;
        mediaId = nextId;
        lyric = nextLyric;

        Bundle currentExtras = session.getController().getExtras();
        Bundle extras = currentExtras == null ? new Bundle() : new Bundle(currentExtras);
        extras.putString(ACTION_KEY, LRC_CHANGE);
        extras.putString(MEDIA_ID_KEY, mediaId);
        // An explicit empty lyric belongs to the new song and clears the old
        // lyric without replacing the entire session extras with an empty Bundle.
        extras.putString(LYRIC_KEY, lyric);
        session.setExtras(extras);

        handler.removeCallbacks(resend);
        if (playing && !lyric.isEmpty()) {
            handler.postDelayed(resend, RESEND_INTERVAL_MS);
        }
    }

    void close() {
        handler.removeCallbacksAndMessages(null);
        session = null;
    }
}
