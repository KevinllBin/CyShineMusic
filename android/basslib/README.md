# BASS Android playback module

This module vendors the official Android distributions used by the app's
native playback engine:

- BASS 2.4.18.3
- BASS FX 2.4.12.6
- BASSFLAC 2.4.6.1
- BASSAPE 2.4.1
- BASSALAC 2.4.1

MP3, OGG and WAV are decoded by BASS itself. Android media codecs cover AAC,
M4A and device-supported WMA, while the bundled add-ons make FLAC, APE and ALAC
support independent of the device codec implementation.

Playback currently defaults to AudioTrack after an output comparison on Redmi
K90 resolved quieter, muffled playback. Both backends remain available through
`OUTPUT_BACKEND` in `BassPlayerPlugin.kt`: `AUDIO_TRACK` selects AudioTrack, while
`AAUDIO` uses BASS's default AAudio output on Android 8.1+ (OpenSL ES on older
devices). This selection changes the output backend only; BASS decoding and
the equalizer chain are shared. Output diagnostics are logged under `CyShineBass`.

BASS is free only for non-commercial use. Review every `*-LICENSE.txt` file in
this directory before redistributing or monetizing the application.
