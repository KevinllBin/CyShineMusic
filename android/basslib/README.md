# BASS Android playback module

This module vendors the official Android distributions used by the app's
native playback engine:

- BASS 2.4.18.3
- BASS FX 2.4.12.6
- BASSFLAC 2.4.6.1
- BASSAPE 2.4.1
- BASSALAC 2.4.1
- BASS_SSL (OpenSSL 1.1.1w)

MP3, OGG and WAV are decoded by BASS itself. Android media codecs cover AAC,
M4A and device-supported WMA, while the bundled add-ons make FLAC, APE and ALAC
support independent of the device codec implementation.

HTTPS streams require `libbass_ssl.so` alongside `libbass.so` in each of
`arm64-v8a`, `armeabi-v7a`, `x86` and `x86_64`. BASS automatically loads this
extension when opening an HTTPS URL; it is not a decoder plugin and does not
need `BASS_PluginLoad`. Apps targeting Android API 24 or later cannot fall back
to Android's private system SSL libraries. Omitting this extension causes
`BASS_ERROR_SSL` (10), even when HTTP playback works. See the official
[BASS_CONFIG_LIBSSL documentation](https://www.un4seen.com/doc/bass/BASS_CONFIG_LIBSSL.html).
The `verifyBassSslLibraries` pre-build task rejects missing ABI copies.

The SSL libraries were copied unchanged from the
[official Android BASS_SSL archive](https://www.un4seen.com/files/bass_ssl-android.zip)
on 2026-10-11. Its `version.txt` reports `OpenSSL 1.1.1w`; all four ELF builds
have 16 KB load-segment alignment. Archive SHA-256:
`991f9dca218288c8966a3df43a5e659a5f70de7d6482c483aca17afbcc0b5c55`.
The [OpenSSL and SSLeay license notices](src/main/assets/licenses/BASS_SSL-OpenSSL-LICENSE.txt)
are also packaged in the APK as `assets/licenses/BASS_SSL-OpenSSL-LICENSE.txt`.

Playback currently defaults to AudioTrack after an output comparison on Redmi
K90 resolved quieter, muffled playback. Both backends remain available through
`OUTPUT_BACKEND` in `BassPlayerPlugin.kt`: `AUDIO_TRACK` selects AudioTrack, while
`AAUDIO` uses BASS's default AAudio output on Android 8.1+ (OpenSL ES on older
devices). This selection changes the output backend only; BASS decoding and
the equalizer chain are shared. Output diagnostics are logged under `CyShineBass`.

BASS is free only for non-commercial use. Review every `*-LICENSE.txt` file in
this directory and the bundled SSL notices before redistributing or monetizing
the application.
