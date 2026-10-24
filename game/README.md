# DEVOUR CLONE: THE FARMHOUSE (MOLLY)

A first-person cooperative horror gameplay implementation in Godot 4.7.2 inspired by DEVOUR (Farmhouse level / Molly).

---

## 1. Quick Start

Run the standalone game scene directly (leaves `project.godot` demo scene untouched):

```bash
# Play mode (windowed GUI)
godot --path . res://game/scenes/main.tscn

# Headless verification (300 frames without crash or script error)
godot --headless --path . --quit-after 300 res://game/scenes/main.tscn
```

---

## 2. Controls & Interaction

| Input | Action | Details |
|---|---|---|
| **W, A, S, D** | Movement | Walk speed: 3.5 m/s |
| **Mouse Motion** | Look around | First-person camera with pitch limits [-80°, 80°] |
| **Left Shift (Hold)** | Sprint | Speed: 6.0 m/s. Drains Stamina (regenerates after 2s delay) |
| **Left Ctrl (Toggle/Hold)** | Crouch | Speed: 1.8 m/s. Silent movement (hearing radius = 0m) |
| **E** | Interact | Pick up rats (max 3), place rat on Sacrifice Pit, pour gasoline, ignite pit, open/close doors, unlock doors, pick up items |
| **G** | Drop Rat | Drops 1 carried rat to the ground; dropped rat flees immediately from player (3.5 m/s) |
| **F** | Flashlight Toggle | Toggles tactical illumination on/off |
| **Right Mouse Button (Hold)** | UV Flashlight Mode | Emits concentrated purple UV beam to stagger/stun Molly (`ability_int_data = 666`). Consumes battery (5s max burn, recharges automatically or with batteries) |
| **ESC** | Pause Menu | Toggle pause overlay |
| **R** | Restart | Reloads scene after Victory or Defeat |

---

## 3. The Farmhouse Layout (Level 2 - Molly)

The farmhouse is constructed programmatically via `FarmhouseBuilder` on a 4x4m modular grid with realistic wooden architecture:

1. **Ground Floor (Y = 0.0, Wall Height = 3.0m):**
   - **Front Porch & Entrance:** Starting area for the player with front door opening into the foyer.
   - **Living Room / Foyer:** Central chamber with the decorative Altar (no longer the sacrifice site; points players to the backyard).
   - **Back Door Passage:** North corridor opening at `(x = 0, z = -10)` leading directly out to the Backyard.
   - **Kitchen & Dining Room:** Contains food supplies (canned rations), clutter, gasoline canisters, and roaming rats.
   - **Hallway & Master Bedroom:** Master bedroom is locked; requires the **Master Bedroom Key** found in the cellar.
   - **Bathroom & Stairwells:** Central corridor connecting upstairs ramp (`x = -1, z = -1` ascending to Y = 3.0) and basement cellar stairs (`x = 1, z = -1` descending to Y = -3.0).

2. **Backyard (Sân Sau, Y = 0.0, Z = -10 to -24):**
   - Exterior gravel/dirt courtyard enclosed by wooden perimeter fences, lit by warm lantern posts.
   - Houses the stone **Sacrifice Pit** at `(x = 0, z = -17)` — the true ritual offering site for banishing Molly.
   - Contains decorative crates, barrels, dead pine trees, and spare gasoline canisters.

3. **Second Floor (Attic / Storage, Y = 3.0):**
   - Hallway with storage attic, spare fuse, food supplies, and rats hiding behind crates.
   - Stairwell opening at `(x = -1, z = -1)` connects down to Ground Floor.

4. **Basement Cellar (Y = -3.0):**
   - Pitch-black, claustrophobic stone cellar locked behind the **Cellar Door** (requires **Basement Key** found on the ground floor).
   - Contains trash cans with hidden rats, extra UV flashlight batteries, bedroom key, gasoline canister, and the spawning point where Molly resurrects.
   - Stairwell opening at `(x = 1, z = -1)` connects up to Ground Floor.

---

## 4. Core Objective & Rules

