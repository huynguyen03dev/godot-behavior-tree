#!/usr/bin/env python3
"""
Master build script for Devour-clone low-poly horror 3D models.
Generates all 21 GLB models headless with Blender 4.5.9 and renders
560x720 Workbench front preview images with camera auto-framing.

Usage:
  /home/hazeruno/tools/blender-4.5.9-linux-x64/blender --background --python game/assets/blender/build_all.py
"""

import os
import sys
import time

# Ensure local blender scripts directory is in sys.path
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import bpy
import common
import characters
import items
import props
import environment

OUTPUT_MODELS_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "models")
OUTPUT_PREVIEWS_DIR = os.path.join(os.path.dirname(SCRIPT_DIR), "previews")

ASSET_DEFINITIONS = [
    # --- Base Assets (1-15) ---
    {
        "file": "ghost.glb",
        "category": "Characters",
        "description": "Emaciated tall ghost with dark tattered shroud, hollow eye sockets, clawed hands; height ~2.18m, feet strictly at z=0",
        "builder": characters.build_ghost,
        "pivot": "Bottom center at feet (y=0 in Godot, z=0 in Blender), facing -Z forward",
        "godot_usage": "Root enemy CharacterBody3D; low-poly horror silhouette with separated arms and legs, tattered shroud strips"
    },
    {
        "file": "player_body.glb",
        "category": "Characters",
        "description": "Survivor character in dark jacket, jeans, and muddy boots; low-poly third-person or mirror reflection model",
        "builder": characters.build_player_body,
        "pivot": "Bottom center at feet (y=0 in Godot), facing -Z forward",
        "godot_usage": "Attach to player CharacterBody3D under a toggleable visual node (visible in reflections or third-person camera)"
    },
    {
        "file": "flashlight.glb",
        "category": "Equipment",
        "description": "Tactical heavy-duty handheld flashlight with ribbed grip, tactical bezel, and glowing lens",
        "builder": items.build_flashlight,
        "pivot": "Center of grip handle (0, 0, 0), beam pointing along -Z forward in Godot",
        "godot_usage": "Child of Camera3D with transform translation (0.22, -0.25, -0.42). Attach SpotLight3D at lens position (0, 0, -0.13) pointing along -Z"
    },
    {
        "file": "ritual_book.glb",
        "category": "Ritual Items",
        "description": "Ancient occult grimoire with thick dark leather cover, raised spine ribs, brass corners, blood pentagram rune, and parchment pages",
        "builder": items.build_ritual_book,
        "pivot": "Bottom center of book (0, 0, 0)",
        "godot_usage": "Place on altar.glb lectern (Node3D transform approx translation (0, 1.05, 0.02) with rotation_degrees (-25, 0, 0)) or player inventory inspection"
    },
    {
        "file": "altar.glb",
        "category": "Sacrificial Props",
        "description": "Heavy sacrificial granite stone altar table with 4 carved pillars, perimeter blood groove, ritual circle, slanted book lectern, and 4 corner candle sconces",
        "builder": props.build_altar,
        "pivot": "Bottom center on floor (0, 0, 0)",
        "godot_usage": "StaticBody3D sacrificial objective centerpiece. Add BoxShape3D collision (2.24m x 1.11m x 1.24m). Snap 4 candle.glb instances to corner sconces at (+-0.95, 0.98, +-0.48)"
    },
    {
        "file": "candle.glb",
        "category": "Lighting Props",
        "description": "Antique brass candlestick holder with saucer rim (diameter <= 0.12m), melting ivory wax candle, and glowing flame (height <= 0.30m)",
        "builder": items.build_candle,
        "pivot": "Bottom center of saucer base (0, 0, 0)",
        "godot_usage": "Attach OmniLight3D at flame position (0, 0.22, 0) with warm light color (#ffaa33, energy 1.2, range 4m) for dynamic flickering ambient light"
    },
    {
        "file": "door.glb",
        "category": "Interactable Props",
        "description": "Heavy wooden plank horror door with iron cross-braces, hinges, handle, and keyhole plate",
        "builder": props.build_door,
        "pivot": "Left edge along hinge line (0, 0, 0)",
        "godot_usage": "AnimatableBody3D or Node3D door pivot. Rotate node around Y axis: rotation_degrees.y = 0.0 (closed) to 90.0 (open). Collision box (1.1m x 2.2m x 0.08m) offset at (0.55, 1.1, 0)"
    },
    {
        "file": "key.glb",
        "category": "Interactive Items",
        "description": "Antique ornate brass skeleton key with gothic cutout bow, turned collar rings, and notched bit teeth",
        "builder": items.build_key,
        "pivot": "Center of key bow (0, 0, 0)",
        "godot_usage": "Area3D pickup item. Add gentle floating Y bobbing and continuous Y-rotation animation for visual interactable hint"
    },
    {
        "file": "crate.glb",
        "category": "Environment Props",
        "description": "Heavy wooden shipping crate (0.9m x 0.9m x 0.9m) with plank panels, corner posts, diagonal braces, and iron corner brackets",
        "builder": props.build_crate,
        "pivot": "Bottom center on floor (0, 0, 0)",
        "godot_usage": "RigidBody3D or StaticBody3D obstacle. Add BoxShape3D collision of size (0.9, 0.9, 0.9) centered at (0, 0.45, 0)"
    },
    {
        "file": "barrel.glb",
        "category": "Environment Props",
        "description": "Oak storage barrel with bulging staves, 4 black iron hoops, recessed wooden lid, and bunghole plug",
        "builder": props.build_barrel,
        "pivot": "Bottom center on floor (0, 0, 0)",
        "godot_usage": "StaticBody3D or RigidBody3D obstacle. Add CylinderShape3D collision (radius 0.36m, height 1.05m) centered at (0, 0.525, 0)"
    },
    {
        "file": "wall_module.glb",
        "category": "Modular Architecture",
        "description": "4m wide x 3m high x 0.25m thick modular corridor/room wall with baseboard molding, wainscoting chair rail, crown molding, and junction pilasters",
        "builder": environment.build_wall_module,
        "pivot": "Bottom center of front face (0, 0, 0)",
        "godot_usage": "Modular kit piece for grid snapping (step 4.0m). Add StaticBody3D with BoxShape3D (4.0, 3.0, 0.25) centered at (0, 1.5, -0.125)"
    },
    {
        "file": "floor_module.glb",
        "category": "Modular Architecture",
        "description": "4m x 4m modular floor tile slab (thickness 0.15m) with individual parallel wooden floorboards and boundary trim",
        "builder": environment.build_floor_module,
        "pivot": "Top center of floor slab (0, 0, 0) at walking surface",
        "godot_usage": "Modular kit piece for grid snapping (step 4.0m). Add StaticBody3D with BoxShape3D (4.0, 0.15, 4.0) centered at (0, -0.075, 0)"
    },
    {
        "file": "ceiling_module.glb",
        "category": "Modular Architecture",
        "description": "4m x 4m modular ceiling tile slab (thickness 0.20m) with aged plaster surface and 3 heavy structural timber rafters with iron straps",
        "builder": environment.build_ceiling_module,
        "pivot": "Bottom center of ceiling plaster face (0, 0, 0)",
        "godot_usage": "Modular kit piece for grid snapping (step 4.0m, place at Y=3.0m). Add StaticBody3D with BoxShape3D (4.0, 0.20, 4.0) centered at (0, 0.10, 0)"
    },
    {
        "file": "painting.glb",
        "category": "Decorations",
        "description": "Creepy haunted Victorian gothic portrait painting in ornate dark wooden/gilt frame with canvas silhouette of a ghostly lady with pale glowing eyes",
        "builder": props.build_painting,
        "pivot": "Center of back face (0, 0, 0) for flush mounting to wall",
        "godot_usage": "Decorative wall asset. Place against wall surface (Z=0 flush). Optional: animate ghostly figure visibility or eye emission in horror jump-scares"
    },
    {
        "file": "rug.glb",
        "category": "Decorations",
        "description": "Ornate Victorian deep crimson floor rug (~2.6m x 1.8m) with gold patterned border, central medallion, and fringed tasselled edges",
        "builder": props.build_rug,
        "pivot": "Bottom center on floor (0, 0, 0)",
        "godot_usage": "Decorative floor asset. Place on floor at Y=0.005 (just above floor_module surface to avoid Z-fighting)"
    },
    # --- Farmhouse & Gameplay Props (16-21) ---
    {
        "file": "rat.glb",
        "category": "Farmhouse Ritual",
        "description": "Low-poly sacrificial rat for Farmhouse ritual; oblong rounded body, pink snout/ears/paws, long thin tail (~0.28m long, ~0.10m high)",
        "builder": characters.build_rat,
        "pivot": "Bottom center at ground under belly (feet at z=0.000 in Blender / y=0 in Godot), facing -Z forward",
        "godot_usage": "Sacrificial objective creature CharacterBody3D or RigidBody3D. AI navigation via NavigationAgent3D. Bait with food.glb to capture"
    },
    {
        "file": "trash_can.glb",
        "category": "Farmhouse Props",
        "description": "Galvanized metal trash can with reinforcing ribs, drop handles, rust weathering, and slightly ajar lid revealing interior (~0.60m high, 0.45m diam)",
        "builder": props.build_trash_can,
        "pivot": "Bottom center on floor (0, 0, 0)",
        "godot_usage": "StaticBody3D or interactive hiding spot. Collision cylinder (radius 0.225m, height 0.60m). Rats spawn or hide inside trash cans"
    },
    {
        "file": "fuse.glb",
        "category": "Farmhouse Items",
        "description": "Industrial ceramic electrical fuse (~0.12m) with white ceramic barrel, dual metal terminal ferrule caps, and indicator band",
        "builder": items.build_fuse,
        "pivot": "Bottom center on floor (0, 0, 0)",
        "godot_usage": "Area3D pickup item. Needed to restore power in circuit breaker panels across Farmhouse map"
    },
    {
        "file": "battery.glb",
        "category": "Farmhouse Items",
        "description": "Heavy-duty 9V rectangular battery (~0.09m high) with dark casing, golden stripe, and top snap/socket terminals",
        "builder": items.build_battery,
        "pivot": "Bottom center on floor (0, 0, 0)",
        "godot_usage": "Area3D pickup item. Consumable battery recharge for player flashlight.glb"
    },
    {
        "file": "first_aid.glb",
        "category": "Farmhouse Items",
        "description": "Medical first aid kit box (~0.25m x 0.18m x 0.10m) with white casing, top handle, front latches, and geometric 3D red cross on lid",
        "builder": items.build_first_aid,
        "pivot": "Bottom center on floor (0, 0, 0)",
        "godot_usage": "Area3D pickup item. Used by survivors to revive knocked-down teammates"
    },
    {
        "file": "food.glb",
        "category": "Farmhouse Items",
        "description": "Tin can ration (~0.10m high) with tinplate metal rims, paper label band, and top pull-tab lid (rat bait)",
        "builder": items.build_food,
        "pivot": "Bottom center on floor (0, 0, 0)",
        "godot_usage": "Area3D pickup / throw item. Placed or thrown on the floor to lure and trap rats for the ritual sacrifice"
    }
]

