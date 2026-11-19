# Level layouts (contract between Track C1 env models and Phase 2 level builders)

Hanoi, present day, poor student neighborhood. Cramped, layered, humid: peeling lime-wash walls,
roller shutters (cửa cuốn), tangled electric cables overhead, plastic stools, potted plants, motorbikes.
Each env glb is exported in **level coordinates** (origin = level origin), so Phase 2 just instances it at (0,0,0).
Collision: duplicate simple boxes named `<name>-colonly` (Godot import hint → static collision only).
Walkable floors must have collision. Glass must be a separate mesh object named `*_glass` (Godot assigns PSX glass shader).
Doors that open are **separate glbs** (`door_wood.glb`, `door_glass_shop.glb`, `door_dorm.glb`) with pivot at hinge;
the env leaves an empty doorway + `MARKER_door_<id>` empty (Blender empties export as Node3D → used as placement markers).
All named empties should be prefixed `MARKER_` (spawn points, light positions, camera spots, entity spots).

## Scene 1: `school` — Giảng đường & sân trường (`assets/models/env/school.glb`)
- Gate on the street side at z=0, school extends toward −z.
- **Street outside the gate** (z 0 → +14): 6 m asphalt road along x (−40..+40), sidewalks, 4 streetlights (MARKER_streetlight_1..4), a bus-stop shelter at x=+12 (MARKER_bus_stop), shuttered shop fronts on the far side. Used in Ch3 night with the Crowd.
- **Gate + guard booth** (x −6, z −1): booth 2×2 m with window, plastic chair; sliding iron gate.
- **Courtyard** 22×16 m (z −2 → −18): flagpole, 2 low-poly trees with brick planters, stone bench, bike/motorbike shed along left wall (x −11).
- **Building** (z −18 → −28), 2 floors visible but only ground floor enterable: corridor 3 m wide along x (−15..+15) with open railing to courtyard, 3 classroom doors.
- **Classroom A** (enterable, 9×10 m, behind middle door): blackboard + teacher desk on −x wall, 5 rows × 2 columns of 2-seat desks, 3 ceiling fans, windows on courtyard side, a clock. MARKER_seat_nam (3rd row, window side).
- Markers: MARKER_spawn_default (gate inside), MARKER_spawn_classroom (Nam's seat), MARKER_spawn_street (street, far end x=−35), MARKER_cam_* (≥4 fixed cutscene cameras: courtyard wide, classroom from teacher desk, gate, street long shot).

## Scene 2: `store_alley` — Cửa hàng tiện lợi 24/7 + con ngõ (`assets/models/env/store.glb`, `assets/models/env/alley.glb`)
- **Store** ("Tiện Lợi 24h Ánh Dương") interior 10 m (x −5..+5) × 8 m (z 0..−8). Front at z=0 is a **full glass wall** (`store_front_glass`) with automatic-style glass door at x=+3.5 (MARKER_door_shop). Sign box above front.
  - 4 shelf gondolas running along z (x = −3.2, −1.6, 0, +1.6), 1.1 m aisles, 1.6 m tall, each with ~12 empty slots per side marked by MARKER_slot_<row>_<n> (for the stocking minigame — only gondola 2 needs slots).
  - Counter + register at front-right (x +3, z −1.5) facing the door; space behind counter for crouching (hide spot, MARKER_hide_counter). Cigarette/phone-card rack behind.
  - Drink fridges along back wall (z −8) with glass doors (`fridge_glass`).
  - Back right door (x +4, z −8) → **storeroom** 4×4 m (x +1..+5, z −8..−12) with stacked boxes, mop bucket, breaker box (MARKER_breaker), back door to alley (MARKER_door_back).
  - Ceiling: 2 rows of fluorescent tube fixtures (MARKER_light_tube_1..6).
- **Street front** (z 0 → +12): sidewalk 3 m, road 6 m, far sidewalk + shuttered houses; streetlights at x −10, +10 (MARKER_streetlight_*). Gazer stands at MARKER_gazer_1..6 (far sidewalk → near the glass, ending right at the glass).
- **Alley** (`alley.glb`): starts at the storeroom back door (x +5, z −12) and winds 60 m toward −x/−z with 2 turns, width 1.8–2.5 m, 3–4 storey walls with moss/stains, balconies, AC units, tangled overhead cables, parked motorbikes, potted plants, a household altar niche, one flickering wall lamp every ~12 m (MARKER_alley_lamp_*). Ends at MARKER_alley_exit (transition to `dorm_shrine`). Also a "streetlight at the far end" visible through fog: MARKER_alley_far_light.
- Spawns: MARKER_spawn_default (behind counter), MARKER_spawn_door (inside front door), MARKER_spawn_alley_start, cams MARKER_cam_store_wide, MARKER_cam_outside_glass, MARKER_cam_alley.

## Scene 3: `dorm_shrine` — Khu trọ + ngôi miếu cuối ngõ (`assets/models/env/dorm.glb`, `assets/models/env/shrine.glb`)
- **Alley entrance** at z=0 (MARKER_spawn_default), 2 m wide lane going −z for 15 m to the dorm gate on the left (x −1).
- **Dorm** ("Nhà trọ") 3 storeys, only floor 1 (ground) + floor 2 enterable:
  - Ground: motorbike parking under the stairs, landlord's notice board, mailbox, water meter. Narrow straight staircase 0.9 m wide up to floor 2.
  - Floor 2: open-air corridor 1.4 m wide, 18 m long with **5 room doors** (P.201–P.205, MARKER_door_201..205). Nam is **P.204**. P.205 at the end is padlocked. Railing overlooks the lane. A single bulb per 2 doors (MARKER_corridor_bulb_*).
  - **Nam's room P.204** (3 m × 5 m = 15 m², 3.2 m tall): door at front; inside: loft (gác xép) at 1.9 m over the back half with a wooden ladder, mattress + desk on loft; floor: small desk with laptop, plastic wardrobe, mini fridge, gas stove + pot on a low shelf (cooking minigame), standing fan, window to the corridor with bars. Back-left: tiny WC (1.2×1.5 m) with squat toilet, bucket, mirror (MARKER_mirror). Light switch by door (MARKER_switch_room). Under-desk hide spot.
  - P.203 (Hùng's former room? No—Hùng shares P.204; P.203 neighbor) just a closed door with TV glow under it.
- **Dead-end lane** continues past the dorm another 20 m (z −15 → −35), narrowing to 1.5 m, to a small square 6×6 m with a **giant banyan tree** (cây đa) and the **abandoned shrine** (miếu): 2.5×2.5 m, tiled curved roof, faded red pillars, altar with incense bowl (MARKER_incense_bowl), broken oil lamp (MARKER_shrine_lamp), cracked photo frame, fallen joss paper. Behind/next to it **the streetlight** (cột đèn đường, MARKER_the_streetlight), tall, sodium orange, slightly bent.
- Cams: MARKER_cam_corridor, MARKER_cam_room, MARKER_cam_shrine_wide, MARKER_cam_streetlight_low (ending shots).

## Day/night reuse
Levels are reused per chapter by switching `Presets/` (day, night, ch3_night, ch4_night, dawn) and moving entity markers —
never by duplicating geometry.
