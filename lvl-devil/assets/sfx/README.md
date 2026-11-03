# SFX — CC0 sound effects

All five files in this directory are original syntheses generated with a
stdlib-only Python script (`wave` + `math` + `random`, fixed seed) and are
released under **CC0** (public domain dedication). No third-party audio
bytes are included; no music stream ships with this game.

Timbre reference: [Kenney](https://kenney.nl) CC0 game-audio packs were used
only as a listening reference for the cartoon timbres (no Kenney binaries
are included). Compatible with freesound-CC0 style short one-shots.

| File | Duration | Recipe | Volume (`volume_db`) |
|---|---|---|---|
| `jump.wav` | 0.12 s | Rising sine blip 300 → 660 Hz | −10 dB |
| `sting.wav` | 0.40 s | Rising two-tone uh-oh sting (220 Hz → 330 Hz) | −8 dB |
| `squelch.wav` | 0.25 s | Decaying low-passed noise burst + 120 Hz wobble (cartoon squelch) | −8 dB |
| `chime.wav` | 0.40 s | Two-note sine chime E5 (659.25 Hz) → A5 (880 Hz) | −10 dB |
| `whoomph.wav` | 0.30 s | Falling filtered-noise whoosh (brightness sweeps down) | −12 dB |

Format: 44.1 kHz, 16-bit mono WAV, peak-normalized to ≈ −3 dBFS. All bus
volumes are capped modest (−12 to −6 dB). Wiring: `res://scripts/audio.gd`
(`SfxBus`) preloads these five streams and exposes
`play_jump/play_sting/play_squelch/play_chime/play_whoomph`.

No music: there is no `music.*` asset and no music bus/stream in the game.
