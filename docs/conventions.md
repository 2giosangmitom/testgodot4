# Conventions — Đèn Đường Cuối Ngõ

Godot **4.7.2**, GDScript, Forward+. Every track MUST follow this file. If you need something that
is not here (new signal, new input action, project setting, autoload), **do not edit
`project.godot` or `autoload/` or `core/`** — list the request in your final report; the main
session applies it.

## Ownership (each track edits only its own dirs)
| Track | Owns |
|---|---|
| main session | `project.godot`, `autoload/`, `core/`, `docs/`, `data/`, `chapters/`, `tests/run_tests.gd` |
| A Rendering | `render/` |
| B Player/UI | `player/`, `ui/`, `assets/fonts/` |
| C Assets | `tools/blender/`, `tools/textures/`, `assets/models/`, `assets/textures/` |
| D Audio | `tools/audio/`, `assets/audio/`, `CREDITS.md` |
| E1 Minigames | `gameplay/minigames/` |
| E2 Entities | `gameplay/entities/` |
| Phase 2 levels | `levels/<its level>/` only |

Tests: put your own test scenes inside your own dir (`render/test_psx.tscn`, ...).

## Units, axes, scale
- 1 unit = 1 m. Y up. Player eye height 1.62 m standing, 0.9 m crouched. Player capsule r=0.3 h=1.75.
- Doors 0.9×2.1 m. Ceiling 2.8 m (dorm 3.2 m with loft at 1.9 m). Store aisles 1.1 m wide (cramped).
- Blender exports glTF with `+Y up` (default exporter), apply modifiers, meters.

## Physics layers (bit index → value)
| # | name | value | used by |
|---|---|---|---|
| 1 | world | 1 | static geometry, walls, floor |
| 2 | player | 2 | player body |
| 3 | interactable | 4 | `Interactable` bodies (player raycast mask) |
| 4 | entity | 8 | Gazer/Mimic/Crowd bodies |
| 5 | trigger | 16 | `Area3D` triggers (mask = player 2) |
| 6 | pickup | 32 | holdable items in minigames |

Player interact raycast mask = `1 | 4 | 32` (world blocks). Length 2.0 m.

## Groups
- `player` — the player node (also `GameState.player`).
- `interactable` — every `Interactable`.
- `entity` — every supernatural entity root.
- `flicker_lights` + a level-specific group (e.g. `store_lights`) — lights that react to `EventBus.lights_flicker(group, dur)` / `lights_set(group, on)`.
- `level` — level root (`LevelBase`).
- `hide_spot` — Area3D under desks/counters; crouching inside → player hidden.

## Shared code you can rely on (main session owns)
- `core/interactable.gd` — `class_name Interactable extends StaticBody3D`.
  `prompt`, `enabled`, `one_shot`, `objective_id`, `get_prompt()`, `can_interact(p)`, `interact(p)`,
  override `_on_interact(player)`, signal `used(player)`. Sets layer 3 automatically.
- `core/level_base.gd` — `class_name LevelBase`; `apply_preset(id)`, `spawn_player(id)`, `get_spawn(id)`, `get_marker(id)`.
  Level children: `Spawns/`, `Markers/`, `Presets/` (LightingPreset), `Entities/`.
- `core/lighting_preset.gd` — `class_name LightingPreset`; `fog_preset`, `ambience`, `ambience_hum`, `clock_hours`.
- `core/chapter_script.gd` — `class_name ChapterScript`; `run()`, helpers `wait`, `objective`, `wait_objective`, `wait_flag`, `checkpoint`.

## Autoloads (singletons)
- **InputSetup** — registers actions at runtime: `move_forward move_back move_left move_right sprint crouch interact phone flashlight pause skip answer phone_next secondary`. (`interact` = E + LMB, `secondary` = RMB, `answer` = Y used to reply to a voice behind a door.)
- **EventBus** — all cross-system signals. Read `autoload/event_bus.gd`; it is the contract. Key ones:
  `noise_emitted(pos, loudness 0..1)`, `flashlight_toggled(on)`, `player_caught(entity_id, cause)`,
  `static_amount(v)`, `lights_flicker(group, dur)`, `subtitle(speaker, text, dur)`, `choice_requested(prompt, options)` → UI emits `choice_made(i)`,
  `fade_request(to_black, dur)` → UI emits `fade_done`, `letterbox(on)`, `toast(text)`, `interact_prompt(text)`,
  `door_knock(door_id)`, `door_state_changed(door_id, open)`, `minigame_completed(id)`.
- **GameState** — `chapter`, `phase`, flags (`set_flag/get_flag`), `add_resolve(delta, reason)`, objectives
  (`add_objective/complete_objective/is_objective_done`), `unlock_message(id)`, `unlocked_messages`,
  clock (`set_clock`, `clock_string()`), input locks (`lock_input(reason)/unlock_input(reason)/is_input_locked()`),
  `player`, `flashlight_on`, `phone_open`, `debug_autoplay` (run with `-- --autoplay`).
