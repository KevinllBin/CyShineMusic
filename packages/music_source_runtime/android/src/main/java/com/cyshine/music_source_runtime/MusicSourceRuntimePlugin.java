package com.cyshine.music_source_runtime;

import com.cyshine.music.source.MusicSourceRuntimeBridge;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding;

public final class MusicSourceRuntimePlugin implements FlutterPlugin {
    private MusicSourceRuntimeBridge bridge;

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        bridge = new MusicSourceRuntimeBridge(
            binding.getApplicationContext(),
            binding.getBinaryMessenger()
        );
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        if (bridge != null) {
            bridge.close();
            bridge = null;
        }
    }
}


