# Credits

## Audio

All audio in `assets/audio/` was produced with the scripts in `tools/audio/` (see `tools/audio/build_all.sh`).
Most of it is procedurally synthesised (numpy). The recorded sources below were all released as **CC0 1.0
(public domain)**, so attribution is optional; we credit them anyway. The sources were resampled, filtered,
pitched, layered and bitcrushed. `tools/audio/fetch_cc0.py` downloads them.

### CC0 sound sources

| Source | Author | License | Files used → game sounds |
|---|---|---|---|
| [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney (www.kenney.nl) | CC0 1.0 | `footstep_concrete_000–004`, `footstep_wood_000–004`, `impactGlass_light_000–002`, `impactGeneric_light_002`, `impactTin_medium_001` → footstep_concrete/tile/wood/stiff, glass_tap, item_drop, can_place |
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 | `tick_001`, `tick_002`, `select_002`, `back_002`, `toggle_001` → ui_move, phone_tap, ui_select, ui_back, phone_open |
| [RPG Audio](https://kenney.nl/assets/rpg-audio) | Kenney | CC0 1.0 | `creak2`, `doorClose_4`, `metalLatch`, `metalClick`, `handleSmallLeather`, `bookOpen` → door_open_creak, door_close, door_lock, door_handle_rattle, stove_click, item_pickup, box_open |
| [UI Audio](https://kenney.nl/assets/ui-audio) | Kenney | CC0 1.0 | `switch3`, `switch10`, `switch20` → flashlight_click, fan_click, light_switch |
| [100 CC0 metal and wood SFX](https://opengameart.org/content/100-cc0-metal-and-wood-sfx) | rubberduck | CC0 1.0 | `lock_open_01`, `metal_open_01`, `wood_hit_07–09`, `wood_slam_04`, `wood_squeak_01` → door_unlock, register_open, door_knock_3, door_knock_slow, mop_squeak |
| [10 book page flips](https://opengameart.org/content/10-book-page-flips) | StarNinjas | CC0 1.0 | `book_flip.3` → page_turn |
| [Boiling water loops](https://opengameart.org/content/boiling-water-loops) | TinyWorlds | CC0 1.0 | `cooking_without_cover_01` → water_boil |
| [Breathing tired](https://opengameart.org/content/breathing-tired) | mikeask | CC0 1.0 | `breathing tired.wav` → breath_heavy |
| [Horror breathing](https://opengameart.org/content/horror-breathing) | primbal | CC0 1.0 | `horrorbreathing.wav` → breath_scared |
| [Dog barking (mono)](https://opengameart.org/content/dog-barking-mono) | Brandon Morris (submitted by HaelDB) | CC0 1.0 (dual-licensed CC0 / OGA-BY 3.0; we use CC0) | `dog_barking_mono.wav` → dog_bark_far, amb_alley_night |

### Speech synthesis

The voice lines (`assets/audio/voice/`), the vendor calls in `rao_dem`, the whisper material in `entity_whisper`,
and the murmur in the crowd and TV ambiences were generated with
[VieNeu-TTS v3 Turbo](https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo) by Phạm Nguyễn Ngọc Bảo,
using its built-in preset voices. The model, SDK and preset voices are licensed under Apache License 2.0, and
the model card explicitly allows commercial use of the generated audio.
Codec: [MOSS-Audio-Tokenizer-Nano](https://huggingface.co/OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano) (OpenMOSS).

### Synthesised in-house

Everything else, including all music, all ambience loops, shop_bell, scanner_beep, heartbeat, static_burst,
jumpscare_sting, stinger_low, motorbike_pass, shrine_bell, wind_chime, water_drip, water_pour, buzz_wrong,
match_strike, phone_vibrate, fluorescent_flicker and hum_fluorescent, was synthesised by `tools/audio/synth.py`.
