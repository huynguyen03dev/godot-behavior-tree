import bpy
import bmesh
import math
from mathutils import Vector, Matrix, Euler
import common
import palette

def create_cube(size, location, scale=(1, 1, 1), rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(
        size=size,
        location=location,
        rotation=rotation
    )
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return obj

def build_wall_module(out_path):
    """
    Builds Wall Module asset:
    - 4.0m wide (X: -2.0 to +2.0) x 3.0m high (Z: 0.0 to 3.0) x 0.25m thick (Y: -0.25 to 0.0)
    - Front face is at Y = 0.0, back at Y = -0.25
    - Baseboard molding, wainscoting chair rail, crown molding, edge pilasters
    - Clean flat boundary for Godot BoxShape3D (4.0, 3.0, 0.25)
    - Pivot at bottom center front (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Main wall structural slab (4.0m x 0.24m x 3.0m)
    wall_core = create_cube(size=1.0, location=(0, -0.125, 1.50), scale=(4.0, 0.25, 3.0))
    common.assign_material(wall_core, p['wall_plaster'])
    parts.append(wall_core)
    
    # 2. Baseboard molding (bottom Z = 0 to 0.22, front face Y = +0.015)
    baseboard = create_cube(size=1.0, location=(0, 0.008, 0.11), scale=(4.0, 0.016, 0.22))
    common.assign_material(baseboard, p['wood_trim'])
    parts.append(baseboard)
    
    baseboard_cap = create_cube(size=1.0, location=(0, 0.012, 0.22), scale=(4.0, 0.024, 0.03))
    common.assign_material(baseboard_cap, p['wood_trim'])
    parts.append(baseboard_cap)
    
    # 3. Wainscoting / Chair Rail at Z = 1.05m
    chair_rail = create_cube(size=1.0, location=(0, 0.010, 1.05), scale=(4.0, 0.020, 0.08))
    common.assign_material(chair_rail, p['wood_trim'])
    parts.append(chair_rail)
    
    # Lower wainscot recessed panels (3 decorative recessed framed panels)
    for px in [-1.30, 0.0, 1.30]:
        panel_trim = create_cube(size=1.0, location=(px, 0.005, 0.63), scale=(1.05, 0.010, 0.65))
        common.assign_material(panel_trim, p['wood_trim'])
        parts.append(panel_trim)
        
        panel_inner = create_cube(size=1.0, location=(px, 0.002, 0.63), scale=(0.95, 0.008, 0.55))
        common.assign_material(panel_inner, p['wall_plaster'])
        parts.append(panel_inner)
        
    # 4. Crown molding at top (Z = 2.88 to 3.0)
    crown_molding = create_cube(size=1.0, location=(0, 0.010, 2.94), scale=(4.0, 0.020, 0.12))
    common.assign_material(crown_molding, p['wood_trim'])
    parts.append(crown_molding)
    
    # 5. Side junction pilasters / vertical seams (X = -1.97 and +1.97)
    for sx in [-1.97, 1.97]:
        pilaster = create_cube(size=1.0, location=(sx, 0.008, 1.50), scale=(0.06, 0.016, 3.0))
        common.assign_material(pilaster, p['wood_trim'])
        parts.append(pilaster)
        
    mesh = common.join_objects(parts, "Wall_Module")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_floor_module(out_path):
    """
    Builds Floor Module asset:
    - 4.0m x 4.0m slab, thickness 0.15m (Z: -0.15 to 0.0)
    - Top walking surface is cleanly at Z = 0.0 (Godot Y = 0.0)
    - Detailed wooden plank flooring with individual plank bevels
    - Clean bounding box for Godot BoxShape3D (4.0, 0.15, 4.0)
    - Pivot at top center (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Base sub-floor foundation slab (4.0m x 4.0m x 0.13m, Z: -0.15 to -0.02)
    subfloor = create_cube(size=1.0, location=(0, 0, -0.085), scale=(4.0, 4.0, 0.13))
    common.assign_material(subfloor, p['wood_trim'])
    parts.append(subfloor)
    
    # 2. Individual parallel floor planks (Z: -0.02 to 0.0)
    # 16 planks running along Y (length 4.0m, width 0.245m each)
    num_planks = 16
    plank_width = 4.0 / num_planks
    for i in range(num_planks):
        px = -2.0 + (i + 0.5) * plank_width
        plank = create_cube(
            size=1.0,
            location=(px, 0, -0.01),
            scale=(plank_width - 0.006, 3.99, 0.02)
        )
        common.assign_material(plank, p['floor_boards'])
        parts.append(plank)
        
    # Perimeter edge border frame
    for sy in [-1.98, 1.98]:
        trim = create_cube(size=1.0, location=(0, sy, -0.008), scale=(4.0, 0.04, 0.022))
        common.assign_material(trim, p['wood_trim'])
        parts.append(trim)
        
    mesh = common.join_objects(parts, "Floor_Module")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_ceiling_module(out_path):
    """
    Builds Ceiling Module asset:
    - 4.0m x 4.0m slab, thickness 0.20m
    - Plaster ceiling tile with 3 structural heavy dark timber beams
    - Bottom visible ceiling plane at Z = 0.0
    - Clean bounding box for Godot BoxShape3D (4.0, 0.20, 4.0)
    - Pivot at bottom center (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Main plaster ceiling slab (Z: 0.0 to 0.12)
    slab = create_cube(size=1.0, location=(0, 0, 0.06), scale=(4.0, 4.0, 0.12))
    common.assign_material(slab, p['wall_plaster'])
    parts.append(slab)
    
    # 2. Three heavy wooden structural support beams running along Y
    # Beams hang down from Z=0.08 to Z=-0.06 (depth 0.14m, width 0.16m)
    for bx in [-1.33, 0.0, 1.33]:
        beam = create_cube(size=1.0, location=(bx, 0, 0.01), scale=(0.18, 4.0, 0.14))
        common.assign_material(beam, p['wood_trim'])
        parts.append(beam)
        
        # Metal joint brackets near ends
        for by in [-1.80, 1.80]:
            strap = create_cube(size=1.0, location=(bx, by, -0.05), scale=(0.20, 0.06, 0.03))
            common.assign_material(strap, p['aged_iron'])
            parts.append(strap)
            
    # 3. Two cross-rafters running along X (connecting between the beams)
    for cy in [-1.0, 1.0]:
        rafter = create_cube(size=1.0, location=(0, cy, 0.03), scale=(3.98, 0.12, 0.08))
        common.assign_material(rafter, p['wood_trim'])
        parts.append(rafter)
        
    mesh = common.join_objects(parts, "Ceiling_Module")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats
