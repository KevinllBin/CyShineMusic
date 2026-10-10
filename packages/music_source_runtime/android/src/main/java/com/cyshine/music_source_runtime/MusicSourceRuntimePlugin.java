package com.cyshine.music_source_runtime;

import com.cyshine.music.source.MusicSourceRuntimeBridge;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding;

public final class MusicSourceRuntimePlugin implements FlutterPlugin {
    private MusicSourceRuntimeBridge bridge;
    private MusicSourceRuntimeBridge updateBridge;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        bridge = new MusicSourceRuntimeBridge(
            binding.getApplicationContext(),
            binding.getBinaryMessenger()
        );
        updateBridge = new MusicSourceRuntimeBridge(
            binding.getApplicationContext(),
            binding.getBinaryMessenger(),
            "cy_shine_music/music_source_update_runtime"
        );
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (updateBridge != null) {
            updateBridge.close();
            updateBridge = null;
        }
        if (bridge != null) {
            bridge.close();
            bridge = null;
        }
    }
}


