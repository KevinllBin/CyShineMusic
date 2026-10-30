# BASS playback and GrooveShift

Android local playback uses a BASSmix output with a tempo decoding source. Online
playback keeps the direct BASS stream. The equalizer remains on the output.

GrooveShift is opt-in through Settings > Playback. Both consecutive sources must
be local and seekable. Analysis runs on one worker; BASS mixer position syncs
execute gain envelopes, filters, echo and source seeks. The Dart controller
confirms the next queue entry before native playback can start it, then adopts
metadata at the musical handoff. Transport and queue changes invalidate the
native generation and release effects, callbacks and the unused source.

The analysis/planning implementation is independent Kotlin code. Its compressed
numeric fixture was exported by directly invoking the original 12.5.1 algorithms
from the user-supplied analysis sample (SHA-256
68e06c391c0bb5ce39968547999f3d68021d26cf17e11e676b404c05e1d6fb0d).
No original DEX or proprietary application code is bundled in the player.

Run the algorithm regression suite from `android/`:

```sh
./gradlew :bass_player:testReleaseUnitTest
```

It checks 250 complete plans, 251 execution gain curves and 23 complete
synthetic analysis results. These are numeric/core tests, with no UI automation.
The no-sound emulator probe in `tool/` runs production classes for stereo,
mono/resampling, fade overlap, missing queue confirmation, seek and cancellation
before/during/after a transition. It requires the compiled release classes and
an authorized x86_64 emulator at emulator-5554; it installs no application.

Vendor provenance and notices are in `android/basslib/README.md` at the repository
root. In particular BASSmix uses the current official build, while BASS and
BASS FX retain the existing binaries. Passing numeric and native tests does not
establish sample-for-sample waveform equality with the original app. Physical
phone listening and notification/lyric acceptance are documented in
`docs/groove-shift-manual-test.md` at the repository root.

Diagnostics are included in Release builds. The native `CyShineTrace` journal
records source identities, mixer/source clocks and transition stages. Dart
records received snapshot sequences, EOF guards and metadata handoff decisions.
Normal clock records and repeated jump records are limited to one per second;
25 ms effect automation does not log per callback. The in-app log console can
export both rotated files to `Download/CyShineMusic/logs/` using MediaStore.
The exported text can be read with `adb pull` without root or a debug signature.