### Authentic 3-Step Rat Sacrifice Ritual (Nghi Thức Hiến Tế Chuột 3 Bước)
The ritual takes place exclusively at the **Sacrifice Pit in the Backyard** (the foyer altar is decorative):

1. **Step 1 - Place Rat (`is_placed_on_pit = true`):**
   - Catch roaming rats by pressing `[E]` (player carries up to 3 in bag).
   - Approach the backyard Sacrifice Pit and press `[E]` to place 1 carried rat onto the pit stone.
   - The rat stays stationary on the pit (`is_placed_on_pit = true`). HUD displays: *"Rat placed — pour gasoline"*.
2. **Step 2 - Pour Gasoline (`has_fuel = true`):**
   - Pick up a red Gasoline Canister (`gasoline.glb` / red can fallback) found in the kitchen, basement, or backyard.
   - Approach the pit and press `[E]` to pour gasoline over the offering. Consumes 1 canister.
   - Pit fuel status becomes active (`has_fuel = true`). HUD displays: *"Press [E] to ignite"*.
3. **Step 3 - Ignite Pit (`is_burning = true`):**
   - Press `[E]` once both rat and fuel are present.
   - The pit erupts in ritual flames for 1.5 seconds, burning the rat to ash.
   - `burnt_count += 1`, offering state resets (`has_rat_placed = false`, `has_fuel = false`), and Molly enrages.
   - *Requirement:* Missing either step prevents burning (rat without fuel cannot ignite; fuel without rat cannot ignite).

### Rat Fleeing Behavior
- **Escaped / Dropped Rats:** Pressing `[G]` drops 1 carried rat from the bag to the floor. The rat immediately sprints away from the player at **3.5 m/s** (> 1 meter in 60 frames) toward a distant navmesh point, squeaking in panic.
- **Offering Rats:** Once placed on the Sacrifice Pit, the rat does not flee and remains still awaiting fuel and ignition.

### Molly Escalation
As rats are burned, Molly's motor speed scales progressively:
- 0 rats burned: `1.00 m/s` (placid wander)
- 9 rats burned: `2.53 m/s` (frenzied enrage)

### Win & Loss Conditions
- **Win Condition:** Sacrifice **9 rats** at the Backyard Sacrifice Pit to banish Molly and cleanse the farmhouse.
- **Loss Condition:** Being grabbed by Molly **3 times** (tracked via Sanity / Hearts HUD).

### Sub-Items & Survival Mechanics
- **Gasoline Canisters:** Red fuel canisters placed in kitchen, cellar, and backyard; 1 canister provides 1 pour into the sacrifice pit.
- **Keys:** `Basement Key` unlocks the Cellar Door; `Master Bedroom Key` unlocks the Master Bedroom.
- **Electrical Fuses:** Found in rooms to repair blown fuse boxes.
- **Flashlight Batteries:** Instantly recharges the player's UV flashlight capacity to 100%.
- **First Aid Kits:** Restores 1 lost sanity life / grab point.
- **Canned Food / Rations:** Instantly restores stamina bar to 100%.

---

## 5. Collision Layer Matrix

- **Layer 1 (Bit 1):** `World` (Floors, walls, ceilings, ramps, furniture obstacles)
- **Layer 2 (Bit 2):** `Player` (Player CharacterBody3D)
- **Layer 3 (Bit 4):** `Ghost` (Molly CharacterBody3D)
- **Layer 4 (Bit 8):** `Interactables` (Rats, Altar, Doors, Trash Cans, Keys, Pickups)

---

## 6. Architecture & File Structure

```
game/
├── scenes/
│   ├── main.tscn              # Master game scene (GameManager, House, NavRegion, Spawns)
│   ├── player.tscn            # FPS Player CharacterBody3D with head/camera/lights/raycast
│   ├── ghost.tscn             # Molly Ghost CharacterBody3D with NavAgent and Brain
│   ├── sacrifice_pit.tscn     # Backyard Sacrifice Pit for authentic 3-step ritual
│   ├── altar.tscn             # Decorative Foyer Altar (points players to backyard)
│   ├── rat.tscn               # Catchable rat Area3D with wiggle & audio
│   ├── trash_can.tscn         # Interactive trash can StaticBody3D with hidden rat
│   ├── door.tscn              # Interactive AnimatableBody3D door with lock support
│   ├── pickup_item.tscn       # Interactive pickup Area3D (Keys, Fuses, Batteries, Meds, Food)
│   └── ui_hud.tscn            # CanvasLayer HUD (Rats, Keys, Sanity, Stamina, UV, Overlays)
├── scripts/
│   ├── game_manager.gd        # Game loop, rat burn scaling, grab counter, win/loss, respawns
│   ├── farmhouse_builder.gd   # 2-story + basement procedural modular architecture builder
│   ├── player_controller.gd   # FPS locomotion, sprint/crouch, UV flashlight, inventory
│   ├── ghost_actor.gd         # 14-method Actor API contract, vision cone, hearing, UV hit
│   ├── ghost_brain.gd         # BT runner bridge + standalone fallback AI loop
│   ├── sacrifice_pit.gd       # Backyard 3-step sacrifice pit (rat placed -> fuel poured -> ignited)
│   ├── altar.gd               # Decorative foyer altar interaction and guidance
│   ├── rat.gd                 # Rat actor API, BT integration, flee impulse, and wiggle logic
│   ├── trash_can.gd           # Trash can search interaction
│   ├── door.gd                # Door open/close hinge physics and key unlocking
│   ├── pickup_item.gd         # Key / consumable collection logic
│   └── ui_hud.gd              # HUD display, damage flash, win/loss/pause screens
└── assets/
    └── models/                # 3D GLB assets from Blender agent
```

---

## 7. Asset Status & Fallbacks

All 3D assets are integrated and backed by GLB files located in `game/assets/models/`:

1. **Scene Pre-configured Instances:**
   - `ghost.glb`: Instanced directly in `game/scenes/ghost.tscn` under `Visual/GhostModel` (scaled `0.85x` to fit 1.85m capsule, feet at y=0, glowing cyan eyes at y=1.6m).
   - `altar.glb`: Instanced directly in `game/scenes/altar.tscn` under `Visual/AltarModel` (box collider `2.24 x 1.11 x 1.24m`).
   - `candle.glb`: 4 instances placed at tabletop corners of `altar.tscn` with warm candle flame lights.
   - `door.glb`: Instanced in `game/scenes/door.tscn` with hinge pivot.
   - `flashlight.glb`: Instanced in `game/scenes/player.tscn` on player viewmodel.
   - `wall_module.glb`, `floor_module.glb`, `ceiling_module.glb`: Instanced across Ground Floor, Second Floor, and Basement levels in `farmhouse_builder.gd`.
   - `crate.glb`, `barrel.glb`, `rug.glb`, `painting.glb`: Instanced as interior decorative clutter.

2. **Dynamically Loaded GLBs:**
   - `rat.glb`: Loaded by `game/scripts/rat.gd` with wiggle animation.
   - `trash_can.glb`: Loaded by `game/scripts/trash_can.gd` with search trigger.
   - `key.glb`, `fuse.glb`, `battery.glb`, `first_aid.glb`, `food.glb`: Loaded dynamically by `game/scripts/pickup_item.gd` based on item type.

3. **Procedural Fallbacks (Graceful Degradation):**
   - Each script (`ghost_actor.gd`, `altar.gd`, `door.gd`, `rat.gd`, `trash_can.gd`, `pickup_item.gd`) contains procedural primitive fallbacks (MeshInstance3D box/capsule/cylinder with standard PBR materials). If any GLB fails to load or is deleted, the game continues to function without crashing.

4. **Visual Previews (Engine captures in `game/previews/`):**
   - `game/previews/1_spawn_altar.png`: Spawn view looking at the sacrificial Altar and corner candles.
   - `game/previews/2_ghost_4m.png`: Direct view of Molly (Ghost) illuminated by flashlight at 4m distance.
   - `game/previews/3_foyer_overview.png`: Wide view of the farmhouse living room / foyer showing ceiling beams and layout.
