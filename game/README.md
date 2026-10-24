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
| **E** | Interact | Pick up rats (max 3), burn rats at Altar, open/close doors, unlock doors, pick up items |
| **F** | Flashlight Toggle | Toggles tactical illumination on/off |
| **Right Mouse Button (Hold)** | UV Flashlight Mode | Emits concentrated purple UV beam to stagger/stun Molly (`ability_int_data = 666`). Consumes battery (5s max burn, recharges automatically or with batteries) |
| **ESC** | Pause Menu | Toggle pause overlay |
| **R** | Restart | Reloads scene after Victory or Defeat |

---

## 3. The Farmhouse Layout (Level 2 - Molly)

The farmhouse is constructed programmatically via `FarmhouseBuilder` on a 4x4m modular grid with realistic wooden architecture:

1. **Ground Floor (Y = 0.0, Wall Height = 3.0m):**
   - **Front Porch & Entrance:** Starting area for the player with front door opening into the foyer.
   - **Living Room / Foyer:** Central chamber housing the **Altar of Banishment**, lit by candles and eerie moonlight.
   - **Kitchen & Dining Room:** Contains food supplies (canned rations), clutter, and roaming rats.
   - **Hallway & Master Bedroom:** Master bedroom is locked; requires the **Master Bedroom Key** found in the cellar.
   - **Bathroom & Stairwells:** Central corridor connecting upstairs ramp (`x = -1, z = -1` ascending to Y = 3.0) and basement cellar stairs (`x = 1, z = -1` descending to Y = -3.0).

2. **Second Floor (Attic / Storage, Y = 3.0):**
   - Hallway with storage attic, spare fuse, food supplies, and rats hiding behind crates.
   - Stairwell opening at `(x = -1, z = -1)` connects down to Ground Floor.

3. **Basement Cellar (Y = -3.0):**
   - Pitch-black, claustrophobic stone cellar locked behind the **Cellar Door** (requires **Basement Key** found on the ground floor).
   - Contains trash cans with hidden rats, extra UV flashlight batteries, bedroom key, and the spawning point where Molly resurrects.
   - Stairwell opening at `(x = 1, z = -1)` connects up to Ground Floor.

---

## 4. Core Objective & Rules

### Rat Sacrifice Ritual (Đốt Chuột)
1. **Spawn:** 11 initial rats roam the farmhouse (cellar, attic, kitchen, and inside trash cans).
2. **Collect:** Press `[E]` to catch rats. The player can carry up to **3 rats** at a time in their bag.
3. **Sacrifice:** Bring rats to the central Altar and press `[E]` to burn them. Each rat burned triggers an intense flame burst and updates the candle lights.
4. **Molly Escalation:** As more rats are burned, Molly's motor speed scales progressively:
   - 0 rats burned: `1.00 m/s` (placid wander)
   - 9 rats burned: `2.53 m/s` (frenzied enrage)
5. **Win Condition:** Sacrifice **9 rats** at the Altar to banish Molly and cleanse the farmhouse.
6. **Loss Condition:** Being grabbed by Molly **3 times** (tracked via Sanity / Hearts HUD).

### Sub-Items & Survival Mechanics
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
│   ├── altar.tscn             # Sacrificial Altar with lights and trigger area
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
│   ├── altar.gd               # Sacrificial altar interaction and burnt count tracking
│   ├── rat.gd                 # Rat idle wiggle, catch logic, and audio
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