- **SaveSystem** — checkpoints + profile settings (`get_setting/set_setting`).
- **AudioDirector** — `play_sfx(name, vol_db, pitch, bus)`, `play_sfx_3d(name, pos, ...)`, `play_ambience(name, layer, vol_db, fade)`,
  `stop_ambience(layer)`, `play_music(name)`, `play_voice(key) -> seconds`. Names resolve to
  `assets/audio/{sfx,amb,music,voice}/<name>.(ogg|wav)`. Missing files only warn → safe to call before audio exists.
  Buses: `Master Music Amb SFX Voice Entity`.
- **Dialogue** — `await Dialogue.say(key)`, `await Dialogue.say_seq([...])`, `var i = await Dialogue.ask(prompt, options, timeout, default)`,
  `get_message(id)`, `speaker_name(id)`.
- **RenderSettings** — `set_fog_preset(name, dur)` (`day overcast dusk night night_store dread dawn`), `set_fog(near, far, color, dur)`,
  `set_static(0..1)`, `set_low_res(bool)`.
- **ChapterDirector** — `await goto_level(id, spawn, preset)`, ids `school | store_alley | dorm_shrine`; `start_chapter(n)`.

## PSX shader globals (project.godot `[shader_globals]`)
`psx_fog_color (color)`, `psx_fog_near (float)`, `psx_fog_far (float)`, `psx_snap_resolution (vec2)`,
`psx_affine_strength (float 0..1)`, `psx_static (float 0..1)`, `psx_time_scale (float)`.
Use them in shaders as `global uniform float psx_fog_near;` etc. Do NOT use Godot Environment fog —
fog is done in the PSX shaders so it is identical everywhere. Background clear color = fog color.

## Expected public APIs between tracks
**Player** (`res://player/player.tscn`, root `class_name Player extends CharacterBody3D`, group `player`):
`get_camera() -> Camera3D`, `teleport(xform: Transform3D)`, `is_crouching()`, `is_sprinting()`, `is_hidden()`,
`look_at_point(pos: Vector3, duration)` (forced look for scares), `set_controls_enabled(bool)`,
`hold_item(node: Node3D)` / `release_item()` / `get_held_item()`, `kill(cause: String)` (plays death, emits `player_caught`),
`get_hold_point() -> Node3D` (in front of camera). Respects `GameState.is_input_locked()`.
Emits `EventBus.noise_emitted` from footsteps (walk 0.15, crouch 0.05, sprint 0.8).

**Render**: `res://render/psx_root.tscn` is NOT required — the game uses the project's 640x480 viewport stretch.
Post-fx is a CanvasLayer scene `res://render/post_fx.tscn` that UI/levels instance once (B instances it in the HUD).
Materials: `res://render/materials/psx_lit.tres` etc.; shaders in `res://render/shaders/`.
A helper `res://render/psx_material_factory.gd` (`static func make(albedo: Texture2D, opts := {}) -> ShaderMaterial`) and
`res://render/psx_apply.gd` (`static func apply_to(node: Node)` — walks MeshInstance3D children and replaces their
StandardMaterial3D with PSX materials keeping the albedo texture). Levels and imported glbs use `psx_apply`.

**Entities** expose `activate()`, `deactivate()`, `entity_id`, and live under a level's `Entities/` node.

**Minigames** each a scene with root script exposing `signal completed`, `start()`, `minigame_id`, emitting
`EventBus.minigame_completed(minigame_id)` too.

## Data formats (`data/dialogue/`)
`speakers.json`:
```json
{ "nam": {"name": "Nam", "voice": "Hải Đăng"}, "hung": {"name": "Hùng", "voice": "Thiện Minh"} }
```
`lines_<chapter>.json` (key → line). `fx`: `none` | `phone` (thin, band-passed) | `radio` | `door` (muffled) | `entity` (reverse/pitch/static):
```json
{ "ch1_hung_01": {"speaker": "hung", "text": "Ê Nam, tối nay mày trực à?", "fx": "none"} }
```
`messages.json` (phone SMS):
```json
{ "m_ch2_hung_01": {"from": "hung", "time": "21:40", "text": "Tao về quê rồi nhé...", "chapter": 2} }
```
Voice files: `assets/audio/voice/<key>.ogg`, 22050 Hz mono.

## Text / language
All in-game text Vietnamese with full diacritics. Fonts must support Vietnamese (OFL fonts only).
Brand and person names are fictional (store chain: **"Tiện Lợi 24h Ánh Dương"**). No real logos.

## Art rules (PSX)
- Textures ≤ 256 px (characters/props 64–128), **Nearest** filter, no mipmaps; import with
  `compress/mode=0 (lossless)`, `mipmaps/generate=false`.
- Palette: desaturated, slight green/yellow cast at night (fluorescent), sodium orange for streetlights.
- Characters 300–700 tris, faces are flat 64×64 textures.
- No real-time soft shadows. Use few lights; prefer vertex lighting (`render_mode vertex_lighting`).

## Git
Work on your worktree branch, commit often with clear messages, end commit messages with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Don't commit `.godot/`.
Verify with `godot --headless --path . --import` (must not print script/shader errors for your files)
and, for runtime checks, `godot --headless --path . res://<your_test>.tscn --quit-after 120`.