def verify_import(glb_path):
    """Verifies that a GLB file can be cleanly re-imported by Blender."""
    common.clean_scene()
    bpy.ops.import_scene.gltf(filepath=glb_path)
    imported_objects = list(bpy.context.scene.objects)
    return len(imported_objects) > 0, [o.name for o in imported_objects]

def main():
    os.makedirs(OUTPUT_MODELS_DIR, exist_ok=True)
    os.makedirs(OUTPUT_PREVIEWS_DIR, exist_ok=True)
    
    print("=" * 105)
    print("STARTING DEVOUR-CLONE 3D ASSET BUILD & WORKBENCH PREVIEWS (Headless Blender)")
    print(f"Models directory  : {OUTPUT_MODELS_DIR}")
    print(f"Previews directory: {OUTPUT_PREVIEWS_DIR}")
    print("=" * 105)
    
    start_time = time.time()
    results = []
    
    for asset in ASSET_DEFINITIONS:
        filename = asset["file"]
        model_name = os.path.splitext(filename)[0]
        out_path = os.path.join(OUTPUT_MODELS_DIR, filename)
        preview_path = os.path.join(OUTPUT_PREVIEWS_DIR, f"{model_name}_front.png")
        
        print(f"\n--> Building {filename}...")
        t0 = time.time()
        
        # 1. Build & Export GLB
        stats = asset["builder"](out_path)
        file_size_kb = os.path.getsize(out_path) / 1024.0
        
        # Verify triangle count constraint (< 3000)
        assert stats["tris"] < 3000, f"Asset {filename} exceeded triangle limit: {stats['tris']} tris"
        assert file_size_kb > 0, f"Asset {filename} produced empty file"
        
        # 2. Re-import GLB, compute exact world bounds & render Workbench preview
        is_ghost = (filename == "ghost.glb")
        bounds = common.render_preview_and_get_bounds(out_path, preview_path, light_background=is_ghost)
        assert os.path.exists(preview_path), f"Failed to generate preview for {filename}"
        
        # Additional three-quarter preview for ghost.glb
        if is_ghost:
            preview_34_path = os.path.join(OUTPUT_PREVIEWS_DIR, "ghost_three_quarter.png")
            common.render_preview_and_get_bounds(out_path, preview_34_path, camera_angle_deg=35.0, light_background=True)
            assert os.path.exists(preview_34_path), "Failed to generate ghost_three_quarter.png"
        
        dt = time.time() - t0
        
        results.append({
            "file": filename,
            "category": asset["category"],
            "description": asset["description"],
            "pivot": asset["pivot"],
            "godot_usage": asset["godot_usage"],
            "tris": stats["tris"],
            "verts": stats["verts"],
            "size_kb": round(file_size_kb, 1),
            "width": bounds["width"],
            "depth": bounds["depth"],
            "height": bounds["height"],
            "min_z": bounds["min_z"],
            "preview": preview_path,
            "build_time_s": round(dt, 2)
        })
        
        print(f"    [OK] {filename:<16} | Tris: {stats['tris']:<5} | Size: {file_size_kb:>5.1f} KB | "
              f"Bounds: {bounds['width']:.2f}x{bounds['depth']:.2f}x{bounds['height']:.2f}m | "
              f"MinZ: {bounds['min_z']:>6.3f}m | {dt:.2f}s")
        
    print("\n" + "=" * 105)
    print("VERIFICATION: Testing GLB re-import on key assets...")
    for test_target in ["ghost.glb", "candle.glb", "rat.glb", "trash_can.glb", "altar.glb"]:
        test_path = os.path.join(OUTPUT_MODELS_DIR, test_target)
        ok, objs = verify_import(test_path)
        print(f"  Re-import {test_target:<16}: {'PASS' if ok else 'FAIL'} (Nodes: {len(objs)})")
        assert ok, f"Re-import of {test_target} failed!"
        
    total_time = time.time() - start_time
    print("=" * 105)
    print(f"ALL {len(results)} ASSETS BUILT & PREVIEWS GENERATED SUCCESSFULLY in {total_time:.2f}s!")
    print("=" * 105)
    
    # Print Markdown bounds table for inspection and copy into ASSETS.md
    print("\n--- BOUNDS & SPECIFICATIONS TABLE ---")
    print(f"{'File':<18} | {'Tris':<5} | {'Size KB':<7} | {'Width (m)':<9} | {'Depth (m)':<9} | {'Height (m)':<10} | {'Min Z (m)':<9} | {'Category'}")
    print("-" * 105)
    for r in results:
        print(f"{r['file']:<18} | {r['tris']:<5} | {r['size_kb']:<7} | {r['width']:<9.3f} | {r['depth']:<9.3f} | {r['height']:<10.3f} | {r['min_z']:<9.3f} | {r['category']}")
        
    return results

if __name__ == "__main__":
    main()
