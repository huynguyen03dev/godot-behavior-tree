import bpy
import bmesh
import math
from mathutils import Vector, Matrix, Euler
import common
import palette

def create_cylinder(radius, depth, vertices, location, rotation=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation
    )
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return obj

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

def create_torus(major_radius, minor_radius, major_segments, minor_segments, location, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=location,
        rotation=rotation
    )
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(rotation=True)
    return obj

def build_altar(out_path):
    """
    Builds Altar asset:
    - Heavy stone sacrificial table (~2.2m x 1.2m x 0.95m)
    - Slanted center book lectern, 4 corner candle sconces, blood grooves
    - Pivot at bottom center (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Four carved stone pillar legs with plinth bases and capitals
    leg_x = 0.90
    leg_y = 0.45
    for sx in [-leg_x, leg_x]:
        for sy in [-leg_y, leg_y]:
            # Plinth base
            plinth = create_cube(size=1.0, location=(sx, sy, 0.05), scale=(0.28, 0.28, 0.10))
            common.assign_material(plinth, p['stone_altar'])
            parts.append(plinth)
            
            # Pillar column
            col = create_cylinder(radius=0.10, depth=0.62, vertices=10, location=(sx, sy, 0.41))
            common.assign_material(col, p['stone_altar'])
            parts.append(col)
            
            # Capital top
            cap = create_cube(size=1.0, location=(sx, sy, 0.77), scale=(0.26, 0.26, 0.10))
            common.assign_material(cap, p['stone_altar'])
            parts.append(cap)
            
    # Lower stretcher / shelf connecting legs
    stretcher = create_cube(size=1.0, location=(0, 0, 0.16), scale=(1.80, 0.90, 0.08))
    common.assign_material(stretcher, p['stone_altar'])
    parts.append(stretcher)
    
    # 2. Main Altar Stone Top Slab (Z = 0.82 to 0.96)
    sub_slab = create_cube(size=1.0, location=(0, 0, 0.84), scale=(2.16, 1.16, 0.06))
    common.assign_material(sub_slab, p['stone_altar'])
    parts.append(sub_slab)
    
    top_slab = create_cube(size=1.0, location=(0, 0, 0.91), scale=(2.24, 1.24, 0.08))
    common.assign_material(top_slab, p['stone_altar'])
    parts.append(top_slab)
    
    # Sacrificial perimeter blood channel groove
    groove_x1 = create_cube(size=1.0, location=(0, 0.50, 0.952), scale=(1.90, 0.03, 0.005))
    common.assign_material(groove_x1, p['blood_rune'])
    parts.append(groove_x1)
    
    groove_x2 = create_cube(size=1.0, location=(0, -0.50, 0.952), scale=(1.90, 0.03, 0.005))
    common.assign_material(groove_x2, p['blood_rune'])
    parts.append(groove_x2)
    
    groove_y1 = create_cube(size=1.0, location=(0.95, 0, 0.952), scale=(0.03, 1.00, 0.005))
    common.assign_material(groove_y1, p['blood_rune'])
    parts.append(groove_y1)
    
    groove_y2 = create_cube(size=1.0, location=(-0.95, 0, 0.952), scale=(0.03, 1.00, 0.005))
    common.assign_material(groove_y2, p['blood_rune'])
    parts.append(groove_y2)
    
    # Ritual center circle
    circle = create_torus(major_radius=0.28, minor_radius=0.008, major_segments=16, minor_segments=5, location=(0, 0, 0.952))
    common.assign_material(circle, p['blood_rune'])
    parts.append(circle)
    
    # 3. Slanted Stone/Iron Book Lectern Stand in center
    lectern_base = create_cube(size=1.0, location=(0, 0, 0.965), scale=(0.32, 0.22, 0.03))
    common.assign_material(lectern_base, p['aged_iron'])
    parts.append(lectern_base)
    
    # Angled rest plate (tilted ~25 deg towards -Y so reader facing +Y can read)
    lectern_rest = create_cube(
        size=1.0, location=(0, 0.02, 1.03), scale=(0.40, 0.32, 0.025),
        rotation=(math.radians(-25), 0, 0)
    )
    common.assign_material(lectern_rest, p['aged_iron'])
    parts.append(lectern_rest)
    
    # Bottom lip to hold book
    lectern_lip = create_cube(
        size=1.0, location=(0, -0.11, 0.99), scale=(0.40, 0.03, 0.03),
        rotation=(math.radians(-25), 0, 0)
    )
    common.assign_material(lectern_lip, p['aged_iron'])
    parts.append(lectern_lip)
    
    # 4. Four brass candle sconces at the corners
    for sx in [-0.95, 0.95]:
        for sy in [-0.48, 0.48]:
            sconce_base = create_cylinder(radius=0.045, depth=0.015, vertices=10, location=(sx, sy, 0.96))
            common.assign_material(sconce_base, p['brass_antique'])
            parts.append(sconce_base)
            
            sconce_cup = create_cylinder(radius=0.03, depth=0.035, vertices=10, location=(sx, sy, 0.98))
            common.assign_material(sconce_cup, p['brass_antique'])
            parts.append(sconce_cup)
            
    mesh = common.join_objects(parts, "Altar")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_door(out_path):
    """
    Builds Door asset:
    - Wooden plank horror mansion door (1.1m x 2.2m x 0.08m)
    - Heavy iron strap braces, handle, keyhole, and hinges
    - PIVOT: placed at the left hinge edge at (0, 0, 0) for natural door swing in Godot!
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # Door spans: X: 0 to 1.10m, Y: -0.04 to +0.04m, Z: 0 to 2.20m
    
    # 1. Vertical wooden planks (5 vertical planks side-by-side)
    plank_count = 5
    plank_w = 1.08 / plank_count
    for i in range(plank_count):
        px = 0.01 + (i + 0.5) * plank_w
        plank = create_cube(size=1.0, location=(px, 0, 1.10), scale=(plank_w - 0.006, 0.065, 2.18))
        common.assign_material(plank, p['wood_plank'])
        parts.append(plank)
        
    # Outer frame border planks
    frame_left = create_cube(size=1.0, location=(0.04, 0, 1.10), scale=(0.08, 0.075, 2.20))
    common.assign_material(frame_left, p['wood_plank'])
    parts.append(frame_left)
    
    frame_right = create_cube(size=1.0, location=(1.06, 0, 1.10), scale=(0.08, 0.075, 2.20))
    common.assign_material(frame_right, p['wood_plank'])
    parts.append(frame_right)
    
    # 2. Horizontal iron strap braces (across front Y = +0.038)
    for bz in [0.45, 1.75]:
        brace = create_cube(size=1.0, location=(0.55, 0.04, bz), scale=(1.04, 0.012, 0.09))
        common.assign_material(brace, p['aged_iron'])
        parts.append(brace)
        
        # Rivets along brace
        for rx in [0.10, 0.35, 0.60, 0.85, 1.0]:
            rivet = create_cylinder(radius=0.012, depth=0.008, vertices=8, location=(rx, 0.046, bz), rotation=(math.radians(90), 0, 0))
            common.assign_material(rivet, p['aged_iron'])
            parts.append(rivet)
            
    # Diagonal wooden cross brace between the iron straps
    cross_brace = create_cube(
        size=1.0, location=(0.55, 0.038, 1.10), scale=(1.35, 0.012, 0.08),
        rotation=(0, math.radians(50), 0)
    )
    common.assign_material(cross_brace, p['wood_plank'])
    parts.append(cross_brace)
    
    # 3. Heavy Iron Hinges on left edge (X = 0, Z = 0.45 and Z = 1.75)
    for hz in [0.45, 1.75]:
        hinge_knuckle = create_cylinder(radius=0.018, depth=0.12, vertices=10, location=(0, 0, hz))
        common.assign_material(hinge_knuckle, p['aged_iron'])
        parts.append(hinge_knuckle)
        
        hinge_strap = create_cube(size=1.0, location=(0.08, -0.04, hz), scale=(0.16, 0.012, 0.07))
        common.assign_material(hinge_strap, p['aged_iron'])
        parts.append(hinge_strap)
        
    # 4. Heavy iron door handle and keyhole plate on right side (X = 0.96, Z = 1.05)
    plate = create_cube(size=1.0, location=(0.96, 0.042, 1.05), scale=(0.07, 0.008, 0.24))
    common.assign_material(plate, p['aged_iron'])
    parts.append(plate)
    
    # Handle boss & lever handle
    boss = create_cylinder(radius=0.016, depth=0.025, vertices=8, location=(0.96, 0.054, 1.12), rotation=(math.radians(90), 0, 0))
    common.assign_material(boss, p['aged_iron'])
    parts.append(boss)
    
    handle_bar = create_cube(size=1.0, location=(0.92, 0.068, 1.12), scale=(0.12, 0.02, 0.025))
    common.assign_material(handle_bar, p['aged_iron'])
    parts.append(handle_bar)
    
    # Keyhole cutout slot
    keyhole = create_cube(size=1.0, location=(0.96, 0.046, 0.99), scale=(0.012, 0.005, 0.03))
    common.assign_material(keyhole, p['aged_iron'])
    parts.append(keyhole)
    
    mesh = common.join_objects(parts, "Door")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_crate(out_path):
    """
    Builds Crate asset:
    - Wooden packing crate (0.9m x 0.9m x 0.9m)
    - Plank recessed panels, corner frame planks, cross braces, iron corner brackets
    - Pivot at bottom center (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Inner core box / plank faces (0.86m x 0.86m x 0.86m)
    core = create_cube(size=1.0, location=(0, 0, 0.45), scale=(0.86, 0.86, 0.86))
    common.assign_material(core, p['wood_plank'])
    parts.append(core)
    
    # 2. Outer frame corner edges
    # 4 Vertical corner posts
    for sx in [-0.41, 0.41]:
        for sy in [-0.41, 0.41]:
            post = create_cube(size=1.0, location=(sx, sy, 0.45), scale=(0.09, 0.09, 0.90))
            common.assign_material(post, p['wood_plank'])
            parts.append(post)
            
    # 4 Bottom horizontal rails
    for sy in [-0.41, 0.41]:
        rail = create_cube(size=1.0, location=(0, sy, 0.045), scale=(0.78, 0.09, 0.09))
        common.assign_material(rail, p['wood_plank'])
        parts.append(rail)
    for sx in [-0.41, 0.41]:
        rail = create_cube(size=1.0, location=(sx, 0, 0.045), scale=(0.09, 0.78, 0.09))
        common.assign_material(rail, p['wood_plank'])
        parts.append(rail)
        
    # 4 Top horizontal rails
    for sy in [-0.41, 0.41]:
        rail = create_cube(size=1.0, location=(0, sy, 0.855), scale=(0.78, 0.09, 0.09))
        common.assign_material(rail, p['wood_plank'])
        parts.append(rail)
    for sx in [-0.41, 0.41]:
        rail = create_cube(size=1.0, location=(sx, 0, 0.855), scale=(0.09, 0.78, 0.09))
        common.assign_material(rail, p['wood_plank'])
        parts.append(rail)
        
    # 3. Diagonal cross braces on 4 side faces
    for sy in [-0.435, 0.435]:
        cross = create_cube(size=1.0, location=(0, sy, 0.45), scale=(1.02, 0.04, 0.08), rotation=(0, math.radians(45), 0))
        common.assign_material(cross, p['wood_plank'])
        parts.append(cross)
    for sx in [-0.435, 0.435]:
        cross = create_cube(size=1.0, location=(sx, 0, 0.45), scale=(0.04, 1.02, 0.08), rotation=(math.radians(45), 0, 0))
        common.assign_material(cross, p['wood_plank'])
        parts.append(cross)
        
    # 4. Metal corner bracket plates (8 corners)
    for sx in [-0.44, 0.44]:
        for sy in [-0.44, 0.44]:
            for sz in [0.06, 0.84]:
                corner_b = create_cube(size=1.0, location=(sx, sy, sz), scale=(0.05, 0.05, 0.05))
                common.assign_material(corner_b, p['aged_iron'])
                parts.append(corner_b)
                
    mesh = common.join_objects(parts, "Crate")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_barrel(out_path):
    """
    Builds Barrel asset:
    - Wooden storage cask with bulging staves and 4 iron hoops
    - Height: ~1.05m, belly diameter: ~0.74m, end diameter: ~0.60m
    - Pivot at bottom center (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Bulging barrel body built from stacked ring cylinders
    # Levels from Z=0 to Z=1.05
    # Bottom section (Z: 0 to 0.28)
    b_bot = create_cylinder(radius=0.31, depth=0.28, vertices=16, location=(0, 0, 0.14), scale=(1.0, 1.0, 1.0))
    common.assign_material(b_bot, p['wood_plank'])
    parts.append(b_bot)
    
    # Lower belly (Z: 0.28 to 0.525)
    b_low = create_cylinder(radius=0.365, depth=0.26, vertices=16, location=(0, 0, 0.40))
    common.assign_material(b_low, p['wood_plank'])
    parts.append(b_low)
    
    # Upper belly (Z: 0.525 to 0.77)
    b_up = create_cylinder(radius=0.365, depth=0.26, vertices=16, location=(0, 0, 0.65))
    common.assign_material(b_up, p['wood_plank'])
    parts.append(b_up)
    
    # Top section (Z: 0.77 to 1.05)
    b_top = create_cylinder(radius=0.31, depth=0.28, vertices=16, location=(0, 0, 0.91))
    common.assign_material(b_top, p['wood_plank'])
    parts.append(b_top)
    
    # Recessed top lid rim & wood lid
    lid_rim = create_torus(major_radius=0.305, minor_radius=0.012, major_segments=16, minor_segments=5, location=(0, 0, 1.04))
    common.assign_material(lid_rim, p['wood_plank'])
    parts.append(lid_rim)
    
    lid_wood = create_cylinder(radius=0.29, depth=0.02, vertices=14, location=(0, 0, 1.02))
    common.assign_material(lid_wood, p['wood_plank'])
    parts.append(lid_wood)
    
    # Bunghole plug on lid
    plug = create_cylinder(radius=0.025, depth=0.015, vertices=8, location=(0.12, 0.05, 1.035))
    common.assign_material(plug, p['aged_iron'])
    parts.append(plug)
    
    # 2. Four Iron Hoops / Bands
    # Chime hoop bottom (Z = 0.08)
    hoop_b1 = create_cylinder(radius=0.32, depth=0.035, vertices=16, location=(0, 0, 0.08))
    common.assign_material(hoop_b1, p['aged_iron'])
    parts.append(hoop_b1)
    
    # Quarter hoop bottom (Z = 0.30)
    hoop_b2 = create_cylinder(radius=0.355, depth=0.035, vertices=16, location=(0, 0, 0.30))
    common.assign_material(hoop_b2, p['aged_iron'])
    parts.append(hoop_b2)
    
    # Quarter hoop top (Z = 0.75)
    hoop_t2 = create_cylinder(radius=0.355, depth=0.035, vertices=16, location=(0, 0, 0.75))
    common.assign_material(hoop_t2, p['aged_iron'])
    parts.append(hoop_t2)
    
    # Chime hoop top (Z = 0.97)
    hoop_t1 = create_cylinder(radius=0.32, depth=0.035, vertices=16, location=(0, 0, 0.97))
    common.assign_material(hoop_t1, p['aged_iron'])
    parts.append(hoop_t1)
    
    mesh = common.join_objects(parts, "Barrel")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_painting(out_path):
    """
    Builds Painting asset:
    - Haunted gothic portrait painting (~0.95m x 1.30m x 0.06m)
    - Dark ornate wooden frame, dark canvas, ghostly silhouette
    - Pivot at center back (0, 0, 0) flush with wall
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # Painting is in XZ plane (width along X, height along Z), front facing +Y
    # Back is at Y = 0 so placing at (X, Y, Z) sits flush on a wall surface!
    
    # 1. Canvas backing board (Y: 0 to 0.02)
    canvas_back = create_cube(size=1.0, location=(0, 0.01, 0), scale=(0.90, 0.02, 1.25))
    common.assign_material(canvas_back, p['wood_plank'])
    parts.append(canvas_back)
    
    # 2. Outer Carved Wooden Frame (Y: 0 to 0.06)
    # Left & right frame rails
    for sx in [-0.44, 0.44]:
        rail = create_cube(size=1.0, location=(sx, 0.03, 0), scale=(0.10, 0.055, 1.30))
        common.assign_material(rail, p['painting_frame'])
        parts.append(rail)
        
    # Top & bottom frame rails
    for sz in [-0.61, 0.61]:
        rail = create_cube(size=1.0, location=(0, 0.03, sz), scale=(0.98, 0.055, 0.10))
        common.assign_material(rail, p['painting_frame'])
        parts.append(rail)
        
    # Inner beveled frame trim (gold/dark border)
    for sx in [-0.375, 0.375]:
        inner_r = create_cube(size=1.0, location=(sx, 0.025, 0), scale=(0.04, 0.035, 1.14))
        common.assign_material(inner_r, p['brass_antique'])
        parts.append(inner_r)
    for sz in [-0.545, 0.545]:
        inner_r = create_cube(size=1.0, location=(0, 0.025, sz), scale=(0.79, 0.035, 0.04))
        common.assign_material(inner_r, p['brass_antique'])
        parts.append(inner_r)
        
    # 3. Canvas Face (Y = 0.022)
    canvas_face = create_cube(size=1.0, location=(0, 0.022, 0), scale=(0.72, 0.005, 1.06))
    common.assign_material(canvas_face, p['painting_canvas'])
    parts.append(canvas_face)
    
    # 4. Ghostly Portrait Silhouette on Canvas (stylized spooky figure)
    # Silhouette torso / shoulders
    fig_torso = create_cube(size=1.0, location=(0, 0.026, -0.25), scale=(0.42, 0.004, 0.40))
    common.assign_material(fig_torso, p['ghostly_figure'])
    parts.append(fig_torso)
    
    # Neck
    fig_neck = create_cylinder(radius=0.06, depth=0.12, vertices=8, location=(0, 0.026, -0.02), rotation=(math.radians(90), 0, 0))
    common.assign_material(fig_neck, p['ghostly_figure'])
    parts.append(fig_neck)
    
    # Head / skull oval
    fig_head = create_cylinder(radius=0.14, depth=0.005, vertices=12, location=(0, 0.026, 0.14), rotation=(math.radians(90), 0, 0), scale=(0.85, 1.0, 1.15))
    common.assign_material(fig_head, p['ghostly_figure'])
    parts.append(fig_head)
    
    # Creepy glowing pale pinprick eyes
    eye1 = create_cylinder(radius=0.015, depth=0.006, vertices=6, location=(-0.04, 0.028, 0.16), rotation=(math.radians(90), 0, 0))
    common.assign_material(eye1, p['ghost_skin'])
    parts.append(eye1)
    
    eye2 = create_cylinder(radius=0.015, depth=0.006, vertices=6, location=(0.04, 0.028, 0.16), rotation=(math.radians(90), 0, 0))
    common.assign_material(eye2, p['ghost_skin'])
    parts.append(eye2)
    
    mesh = common.join_objects(parts, "Painting")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_rug(out_path):
    """
    Builds Rug asset:
    - Victorian crimson ornate floor rug (~2.6m x 1.8m x 0.015m)
    - Center crimson field, gold patterned border, fringed ends
    - Pivot at bottom center (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # Rug lies in XY plane, Z is vertical thickness (Z = 0 to 0.012)
    # 1. Main Crimson Wool Field
    main_rug = create_cube(size=1.0, location=(0, 0, 0.005), scale=(2.40, 1.60, 0.010))
    common.assign_material(main_rug, p['rug_crimson'])
    parts.append(main_rug)
    
    # 2. Ornate Gold Border Trims
    # Outer border band along length (X)
    for sy in [-0.74, 0.74]:
        border = create_cube(size=1.0, location=(0, sy, 0.006), scale=(2.36, 0.10, 0.011))
        common.assign_material(border, p['rug_gold_border'])
        parts.append(border)
        
    # Outer border band along width (Y)
    for sx in [-1.14, 1.14]:
        border = create_cube(size=1.0, location=(sx, 0, 0.006), scale=(0.10, 1.56, 0.011))
        common.assign_material(border, p['rug_gold_border'])
        parts.append(border)
        
    # Center medallion (lozenge / diamond motif)
    center_diamond = create_cube(
        size=1.0, location=(0, 0, 0.0065), scale=(0.35, 0.35, 0.011),
        rotation=(0, 0, math.radians(45))
    )
    common.assign_material(center_diamond, p['rug_gold_border'])
    parts.append(center_diamond)
    
    # 3. Fringed Tasselled Ends (along -X and +X edges)
    for sx, sign in [(-1.24, -1), (1.24, 1)]:
        fringe_strip = create_cube(size=1.0, location=(sx, 0, 0.004), scale=(0.08, 1.62, 0.007))
        common.assign_material(fringe_strip, p['rug_fringe'])
        parts.append(fringe_strip)
        
        # Fringe tassel segments
        for yi in range(8):
            y_pos = -0.70 + yi * 0.20
            tassel = create_cube(size=1.0, location=(sx + sign * 0.035, y_pos, 0.003), scale=(0.04, 0.08, 0.006))
            common.assign_material(tassel, p['rug_fringe'])
            parts.append(tassel)
            
    mesh = common.join_objects(parts, "Rug")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_trash_can(out_path):
    """
    Builds galvanized metal trash can (rat hiding spot):
    - Height: ~0.60m, diameter: ~0.45m (radius 0.225m)
    - Galvanized metal ribbed cylindrical bin
    - Horizontal reinforcing ribs and side drop handles
    - Weathered rust patches on bottom and rim (material contrast, no image textures)
    - Lid slightly ajar (tilted ~14 deg) resting askew on rim
    - Pivot at bottom center on floor (Z = 0.000)
    - Triangle count: < 500 tris
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Base ring / bottom rim (Z = 0.000 to 0.024)
    base_rim = create_cylinder(radius=0.222, depth=0.024, vertices=12, location=(0, 0, 0.012))
    common.assign_material(base_rim, p['galvanized_metal'])
    parts.append(base_rim)
    
    # Bottom plate rust ring
    bot_rust = create_cylinder(radius=0.223, depth=0.010, vertices=12, location=(0, 0, 0.005))
    common.assign_material(bot_rust, p['metal_rust'])
    parts.append(bot_rust)
    
    # 2. Main Corrugated Can Body (Z = 0.020 to 0.560, height 0.540)
    can_body = create_cylinder(radius=0.212, depth=0.540, vertices=12, location=(0, 0, 0.290))
    common.assign_material(can_body, p['galvanized_metal'])
    parts.append(can_body)
    
    # Interior dark opening void (visible under ajar lid)
    can_interior = create_cylinder(radius=0.200, depth=0.080, vertices=10, location=(0, 0, 0.520))
    common.assign_material(can_interior, p['metal_rust'])
    parts.append(can_interior)
    
    # Horizontal Reinforcing Ribs (2 rings)
    for rz in [0.200, 0.380]:
        rib = create_cylinder(radius=0.218, depth=0.018, vertices=12, location=(0, 0, rz))
        common.assign_material(rib, p['galvanized_metal'])
        parts.append(rib)
        
    # Weathered rust patches on lower body and seams
    rust_patch1 = create_cube(size=1.0, location=(0.170, 0.120, 0.080), scale=(0.080, 0.060, 0.070), rotation=(0, 0, math.radians(35)))
    common.assign_material(rust_patch1, p['metal_rust'])
    parts.append(rust_patch1)
    
    rust_patch2 = create_cube(size=1.0, location=(-0.160, 0.130, 0.220), scale=(0.060, 0.070, 0.060), rotation=(0, 0, math.radians(-25)))
    common.assign_material(rust_patch2, p['metal_rust'])
    parts.append(rust_patch2)
    
    # 3. Top Rim Collar (Z = 0.550 to 0.575)
    top_rim = create_cylinder(radius=0.225, depth=0.025, vertices=12, location=(0, 0, 0.562))
    common.assign_material(top_rim, p['galvanized_metal'])
    parts.append(top_rim)
    
    # 4. Side Drop Handles (along +/- X)
    for sign in [1, -1]:
        hx = sign * 0.224
        # Bracket plate
        bracket = create_cube(size=1.0, location=(hx, 0, 0.420), scale=(0.008, 0.050, 0.035))
        common.assign_material(bracket, p['aged_iron'])
        parts.append(bracket)
        
        # Bail handle wire
        handle_bar = create_cube(size=1.0, location=(sign * (0.224 + 0.020), 0, 0.405), scale=(0.010, 0.070, 0.010))
        common.assign_material(handle_bar, p['aged_iron'])
        parts.append(handle_bar)
        
        for hy in [-0.032, 0.032]:
            handle_arm = create_cube(size=1.0, location=(sign * (0.224 + 0.010), hy, 0.412), scale=(0.020, 0.010, 0.010))
            common.assign_material(handle_arm, p['aged_iron'])
            parts.append(handle_arm)
            
    # 5. Slightly Ajar Lid (tilted ~14 degrees, resting askew on rim)
    # Lid center positioned at (0.015, -0.010, 0.595), tilted around X-axis
    lid_tilt_x = math.radians(14)
    lid_tilt_y = math.radians(-4)
    rot_lid = Euler((lid_tilt_x, lid_tilt_y, 0), 'XYZ')
    
    # Lid main plate
    lid_center = Vector((0.015, -0.010, 0.595))
    lid_plate = create_cylinder(radius=0.232, depth=0.018, vertices=12, location=lid_center, rotation=rot_lid)
    common.assign_material(lid_plate, p['galvanized_metal'])
    parts.append(lid_plate)
    
    # Lid stepped center boss
    boss_loc = lid_center + rot_lid.to_matrix() @ Vector((0, 0, 0.012))
    lid_boss = create_cylinder(radius=0.150, depth=0.014, vertices=10, location=boss_loc, rotation=rot_lid)
    common.assign_material(lid_boss, p['galvanized_metal'])
    parts.append(lid_boss)
    
    # Lid center handle loop
    handle_loc = lid_center + rot_lid.to_matrix() @ Vector((0, 0, 0.030))
    lid_handle = create_cube(size=1.0, location=handle_loc, scale=(0.080, 0.018, 0.022), rotation=rot_lid)
    common.assign_material(lid_handle, p['aged_iron'])
    parts.append(lid_handle)
    
    # Lid rust streak
    rust_loc = lid_center + rot_lid.to_matrix() @ Vector((-0.08, 0.06, 0.010))
    lid_rust = create_cube(size=1.0, location=rust_loc, scale=(0.070, 0.050, 0.010), rotation=rot_lid)
    common.assign_material(lid_rust, p['metal_rust'])
    parts.append(lid_rust)
    
    mesh = common.join_objects(parts, "Trash_Can")
    mesh.data.validate(verbose=False)
    
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats
