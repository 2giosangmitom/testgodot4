# Level contract — node names the chapter scripts rely on

Phase 2 builders implement this exactly; Phase 3 chapter scripts (`chapters/chN.gd`) reference these names with
`level.get_node("...")`. If a name is impossible, keep the closest and report it. Geometry/markers come from
`docs/level_layouts.md` and `assets/models/env/*.glb` (see `MARKER_*` empties); props from `assets/models/props/*.glb`,
characters from `assets/models/chars/*.glb`.

## Scene skeleton (every level, root script `core/level_base.gd`)
```
<LevelRoot>  (LevelBase; level_id)
  Env          instanced env glb(s); PSXApply.apply_to(self) in _ready; -colonly colliders are static bodies
  Spawns/      Marker3D: names listed per level; -Z is the player's forward
  Markers/     Marker3D (cameras use FixedCamera nodes named cam_*), entity spots, ritual spots
  Presets/     LightingPreset children (names listed per level) each holding its lights (+ WorldEnvironment in ONE preset
               at a time is handled by LightingPreset). Fluorescent/streetlights are FlickerLight-driven.
  Doors/       Door instances (door_id = node name lowercase, e.g. shop_front)
  Interactables/  Interactable / Readable / PickupItem / minigame scenes
  Triggers/    TriggerZone nodes (trigger_id = node name)
  Entities/    entity scenes (start inactive unless noted); NPC statues placed here too
  NPCs/        static character glb instances (idle anim) used in cutscenes/dialogue, hidden by default (visible=false)
```
- Worldspace: WorldEnvironment with clear-color background, linear tonemap, NO Godot fog; ambient color per preset (low).
- Every level: `func _ready()` calls `PSXApply.apply_to(self)` once; meshes named `*_glass` / `*_emit` get the right shader.
- Crowd members/entities use character glbs; Mimic meshes must have shadows disabled.
- Navigation: a NavigationRegion3D (baked at edit-time or at runtime via `bake_navigation_mesh`) covering walkable floors for the Crowd.
- Level scene path = `res://levels/<level_id>/<level_id>.tscn`; a headless smoke test `res://levels/<level_id>/test_level.gd`
  (instances the level, spawns the player at every spawn, checks each node path in this contract exists, checks no script errors).
- A screenshot tool: `res://levels/<level_id>/shot.gd` (`-- --shot=<png> --cam=<marker name or spawn name> --preset=<id>`).

## `school` (level_id `school`)
- Spawns: `default` (inside gate), `classroom` (Nam's seat), `street` (street far end, x≈-35), `gate_outside`
- Presets: `day` (fog `day`, clock 16:40), `night_ch3` (fog `night`, sodium street lamps with FlickerLight `sodium`, clock 22:00, ambience `amb_street_dead`)
- NPCs (hidden by default): `Thay_Khai`, `Linh`, `Hung`, `BacTu` (guard booth, visible in ch3), `Students` (3 seated in classroom A)
- Interactables: `MissingPoster` (Readable id `missing_poster`, on Triggers-free wall in the courtyard among sitting students; sets flag `has_name_tag` when read), a `Door` under `Doors/` named `Grocery` (door_id `grocery`, unlocked) leading into the grocery shop,
  with `IncensePickup` (PickupItem item_id `incense`, inventory_item true) inside the grocery, `GuardOilPickup` (item_id `oil`, inventory_item true) in the guard booth.
- Entities (inactive; Phase 3 activates): `CrowdBusStop` (4× CrowdMember, pose `wait`), `CrowdSweepers` (2× `sweep` in the road), `CrowdTeaShop` (3× `sit` at plastic stools), `CrowdSchoolyard` (4× mixed, courtyard).
- Triggers: `trig_gate` (inside gate, Ch1 "ra cổng"), `trig_ch3_gate` (at the gate in Ch3), `trig_ch3_leave` (street end toward the alley)
- Markers: cams `cam_courtyard`, `cam_classroom`, `cam_gate`, `cam_street`, `cam_bus_stop`; `MARKER_seat_nam`
- Sounds: day ambience `amb_school_day` in `day`, classroom ambience when inside is optional (zone trigger).

## `store_alley` (level_id `store_alley`)
- Spawns: `default` (behind counter), `door` (inside front door), `alley_start` (storeroom back door outside), `front_street` (sidewalk in front, Ch4), `alley_mid`
- Presets: `night_store` (Ch1 night; fog `night_store`; fluorescent tubes in group `store_lights` via FlickerLight; amb `amb_store_night` + hum `hum_fluorescent`), `dusk_store` (Ch2 afternoon, fog `dusk`), `alley_predawn` (Ch1 05:00 alley; fog `night`, lamps flicker, amb `amb_alley_night`), `ch4_night` (fog `dread`, almost no lights, lamps dying)
- Doors: `ShopDoor` (door_id `shop_front`), `StoreroomDoor` (`storeroom`), `BackDoor` (`back_door`)
- Minigame scenes under Interactables: `Checkout` (id `checkout`, anchors at the register), `ShelfStock` (id `shelf_stock`, slots on gondola 2), `Mop` (id `mop`, stains in aisles), each `build_placeholder=false`, using real props (can_*, instant_noodle_pack, cardboard_box_*, mop, barcode_scanner, cash_register).
- Interactables: `RulesNote` (Readable `rules_note`, sets flag `read_rules` when read), `Drawer` (Interactable in storeroom; on use shows Readable `name_tag_store`, sets flag `found_name_tag_store`), `AlleyAltar` (Interactable in alley niche; Phase 3 handles incense logic; emits `used`), `Breaker` not here
- NPCs (hidden): `Hanh`, `Customer1` (xe ôm: `passerby_m1`), `Customer2` (silent girl: `student_f2`), `OldLady` (`ba_cu`) — each with a Marker in `Markers` (`npc_counter`, `npc_door`, `npc_exit`)
- Entities: `Gazer` (outside_glass, markers `gazer_1..gazer_6` far→near, last at the glass), `GazerHunt` (hunt, for Ch4 in alley, markers `hunt_1..hunt_5` along the alley)
- Triggers: `trig_alley_enter`, `trig_alley_end` (→ dorm_shrine), `trig_store_front_ch4`
- Markers: `cam_store_wide`, `cam_outside_glass`, `cam_alley`, `cam_counter`
- Light groups: `store_lights` (tubes), `alley_lights` (wall lamps)

## `dorm_shrine` (level_id `dorm_shrine`)
- Spawns: `default` (lane entrance z=0), `room` (inside P.204, facing the door), `corridor_stairs` (floor 2 top of stairs), `ground_floor`, `shrine_lane` (just before the square), `shrine`
- Presets: `night` (Ch2; fog `night`; corridor bulbs group `dorm_lights`; amb `amb_dorm_night`), `day` (Ch3 16:00, fog `overcast`, amb `amb_room_day`), `ch4_night` (fog `dread`, amb `amb_shrine`, drone `drone_dread` layer), `dawn` (Ending A, fog `dawn`)
- Doors: `Door204` (door_id `door_204`, lockable; Nam's), `Door203`, `Door202`, `Door201` (locked, decorative, TV glow under 203), `Door205` (locked padlocked), `RoomWCDoor`, `DormGate`
- Minigames: `Noodles` (id `noodles`, anchors on the low shelf), `RoomRoutine` (ids `lamp_switch_off`, `check_door_lock`, `go_to_sleep`; `door_path` → `Doors/Door204`; light_group `room_lights`)
- Interactables: `NoticeBoard` (Readable `notice_board`), `PhotoInBag` (Interactable on the loft: shows Readable `old_photo`, sets flags `seen_photo_room`, `has_photo`), `Breaker` (Interactable at ground floor; sets flag `breaker_on`, emits `EventBus.lights_set("dorm_lights", true)`), `Mirror` (Interactable in WC, emits `used`), `LightSwitch204` (LightSwitch group `room_lights`)
- Hide spots: under the desk (volume covers desk + space in front; crouch capsule 0.68 m, eye 0.60 m), inside the wardrobe gap
- Shrine area (square): `Ritual_Incense` (Interactable at the incense bowl), `Ritual_Photo` (at the altar), `Ritual_Oil` (at the lamp), `Ritual_Lamp` (the lamp; relight), each with disabled=false at start but Phase 3 controls `enabled`; `ShrineLamp` (OmniLight3D + oil_lamp prop, off), `TheStreetlight` (streetlight.glb + SpotLight3D/OmniLight3D with FlickerLight `sodium`, light group `streetlight`), `CallNamePoint` Marker (where the choice appears)
- NPCs (hidden): `Hung` (ending A), `MimicHung` and `MimicLinh` are Entities not NPCs
- Entities: `MimicDoor` (Mimic DOOR mode, impersonates hung, `door_path` Doors/Door204, outside marker `mimic_door_out`), `MimicCorridor` (CORRIDOR mode, impersonates linh, marker `mimic_corridor`), `GazerTuan` (Gazer `hunt`, markers along the lane and shrine square; final position under TheStreetlight `tuan_final`)
- Triggers: `trig_lane_enter`, `trig_stairs_up`, `trig_corridor`, `trig_room`, `trig_square` (shrine square), `trig_shrine_close` (near the altar)
- Markers: `cam_corridor`, `cam_room`, `cam_shrine_wide`, `cam_streetlight_low`, `cam_lane_end` (+ `tuan_*` markers)
- Light groups: `room_lights`, `dorm_lights`, `streetlight`

## Cross-cutting rules for builders
- Instance real props/characters (glb) — not primitives. Use `PSXApply`. Textures are Nearest.
- Keep each level under ~25k visible tris and ≤ 12 real-time lights; Forward+ with vertex lighting.
- Every node path above must exist (even if disabled or hidden) so Phase 3 can assume them.
- `Interactable.prompt` strings in Vietnamese ("Đọc", "Mở", "Nhặt", "Dùng", "Thắp nhang"...).
- Collision: player capsule r=0.3 must traverse every path (doors, aisles 1.1 m, stairs 0.9 m wide).
- Smoke test must pass: `godot --headless --path . -s res://levels/<id>/test_level.gd` exit code 0.
