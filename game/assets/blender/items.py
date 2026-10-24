import bpy
import bmesh
import math
from mathutils import Vector, Matrix, Euler
import common
import palette

def create_icosphere(radius, subdivisions, location, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions,
        radius=radius,
        location=location
    )
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    return obj

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

def build_flashlight(out_path):
    """
    Builds Flashlight asset:
    - Tactical handheld flashlight pointing along +Y in Blender (Godot -Z forward)
    - Pivot at grip handle (0, 0, 0) for natural attachment to FPS Camera3D
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Main grip handle (cylinder along Y axis from Y=-0.10 to Y=+0.04)
    # Rotation (90 deg around X so cylinder axis aligns with Y)
    rot_y = (math.radians(90), 0, 0)
    handle = create_cylinder(radius=0.018, depth=0.14, vertices=12, location=(0, -0.03, 0), rotation=rot_y)
    common.assign_material(handle, p['tactical_metal'])
    parts.append(handle)
    
    # Ribbed grip rings
    for y_offset in [-0.07, -0.05, -0.03, -0.01, 0.01]:
        ring = create_cylinder(radius=0.0195, depth=0.008, vertices=12, location=(0, y_offset, 0), rotation=rot_y)
        common.assign_material(ring, p['tactical_metal'])
        parts.append(ring)
        
    # Power switch button on top (+Z)
    switch_base = create_cube(size=1.0, location=(0, -0.01, 0.02), scale=(0.012, 0.02, 0.005))
    common.assign_material(switch_base, p['tactical_metal'])
    parts.append(switch_base)
    
    switch_btn = create_cylinder(radius=0.005, depth=0.006, vertices=8, location=(0, -0.01, 0.024))
    common.assign_material(switch_btn, p['aged_iron'])
    parts.append(switch_btn)
    
    # Tail cap at back (Y = -0.11)
    tail_cap = create_cylinder(radius=0.020, depth=0.02, vertices=12, location=(0, -0.11, 0), rotation=rot_y)
    common.assign_material(tail_cap, p['tactical_metal'])
    parts.append(tail_cap)
    
    # Lanyard loop
    lanyard = create_torus(major_radius=0.008, minor_radius=0.0025, major_segments=8, minor_segments=6, location=(0, -0.125, 0), rotation=(0, math.radians(90), 0))
    common.assign_material(lanyard, p['aged_iron'])
    parts.append(lanyard)
    
    # 2. Beveled head housing (Y = 0.04 to 0.11)
    neck = create_cylinder(radius=0.023, depth=0.03, vertices=12, location=(0, 0.055, 0), rotation=rot_y)
    common.assign_material(neck, p['tactical_metal'])
    parts.append(neck)
    
    head_cone = create_cylinder(radius=0.032, depth=0.05, vertices=14, location=(0, 0.09, 0), rotation=rot_y)
    common.assign_material(head_cone, p['tactical_metal'])
    parts.append(head_cone)
    
    # Front bezel ring (heavy tactical crown)
    bezel = create_cylinder(radius=0.034, depth=0.015, vertices=14, location=(0, 0.12, 0), rotation=rot_y)
    common.assign_material(bezel, p['aged_iron'])
    parts.append(bezel)
    
    # Emissive front lens (slightly recessed at Y = 0.122)
    lens = create_cylinder(radius=0.030, depth=0.005, vertices=14, location=(0, 0.122, 0), rotation=rot_y)
    common.assign_material(lens, p['flashlight_lens'])
    parts.append(lens)
    
    mesh = common.join_objects(parts, "Flashlight")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_ritual_book(out_path):
    """
    Builds Ritual Book (Grimoire) asset:
    - Thick leather bound tome with brass corners, occult rune, aged parchment pages
    - Pivot at bottom center (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # Book dimensions: X=0.26 (width), Y=0.36 (length), Z=0.08 (thickness)
    # Spine on left (-X side)
    
    # 1. Parchment paper block (inside)
    paper = create_cube(size=1.0, location=(0.01, 0, 0.04), scale=(0.24, 0.33, 0.065))
    common.assign_material(paper, p['parchment'])
    parts.append(paper)
    
    # 2. Leather covers (bottom and top)
    bottom_cover = create_cube(size=1.0, location=(0, 0, 0.004), scale=(0.26, 0.35, 0.008))
    common.assign_material(bottom_cover, p['leather_dark'])
    parts.append(bottom_cover)
    
    top_cover = create_cube(size=1.0, location=(0, 0, 0.076), scale=(0.26, 0.35, 0.008))
    common.assign_material(top_cover, p['leather_dark'])
    parts.append(top_cover)
    
    # Leather spine (curved cylinder at -X = -0.13)
    spine = create_cylinder(radius=0.042, depth=0.35, vertices=10, location=(-0.13, 0, 0.04), rotation=(math.radians(90), 0, 0), scale=(0.5, 1.0, 1.0))
    common.assign_material(spine, p['leather_dark'])
    parts.append(spine)
    
    # 3 Spine decorative raised leather bands
    for y_pos in [-0.10, 0.0, 0.10]:
        band = create_cylinder(radius=0.045, depth=0.015, vertices=10, location=(-0.132, y_pos, 0.04), rotation=(math.radians(90), 0, 0), scale=(0.5, 1.0, 1.0))
        common.assign_material(band, p['leather_dark'])
        parts.append(band)
        
    # 3. Brass corner protectors (4 corners on top cover)
    for cx in [0.11]:
        for cy in [-0.155, 0.155]:
            corner = create_cube(size=1.0, location=(cx, cy, 0.081), scale=(0.04, 0.04, 0.005))
            common.assign_material(corner, p['brass_antique'])
            parts.append(corner)
            
    # Brass latch clasp on front opening edge (+X)
    clasp_base = create_cube(size=1.0, location=(0.13, 0, 0.04), scale=(0.015, 0.05, 0.04))
    common.assign_material(clasp_base, p['brass_antique'])
    parts.append(clasp_base)
    
    # 4. Occult Blood Rune / Pentagram on top cover (Z = 0.081)
    # Circle
    rune_circle = create_torus(major_radius=0.065, minor_radius=0.004, major_segments=12, minor_segments=5, location=(0, 0, 0.082))
    common.assign_material(rune_circle, p['blood_rune'])
    parts.append(rune_circle)
    
    # Inscribed 5-point star rune segments
    for i in range(5):
        angle = i * (2 * math.pi / 5) - math.pi / 2
        next_angle = (i + 2) * (2 * math.pi / 5) - math.pi / 2
        p1 = Vector((math.cos(angle) * 0.06, math.sin(angle) * 0.06, 0.082))
        p2 = Vector((math.cos(next_angle) * 0.06, math.sin(next_angle) * 0.06, 0.082))
        mid = (p1 + p2) * 0.5
        diff = p2 - p1
        dist = diff.length
        rot_z = math.atan2(diff.y, diff.x)
        star_bar = create_cube(size=1.0, location=(mid.x, mid.y, mid.z), scale=(dist, 0.006, 0.003), rotation=(0, 0, rot_z))
        common.assign_material(star_bar, p['blood_rune'])
        parts.append(star_bar)
        
    mesh = common.join_objects(parts, "Ritual_Book")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_candle(out_path):
    """
    Builds Candle asset:
    - Base saucer diameter <= 0.12m (actual: 0.10m)
    - Total height <= 0.30m (actual: ~0.282m)
    - Contiguous unified silhouette (removed detached ring handle)
    - Melted dripping wax and glowing stylized flame
    - Pivot at bottom center (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Antique Brass Candlestick Holder (Z = 0.00 to 0.08, base diameter 0.10m)
    # Saucer base (radius 0.05m = diameter 0.10m <= 0.12m)
    saucer = create_cylinder(radius=0.050, depth=0.012, vertices=14, location=(0, 0, 0.006))
    common.assign_material(saucer, p['brass_antique'])
    parts.append(saucer)
    
    saucer_rim = create_cylinder(radius=0.048, depth=0.006, vertices=14, location=(0, 0, 0.012))
    common.assign_material(saucer_rim, p['brass_antique'])
    parts.append(saucer_rim)
    
    # Stem column rising smoothly from base
    stem_base = create_cylinder(radius=0.024, depth=0.016, vertices=10, location=(0, 0, 0.022))
    common.assign_material(stem_base, p['brass_antique'])
    parts.append(stem_base)
    
    stem_shaft = create_cylinder(radius=0.014, depth=0.035, vertices=10, location=(0, 0, 0.045))
    common.assign_material(stem_shaft, p['brass_antique'])
    parts.append(stem_shaft)
    
    cup = create_cylinder(radius=0.026, depth=0.018, vertices=12, location=(0, 0, 0.070))
    common.assign_material(cup, p['brass_antique'])
    parts.append(cup)
    
    # 2. Dripping Wax Candle (Z = 0.075 to 0.245)
    candle_body = create_cylinder(radius=0.018, depth=0.170, vertices=12, location=(0, 0, 0.160))
    common.assign_material(candle_body, p['candle_wax'])
    parts.append(candle_body)
    
    # Melted drip formations attached directly to candle body
    drip_data = [
        (0.017, 0.000, 0.190, 0.005, 0.06),
        (-0.012, 0.012, 0.165, 0.004, 0.05),
        (0.008, -0.015, 0.140, 0.004, 0.04),
    ]
    for dx, dy, dz, dr, dh in drip_data:
        drip = create_cylinder(radius=dr, depth=dh, vertices=6, location=(dx, dy, dz))
        common.assign_material(drip, p['candle_wax'])
        parts.append(drip)
        
    wax_top = create_icosphere(radius=0.0185, subdivisions=1, location=(0, 0, 0.244), scale=(1.0, 1.0, 0.35))
    common.assign_material(wax_top, p['candle_wax'])
    parts.append(wax_top)
    
    # 3. Blackened Wick (Z = 0.244 to 0.260)
    wick = create_cylinder(radius=0.002, depth=0.016, vertices=6, location=(0, 0, 0.252))
    common.assign_material(wick, p['aged_iron'])
    parts.append(wick)
    
    # 4. Stylized Glowing Flame (Z = 0.258 to 0.282)
    flame_lower = create_icosphere(radius=0.011, subdivisions=1, location=(0, 0, 0.266), scale=(0.85, 0.85, 1.2))
    common.assign_material(flame_lower, p['candle_flame'])
    parts.append(flame_lower)
    
    flame_tip = create_icosphere(radius=0.006, subdivisions=1, location=(0, 0, 0.277), scale=(0.6, 0.6, 1.3))
    common.assign_material(flame_tip, p['candle_flame'])
    parts.append(flame_tip)
    
    mesh = common.join_objects(parts, "Candle")
    mesh.data.validate(verbose=False)
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_key(out_path):
    """
    Builds Key asset:
    - Antique ornate skeleton key (~0.16m long)
    - Pivot at bow/ring center (0, 0, 0)
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # Key lies along Y axis: Bow at Y=0, shank extends to Y=0.14, bit at Y=0.12..0.15
    rot_y = (math.radians(90), 0, 0)
    
    # 1. Ornate Bow (head handle)
    bow_outer = create_torus(major_radius=0.024, minor_radius=0.004, major_segments=14, minor_segments=6, location=(0, 0, 0))
    common.assign_material(bow_outer, p['brass_antique'])
    parts.append(bow_outer)
    
    # Inner trefoil/cross filigree
    bar_x = create_cube(size=1.0, location=(0, 0, 0), scale=(0.042, 0.005, 0.005))
    common.assign_material(bar_x, p['brass_antique'])
    parts.append(bar_x)
    
    bar_y = create_cube(size=1.0, location=(0, 0, 0), scale=(0.005, 0.042, 0.005))
    common.assign_material(bar_y, p['brass_antique'])
    parts.append(bar_y)
    
    center_stud = create_icosphere(radius=0.006, subdivisions=1, location=(0, 0, 0))
    common.assign_material(center_stud, p['brass_antique'])
    parts.append(center_stud)
    
    # 2. Collar decorative rings
    collar1 = create_cylinder(radius=0.008, depth=0.006, vertices=10, location=(0, 0.028, 0), rotation=rot_y)
    common.assign_material(collar1, p['brass_antique'])
    parts.append(collar1)
    
    collar2 = create_cylinder(radius=0.007, depth=0.004, vertices=10, location=(0, 0.035, 0), rotation=rot_y)
    common.assign_material(collar2, p['brass_antique'])
    parts.append(collar2)
    
    # 3. Main cylindrical shank
    shank = create_cylinder(radius=0.005, depth=0.11, vertices=10, location=(0, 0.09, 0), rotation=rot_y)
    common.assign_material(shank, p['brass_antique'])
    parts.append(shank)
    
    # Tip end bead
    tip = create_icosphere(radius=0.006, subdivisions=1, location=(0, 0.146, 0))
    common.assign_material(tip, p['brass_antique'])
    parts.append(tip)
    
    # 4. Intricate Bit / Teeth flag (extends towards -Z or +X)
    # Main bit plate
    bit_plate = create_cube(size=1.0, location=(0.012, 0.125, 0), scale=(0.020, 0.024, 0.005))
    common.assign_material(bit_plate, p['brass_antique'])
    parts.append(bit_plate)
    
    # Key tooth notch 1
    tooth1 = create_cube(size=1.0, location=(0.023, 0.133, 0), scale=(0.008, 0.007, 0.005))
    common.assign_material(tooth1, p['brass_antique'])
    parts.append(tooth1)
    
    # Key tooth notch 2
    tooth2 = create_cube(size=1.0, location=(0.021, 0.118, 0), scale=(0.006, 0.006, 0.005))
    common.assign_material(tooth2, p['brass_antique'])
    parts.append(tooth2)
    
    mesh = common.join_objects(parts, "Key")
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_fuse(out_path):
    """
    Builds industrial ceramic electrical fuse:
    - Length: ~0.12m, diameter: ~0.034m
    - White ceramic cylindrical tube body
    - Metallic terminal contact ferrule caps on both ends
    - Dark central indicator window/band
    - Pivot at bottom center (0, 0, 0), standing vertical
    - Triangle count: < 200 tris
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Ceramic Body (Z = 0.018 to 0.102, length 0.084)
    ceramic = create_cylinder(radius=0.016, depth=0.084, vertices=10, location=(0, 0, 0.060))
    common.assign_material(ceramic, p['fuse_ceramic'])
    parts.append(ceramic)
    
    # 2. Metal End Caps (Bottom: Z = 0.000 to 0.020, Top: Z = 0.100 to 0.120)
    bottom_cap = create_cylinder(radius=0.0175, depth=0.020, vertices=10, location=(0, 0, 0.010))
    common.assign_material(bottom_cap, p['fuse_metal'])
    parts.append(bottom_cap)
    
    top_cap = create_cylinder(radius=0.0175, depth=0.020, vertices=10, location=(0, 0, 0.110))
    common.assign_material(top_cap, p['fuse_metal'])
    parts.append(top_cap)
    
    # Terminal contact buttons / end nipples
    bot_nipple = create_cylinder(radius=0.008, depth=0.004, vertices=6, location=(0, 0, 0.002))
    common.assign_material(bot_nipple, p['fuse_metal'])
    parts.append(bot_nipple)
    
    top_nipple = create_cylinder(radius=0.008, depth=0.004, vertices=6, location=(0, 0, 0.121))
    common.assign_material(top_nipple, p['fuse_metal'])
    parts.append(top_nipple)
    
    # 3. Center Fuse Rating / Indicator Band
    indicator = create_cylinder(radius=0.0166, depth=0.016, vertices=10, location=(0, 0, 0.060))
    common.assign_material(indicator, p['fuse_indicator'])
    parts.append(indicator)
    
    mesh = common.join_objects(parts, "Fuse")
    mesh.data.validate(verbose=False)
    
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_battery(out_path):
    """
    Builds heavy-duty 9V-style rectangular battery:
    - Dimensions: ~0.055m (X) x 0.038m (Y) x 0.090m (Z)
    - Dark industrial plastic rectangular casing
    - Contrast brand stripe band
    - Dual top metal terminals (hexagonal snap + round socket)
    - Pivot at bottom center (0, 0, 0)
    - Triangle count: < 200 tris
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Main Plastic Casing (Z = 0.000 to 0.080)
    casing = create_cube(size=1.0, location=(0, 0, 0.040), scale=(0.054, 0.036, 0.080))
    common.assign_material(casing, p['battery_casing'])
    parts.append(casing)
    
    # 2. Golden Brand Stripe
    stripe = create_cube(size=1.0, location=(0, 0, 0.056), scale=(0.0548, 0.0368, 0.020))
    common.assign_material(stripe, p['battery_stripe'])
    parts.append(stripe)
    
    # 3. Top Terminal Insulator Plate (Z = 0.080 to 0.084)
    plate = create_cube(size=1.0, location=(0, 0, 0.082), scale=(0.048, 0.030, 0.004))
    common.assign_material(plate, p['battery_casing'])
    parts.append(plate)
    
    # 4. Top Terminals (Z = 0.084 to 0.092)
    # Positive terminal (crown / 6-sided prong snap)
    pos_terminal = create_cylinder(radius=0.0065, depth=0.008, vertices=6, location=(-0.013, 0, 0.087))
    common.assign_material(pos_terminal, p['battery_terminal'])
    parts.append(pos_terminal)
    
    # Negative terminal (octagonal socket cup)
    neg_terminal = create_cylinder(radius=0.0075, depth=0.008, vertices=8, location=(0.013, 0, 0.087))
    common.assign_material(neg_terminal, p['battery_terminal'])
    parts.append(neg_terminal)
    
    # Negative terminal inner hollow (dark void)
    neg_inner = create_cylinder(radius=0.0045, depth=0.004, vertices=6, location=(0.013, 0, 0.089))
    common.assign_material(neg_inner, p['battery_casing'])
    parts.append(neg_inner)
    
    mesh = common.join_objects(parts, "Battery")
    mesh.data.validate(verbose=False)
    
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_first_aid(out_path):
    """
    Builds medical First Aid Kit box:
    - Dimensions: ~0.25m x 0.18m x 0.10m
    - White clean case casing with hinged lid
    - Geometric 3D Red Cross on the lid (no textures)
    - Metal latches and top handle
    - Pivot at bottom center (0, 0, 0)
    - Triangle count: < 250 tris
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Main White Case Body (Z = 0.000 to 0.060)
    case_body = create_cube(size=1.0, location=(0, 0, 0.030), scale=(0.245, 0.175, 0.060))
    common.assign_material(case_body, p['first_aid_body'])
    parts.append(case_body)
    
    # 2. Case Lid (Z = 0.060 to 0.096)
    case_lid = create_cube(size=1.0, location=(0, 0, 0.078), scale=(0.250, 0.180, 0.036))
    common.assign_material(case_lid, p['first_aid_body'])
    parts.append(case_lid)
    
    # Rim seal lip between tub and lid
    rim_seal = create_cube(size=1.0, location=(0, 0, 0.060), scale=(0.252, 0.182, 0.005))
    common.assign_material(rim_seal, p['first_aid_latch'])
    parts.append(rim_seal)
    
    # 3. Two Front Metal Latches (on +Y face)
    for sign in [1, -1]:
        latch = create_cube(size=1.0, location=(sign * 0.075, 0.092, 0.060), scale=(0.024, 0.006, 0.024))
        common.assign_material(latch, p['first_aid_latch'])
        parts.append(latch)
        
    # 4. Carrying Handle (top center)
    handle_top = create_cube(size=1.0, location=(0, 0, 0.114), scale=(0.100, 0.016, 0.010))
    common.assign_material(handle_top, p['first_aid_latch'])
    parts.append(handle_top)
    
    for sign in [1, -1]:
        handle_post = create_cube(size=1.0, location=(sign * 0.044, 0, 0.105), scale=(0.012, 0.016, 0.018))
        common.assign_material(handle_post, p['first_aid_latch'])
        parts.append(handle_post)
        
    # 5. Crisp Geometric 3D Red Cross on Top Lid (Z = 0.096 to 0.100)
    # Horizontal arm
    cross_h = create_cube(size=1.0, location=(0, 0, 0.098), scale=(0.084, 0.028, 0.005))
    common.assign_material(cross_h, p['first_aid_cross'])
    parts.append(cross_h)
    
    # Vertical arm
    cross_v = create_cube(size=1.0, location=(0, 0, 0.098), scale=(0.028, 0.084, 0.005))
    common.assign_material(cross_v, p['first_aid_cross'])
    parts.append(cross_v)
    
    # Front face (+Y face) Red Cross (clearly visible from front camera)
    fcross_h = create_cube(size=1.0, location=(0, 0.090, 0.040), scale=(0.064, 0.004, 0.022))
    common.assign_material(fcross_h, p['first_aid_cross'])
    parts.append(fcross_h)
    
    fcross_v = create_cube(size=1.0, location=(0, 0.090, 0.040), scale=(0.022, 0.004, 0.064))
    common.assign_material(fcross_v, p['first_aid_cross'])
    parts.append(fcross_v)
    
    mesh = common.join_objects(parts, "First_Aid")
    mesh.data.validate(verbose=False)
    
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats

def build_food(out_path):
    """
    Builds tin can Food ration (rat bait):
    - Height: ~0.10m, diameter: ~0.076m
    - Tinplate metal body with crimped top/bottom rims
    - Contrasting paper label band
    - Top lid with stamped ring and pull-tab
    - Pivot at bottom center (0, 0, 0)
    - Triangle count: < 200 tris
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Main Tin Can Body (Z = 0.000 to 0.100, radius 0.037m)
    body = create_cylinder(radius=0.0365, depth=0.096, vertices=10, location=(0, 0, 0.050))
    common.assign_material(body, p['can_metal'])
    parts.append(body)
    
    # 2. Crimped Top and Bottom Rims
    bottom_rim = create_cylinder(radius=0.0385, depth=0.006, vertices=10, location=(0, 0, 0.003))
    common.assign_material(bottom_rim, p['can_metal'])
    parts.append(bottom_rim)
    
    top_rim = create_cylinder(radius=0.0385, depth=0.006, vertices=10, location=(0, 0, 0.097))
    common.assign_material(top_rim, p['can_metal'])
    parts.append(top_rim)
    
    # 3. Paper Label Band (Z = 0.012 to 0.088)
    label = create_cylinder(radius=0.0372, depth=0.074, vertices=10, location=(0, 0, 0.050))
    common.assign_material(label, p['can_label'])
    parts.append(label)
    
    # 4. Top Lid Recessed Ring & Pull-Tab
    lid_groove = create_cylinder(radius=0.031, depth=0.002, vertices=8, location=(0, 0, 0.099))
    common.assign_material(lid_groove, p['can_metal'])
    parts.append(lid_groove)
    
    pull_tab = create_cube(size=1.0, location=(0, 0.014, 0.101), scale=(0.016, 0.022, 0.003), rotation=(math.radians(8), 0, 0))
    common.assign_material(pull_tab, p['can_metal'])
    parts.append(pull_tab)
    
    mesh = common.join_objects(parts, "Food")
    mesh.data.validate(verbose=False)
    
    stats = common.get_stats(mesh)
    common.export_glb(out_path)
    return stats
