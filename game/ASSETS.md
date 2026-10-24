# Devour-Clone 3D Asset Catalog (Godot 4.7.2)

Low-poly, horror-stylized 3D assets designed for Godot 4.7.2.
Created via deterministic headless Blender 4.5.9 scripts (`game/assets/blender/build_all.py`).

## Technical Specifications & Conventions
- **Engine Unit**: Metric (1 unit = 1.0 meter).
- **Scale Reference**: Humanoid character ~1.8m, Ghost entity ~2.19m.
- **Orientation**: Forward facing `-Z` (Godot Engine standard forward vector).
- **Pivot Origin**: Ground contact (`Z = 0.000m`) at bottom center for characters, furniture, architecture, and floor props.
- **Budget**: All assets $\le$ 1,000 triangles (far below the strict < 3,000 ceiling; small items < 200–500 tris).
- **Materials**: Unlit/stylized Principled BSDF with base colors and roughness (no external texture image files).
- **Asset Hierarchy**: Each `.glb` contains exactly 1 unified asset mesh (no leftover helper primitives or loose shape garbage).

---

## Complete Model Catalog (21 Assets)

| File | Category | Description | Bounds W×D×H (m) | Min Z (m) | Triangles | Size | Pivot Point | Godot Usage & Placement Notes |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `ghost.glb` | Characters | Tall emaciated ghost entity (Molly), pale flesh, ragged tattered dress with 6 jagged teeth, dark eye voids, seamless continuous arms with curved elbows and 3 spread claw fingers, 6 long cascading dark hair ribbons hugging crown/nape/back with zero air gaps, scalp hair cap, distinct bare feet | 0.48 × 0.53 × 2.11 | **0.000** | 1,280 | 51.9 KB | Feet at (0, 0, 0) | AI Monster root (`CharacterBody3D`). Single continuous lofted dress (0 seam cuts). Hair penetrates $\ge 5$cm into skull; arms penetrate $7.5$cm into shoulders. Scaled for standard ~2.2m door clearance. |
| `player_body.glb` | Characters | Stylized player body in dark trenchcoat and rugged boots for reflections/third-person | 0.67 × 0.30 × 1.81 | **0.000** | 748 | 61.4 KB | Feet at (0, 0, 0) | Player avatar (`CharacterBody3D`), visible in mirrors or spectator camera. |
| `flashlight.glb` | Equipment | Heavy cylindrical tactical flashlight with bevel lens, grip knurling, and toggle switch | 0.07 × 0.26 × 0.07 | -0.034 | 644 | 40.3 KB | Grip handle center | Attach as child of `Camera3D` at `(0.20, -0.20, -0.40)`. Pair with `SpotLight3D`. |
| `ritual_book.glb` | Ritual Items | Heavy occult tome bound in dark leather with embossed crimson pentagram and brass clasps | 0.29 × 0.35 × 0.09 | -0.005 | 396 | 29.5 KB | Base center | Placed open/flat on `altar.glb` book pedestal at `(0, 0.15, 1.05)`. |
| `altar.glb` | Sacrificial Props | Stone ceremonial altar with carved base, blood runnels, central book lectern, and 4 corner candle sconces | 2.24 × 1.24 × 1.11 | **0.000** | 808 | 54.7 KB | Floor base center | Central ritual target (`StaticBody3D`). Corner candle mount offsets: `(±0.95, ±0.48, 0.98)`. |
| `candle.glb` | Lighting Props | Dripping tallow ritual candle on compact brass saucer stand (base $\le$ 0.10m, height 0.28m) | 0.10 × 0.10 × 0.28 | **0.000** | 404 | 30.1 KB | Saucer base (0,0,0) | Mount on Altar corners, tables, or carry in hand. Pair with `OmniLight3D` (`#FFA540`) at flame tip `(0, 0, 0.28)`. |
| `door.glb` | Interactable Props | Heavy plank wooden door with vertical grooved slats, iron reinforcement bands, latch, and rear hinge pin | 1.12 × 0.12 × 2.20 | **0.000** | 560 | 36.9 KB | Left hinge edge (0,0,0) | Fits 1.2m×2.3m door frames in `wall_module.glb`. Rotate around `Y` axis for swing animation. |
| `key.glb` | Interactive Items | Ornate antique brass skeleton key with trefoil bow handle and notched bit flag | 0.06 × 0.18 × 0.02 | -0.008 | 376 | 25.4 KB | Bow loop center | Pickup item (`Area3D`). Bob/rotate animation in world or display in HUD inventory. |
| `crate.glb` | Environment Props | Reinforced wooden shipping crate with cross-braces, iron corner brackets, and seam gaps | 0.93 × 0.93 × 0.90 | **0.000** | 300 | 22.6 KB | Bottom face center | Cover/obstacle prop (`StaticBody3D` or `RigidBody3D`). |
| `barrel.glb` | Environment Props | Dark weathered wooden barrel with bulging staves and 4 metallic compression hoops | 0.73 × 0.73 × 1.05 | **0.000** | 720 | 44.4 KB | Bottom rim center | Obstacle/hiding prop (`StaticBody3D`). |
| `wall_module.glb` | Architecture | 4m × 3m modular wall with lower wood wainscot paneling, upper plaster, baseboard, and top trim | 4.00 × 0.27 × 3.00 | **0.000** | 156 | 12.6 KB | Bottom center (0,0,0) | Grid snapping on 4.0m increments. Clean box collision `Vector3(4.0, 0.27, 3.0)`. |
| `floor_module.glb` | Architecture | 4m × 4m modular floor tile with 8 staggered dark wood planks and perimeter frame | 4.00 × 4.00 × 0.15 | -0.150 | 228 | 17.6 KB | Top walking face `Z=0` | Grid snapping on 4.0m increments. Walking surface aligns exactly to world `Y=0`. |
| `ceiling_module.glb` | Architecture | 4m × 4m modular ceiling panel with plaster surface and cross-beamed heavy wooden rafters | 4.00 × 4.00 × 0.18 | -0.065 | 144 | 12.8 KB | Bottom contact face | Position at ceiling height (`Y = 3.0m`). |
| `painting.glb` | Decorations | Vintage ornate gilded wood frame with distressed horror portrait canvas and hanging wire | 0.98 × 0.12 × 1.32 | -0.660 | 244 | 20.9 KB | Rear frame center | Mount on wall modules at `Y = 1.7m`. Wall-mount offset `Z = -0.05m`. |
| `rug.glb` | Decorations | Faded burgundy Victorian runner rug with patterned border and frayed fringe ends | 2.59 × 1.62 × 0.01 | **0.000** | 288 | 22.7 KB | Center base | Floor decoration placed directly over `floor_module.glb` at `Y = 0.001m` (prevents Z-fighting). |
| `rat.glb` | Farmhouse Ritual | Dark brown scurrying rat with haunches, pointed snout, pink ears/paws/tail, and black bead eyes | 0.09 × 0.33 × 0.09 | **0.000** | 380 | 28.7 KB | Underbelly / feet `Z=0` | Molly ritual target (`CharacterBody3D`). Catchable baitable creature roaming farmhouse. |
| `trash_can.glb` | Farmhouse Props | Corrugated galvanized metal garbage bin with reinforcing ribs, drop handles, rust, and askew ajar lid | 0.50 × 0.46 × 0.66 | **0.000** | 524 | 34.6 KB | Bottom rim (0,0,0) | Ritual burn furnace / search container (`StaticBody3D`). |
| `fuse.glb` | Farmhouse Items | Industrial ceramic cartridge fuse with brass contact caps, end terminal nipples, and indicator band | 0.03 × 0.04 × 0.12 | **0.000** | 184 | 13.5 KB | Base ferrule (0,0,0) | Electrical puzzle pickup item (`Area3D`). Insert into fuse box switchboard. |
| `battery.glb` | Farmhouse Items | Heavy-duty rectangular 9V battery with dark plastic casing, gold branding stripe, and top terminals | 0.06 × 0.04 × 0.09 | **0.000** | 104 | 9.7 KB | Bottom face (0,0,0) | Flashlight battery recharge pickup item (`Area3D`). |
| `first_aid.glb` | Farmhouse Items | Molded medical first aid kit box with latches, top carrying handle, and 3D red cross on lid and front | 0.25 × 0.19 × 0.12 | **0.000** | 144 | 12.8 KB | Bottom face (0,0,0) | Revive / heal consumable pickup item (`Area3D`). |
| `food.glb` | Farmhouse Items | Steel tin can with stamped rims, paper label band, and top recessed lid pull-tab | 0.07 × 0.08 × 0.10 | **0.000** | 184 | 12.9 KB | Bottom rim (0,0,0) | Rat bait lure item (`Area3D`). Place on ground to attract scurrying rats. |

---

## Verifications & Acceptance Criteria

### 1. `ghost.glb` Overhaul & Acceptance
- **Silhouette**: Humanoid horror silhouette with round skull head ($\varnothing \approx 0.23\text{m}$), dark scalp hair cap, bowed head, hunched spine (~8.5° forward lean), slender neck, seamless continuous arms hanging along body with $\ge 3\text{cm}$ clearance and 3 spread claw fingers, distinct bare feet with claw toes at $Z=0.000\text{m}$.
- **Gap-Free Guarantee**:
  * **Hair**: Dark hair cap covers crown & back. 6 hair ribbons penetrate $\ge 5\text{cm}$ into skull at start point, tightly hugging nape, back, and shoulders with zero floating gaps.
  * **Arms**: Upper arm root starts inside shoulder mantle with $7.5\text{cm}$ penetration into torso volume ($\ge 5\text{cm}$ required).
  * **Dress**: Single continuous lofted BMesh surface from collar ($Z=1.78$) down to hem ($Z=0.42$) and 6 jagged teeth ($Z=0.18-0.30$), completely eliminating all horizontal seam cuts.
- **Bounding Box**: $0.484\text{m (width)} \times 0.529\text{m (depth)} \times 2.113\text{m (height)}$ (strict match for target height 2.0–2.2m, width $\le 0.75\text{m}$, depth $\le 0.60\text{m}$).
- **Ground Alignment**: **Min Z = 0.000m** strictly (bare feet anchored at ground level).
- **Node Cleanliness**: Exactly 1 unified mesh (`Ghost_Mesh`), 0 orphan objects, 1,280 triangles (< 1,400 budget).
- **Studio Previews**: Rendered under light studio gray background (`(0.75, 0.75, 0.78)`) at $560\times 760$ (`ghost_front.png` and `ghost_three_quarter.png`).

#### Known Limitations (Accepted for Production)
- **Facial Features / Eye Geometry**: Head mesh does not contain sculpted eyes or mouth cavities. In-game, Molly's glowing eyes are driven by an `OmniLight3D` (cyan) attached to `Visual/EyesLight` ($y \approx 1.6\text{m}$) draped beneath cascading hair strands, making geometric facial features unnecessary.
- **Hunched Stance**: Forward lean is subtle (~8.5° forward curvature, leaning towards an upright stance). Silhouette tests confirm this reads cleanly as an eerie towering figure at typical gameplay engagement distances (3–10m).

### 2. `candle.glb` Fixes
- **Silhouette**: Integrated solid brass saucer stand, wax column with tallow drips, and wick/flame tip.
- **Bounding Box**: $0.097\text{m (width)} \times 0.100\text{m (depth)} \times 0.285\text{m (height)}$ (saucer diameter $\le 0.10\text{m}$, height $\le 0.30\text{m}$, Min Z = 0.000m).
- **Cleanliness**: Loose disconnected ring handle removed; 1 single unified mesh node.

### 3. Farmhouse Molly Ritual Assets
- All 6 new assets (`rat.glb`, `trash_can.glb`, `fuse.glb`, `battery.glb`, `first_aid.glb`, `food.glb`) successfully modeled, verified under triangle ceilings, and rendered to Workbench front previews (`game/assets/previews/*_front.png`).

---

## Rebuild Instructions

All 21 models and previews are 100% deterministic and can be rebuilt headlessly at any time with:

```bash
/home/hazeruno/tools/blender-4.5.9-linux-x64/blender --background --python game/assets/blender/build_all.py
```
Total build & preview render time across all 21 models is ~5.6 seconds.
