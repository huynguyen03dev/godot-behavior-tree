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

def build_ghost(out_path):
    """
    Builds the Ghost / Molly asset meeting exact horror character constraints:
    - Height: 2.0 - 2.2m (~2.11m)
    - Width: <= 0.75m (~0.48m)
    - Depth: <= 0.60m (~0.53m)
    - Feet at z = 0.0 (min z = 0.000m strictly)
    - Humanoid horror silhouette:
      * Distinct round/oval head (diameter ~0.24m), bowed/tilted forward
      * Dark scalp hair cap covering crown and back of skull
      * Upper torso hunched forward ~8.5 degrees around hips (+Y direction)
      * 6 long stringy dark hair strands (~0.85m long) hugging crown, nape, back, and face with zero air gaps
        (each strand penetrates >= 5cm into skull at start point)
      * Seamless continuous arms hanging along torso, curved at elbow, distinct 3-finger claw cluster
        (upper arm root penetrates 7.5cm into shoulder mantle)
      * Single continuous lofted dress/skirt from collar down to shins with 6 ragged jagged teeth,
        exposing distinct calves & feet (zero horizontal seam cuts)
      * Distinct bare feet with skeletal toes firmly planted at z=0.000m
    - Single clean mesh object (Ghost_Mesh), no orphan primitives, < 1400 tris (1280 tris).
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []

    # 1. FEET & LEGS (Z = 0.00 to 1.15)
    for sign in [1, -1]:
        lx = sign * 0.09
        # Sculpted low-poly bare foot with heel, arch, and 3 spread skeletal toes
        heel = create_cube(size=1.0, location=(lx, -0.02, 0.030), scale=(0.055, 0.070, 0.060))
        common.assign_material(heel, p['ghost_skin'])
        parts.append(heel)

        midfoot = create_cube(size=1.0, location=(lx, 0.045, 0.026), scale=(0.060, 0.075, 0.052))
        common.assign_material(midfoot, p['ghost_skin'])
        parts.append(midfoot)

        ball = create_cube(size=1.0, location=(lx, 0.095, 0.020), scale=(0.068, 0.045, 0.040))
        common.assign_material(ball, p['ghost_skin'])
        parts.append(ball)

        # 3 spread skeletal claw toes
        t_in = create_cube(size=1.0, location=(lx - sign * 0.018, 0.135, 0.015), scale=(0.018, 0.050, 0.030))
        common.assign_material(t_in, p['ghost_claw'])
        parts.append(t_in)
        t_mid = create_cube(size=1.0, location=(lx, 0.148, 0.014), scale=(0.018, 0.062, 0.028))
        common.assign_material(t_mid, p['ghost_claw'])
        parts.append(t_mid)
        t_out = create_cube(size=1.0, location=(lx + sign * 0.018, 0.132, 0.013), scale=(0.016, 0.046, 0.026))
        common.assign_material(t_out, p['ghost_claw'])
        parts.append(t_out)

        # Slender calves visible below tattered dress
        calf = create_cylinder(radius=0.034, depth=0.52, vertices=8, location=(lx, 0.01, 0.32))
        calf.data.polygons.foreach_set('use_smooth', [True] * len(calf.data.polygons))
        common.assign_material(calf, p['ghost_skin'])
        parts.append(calf)

        thigh = create_cylinder(radius=0.046, depth=0.54, vertices=8, location=(lx, 0.015, 0.85))
        thigh.data.polygons.foreach_set('use_smooth', [True] * len(thigh.data.polygons))
        common.assign_material(thigh, p['ghost_skin'])
        parts.append(thigh)

    # 2. HUNCHED POSTURE CONSTANTS & LEAN TRANSFORM (~8.5 degrees forward lean around hips)
    piv_y, piv_z = 0.015, 1.18
    lean_rad = math.radians(8.5)
    cos_l = math.cos(lean_rad)
    sin_l = math.sin(lean_rad)

    def transform_lean_forward(loc_y, loc_z):
        dy = loc_y - piv_y
        dz = loc_z - piv_z
        ny = dy * cos_l + dz * sin_l + piv_y
        nz = -dy * sin_l + dz * cos_l + piv_z
        return ny, nz

    # 3. UNIFIED CONTINUOUS TORSO & TATTERED DRESS (Z = 0.18 to 1.78)
    # A single continuous smooth-lofted BMesh surface from collar down to hem with 6 ragged jagged teeth
    # Completely eliminates all horizontal seam cuts and gaps between torso, waist, pelvis and dress.
    body_rings_def = [
        (1.78, 0.035, 0.055, 0.055),  # Collar opening
        (1.72, 0.032, 0.165, 0.080),  # Upper shoulders
        (1.66, 0.028, 0.195, 0.090),  # Broad shoulder mantle draping over arms
        (1.56, 0.025, 0.170, 0.092),  # Mid chest
        (1.44, 0.022, 0.140, 0.082),  # Lower chest
        (1.32, 0.020, 0.120, 0.075),  # Waist
        (1.18, 0.015, 0.145, 0.098),  # Hips / Pelvis
        (0.95, 0.015, 0.172, 0.125),  # Upper dress
        (0.68, 0.015, 0.208, 0.155),  # Mid dress / knees
        (0.42, 0.015, 0.242, 0.180),  # Dress hem
    ]

    bm_body = bmesh.new()
    segs = 12
    ring_verts = []
    for z_base, y_base, rx, ry in body_rings_def:
        if z_base >= 1.18:
            cy, cz = transform_lean_forward(y_base, z_base)
        else:
            cy = y_base + (z_base - 1.18) * 0.04
            cz = z_base
        ring = []
        for i in range(segs):
            ang = 2.0 * math.pi * i / segs
            vx = rx * math.cos(ang)
            vy = cy + ry * math.sin(ang)
            vz = cz
            v = bm_body.verts.new((vx, vy, vz))
            ring.append(v)
        ring_verts.append(ring)

    for r in range(len(ring_verts) - 1):
        r1, r2 = ring_verts[r], ring_verts[r+1]
        for i in range(segs):
            inxt = (i + 1) % segs
            f = bm_body.faces.new([r1[i], r1[inxt], r2[inxt], r2[i]])
            f.smooth = True

    hem_ring = ring_verts[-1]
    tip_z_values = [0.22, 0.30, 0.18, 0.28, 0.23, 0.29]
    for tooth_idx in range(6):
        i1 = tooth_idx * 2
        i2 = (i1 + 1) % segs
        i3 = (i1 + 2) % segs
        mid_ang = 2.0 * math.pi * (tooth_idx * 2 + 1) / segs
        tip_r = 0.255
        tip_z = tip_z_values[tooth_idx]
        tip_x = tip_r * math.cos(mid_ang)
        tip_y = (tip_r * 0.8) * math.sin(mid_ang) - 0.015
        tip_v = bm_body.verts.new((tip_x, tip_y, tip_z))
        f1 = bm_body.faces.new([hem_ring[i1], hem_ring[i2], tip_v])
        f2 = bm_body.faces.new([hem_ring[i2], hem_ring[i3], tip_v])
        f1.smooth = True
        f2.smooth = True

    m_body = bpy.data.meshes.new("UnifiedBody")
    bm_body.to_mesh(m_body)
    bm_body.free()
    body_obj = bpy.data.objects.new("UnifiedBody", m_body)
    bpy.context.scene.collection.objects.link(body_obj)
    common.assign_material(body_obj, p['ghost_robe'])
    parts.append(body_obj)

    # 4. NECK, HEAD, HAIR CAP, EYES, MOUTH
    # Slender neck bowed forward (14 deg), penetrating 7cm into collar and 7cm into skull
    nk_y, nk_z = transform_lean_forward(0.035, 1.82)
    neck = create_cylinder(radius=0.032, depth=0.22, vertices=8, location=(0, nk_y, nk_z), rotation=(-math.radians(14), 0, 0))
    neck.data.polygons.foreach_set('use_smooth', [True] * len(neck.data.polygons))
    common.assign_material(neck, p['ghost_skin'])
    parts.append(neck)

    # Horror skull head bowed slightly forward
    hd_y, hd_z = transform_lean_forward(0.065, 1.99)
    head = create_icosphere(radius=0.12, subdivisions=2, location=(0, hd_y, hd_z), scale=(0.95, 1.05, 1.05))
    head.data.polygons.foreach_set('use_smooth', [True] * len(head.data.polygons))
    common.assign_material(head, p['ghost_skin'])
    parts.append(head)

    # Dark hair scalp cap covering crown, temples, and back of skull
    hair_cap = create_icosphere(radius=0.124, subdivisions=2, location=(0, hd_y - 0.015, hd_z + 0.010), scale=(0.98, 1.06, 1.04))
    hair_cap.data.polygons.foreach_set('use_smooth', [True] * len(hair_cap.data.polygons))
    common.assign_material(hair_cap, p['ghost_hair'])
    parts.append(hair_cap)

    # Lower jaw
    jw_y, jw_z = transform_lean_forward(0.115, 1.90)
    jaw = create_icosphere(radius=0.065, subdivisions=1, location=(0, jw_y, jw_z), scale=(0.8, 1.0, 0.8))
    jaw.data.polygons.foreach_set('use_smooth', [True] * len(jaw.data.polygons))
    common.assign_material(jaw, p['ghost_skin'])
    parts.append(jaw)

    # Sunken dark eye voids
    for sign in [1, -1]:
        ey_y, ey_z = transform_lean_forward(0.150, 2.00)
        eye = create_icosphere(radius=0.026, subdivisions=1, location=(sign * 0.046, ey_y, ey_z), scale=(0.8, 0.6, 1.1))
        common.assign_material(eye, p['ghost_eye_void'])
        parts.append(eye)

    m_y, m_z = transform_lean_forward(0.155, 1.90)
    mouth = create_cube(size=1.0, location=(0, m_y, m_z), scale=(0.045, 0.020, 0.030), rotation=(-math.radians(14), 0, 0))
    common.assign_material(mouth, p['ghost_eye_void'])
    parts.append(mouth)

    # 5. SEAMLESS CONTINUOUS TAPERING ARMS (Deep shoulder penetration 7.5cm into shoulder mantle)
    sh_y, sh_z = transform_lean_forward(0.028, 1.68)
    for is_left in [False, True]:
        sign = -1.0 if is_left else 1.0
        bm_arm = bmesh.new()
        arm_sections = [
            # Section 0: Deep inside shoulder mantle at X = sign * 0.120 (mantle rx = 0.195, penetration = 7.5cm)
            (sign * 0.120, sh_y + 0.000, sh_z + 0.015, 0.038, 0.040),
            # Section 1: Inside shoulder mantle
            (sign * 0.165, sh_y + 0.005, sh_z - 0.020, 0.035, 0.037),
            # Section 2: Exiting under mantle at deltoid
            (sign * 0.195, sh_y + 0.015, sh_z - 0.080, 0.030, 0.032),
            # Section 3: Upper bicep hanging down
            (sign * 0.190, sh_y + 0.030, sh_z - 0.200, 0.026, 0.027),
            # Section 4: Elbow slightly forward and 3.5cm from dress
            (sign * 0.188, sh_y + 0.055, sh_z - 0.350, 0.022, 0.023),
            # Section 5: Forearm
            (sign * 0.182, sh_y + 0.075, sh_z - 0.500, 0.018, 0.019),
            # Section 6: Wrist
            (sign * 0.175, sh_y + 0.088, sh_z - 0.650, 0.015, 0.016),
            # Section 7: Palm base
            (sign * 0.170, sh_y + 0.095, sh_z - 0.720, 0.022, 0.012),
        ]
        arm_rings = []
        segs_arm = 8
        for ax, ay, az, rx, ry in arm_sections:
            ring = []
            for i in range(segs_arm):
                ang = 2.0 * math.pi * i / segs_arm
                vx = ax + rx * math.cos(ang)
                vy = ay + ry * math.sin(ang)
                vz = az
                v = bm_arm.verts.new((vx, vy, vz))
                ring.append(v)
            arm_rings.append(ring)

        for r in range(len(arm_rings) - 1):
            r1 = arm_rings[r]
            r2 = arm_rings[r + 1]
            for i in range(segs_arm):
                inxt = (i + 1) % segs_arm
                f = bm_arm.faces.new([r1[i], r1[inxt], r2[inxt], r2[i]])
                f.smooth = True
        bm_arm.faces.new(arm_rings[0])

        palm_center = Vector((sign * 0.170, sh_y + 0.095, sh_z - 0.720))
        finger_defs = [
            (sign * 0.018,  0.015, -0.110, 0.007, 0.003),
            (sign * 0.000,  0.018, -0.145, 0.008, 0.003),
            (-sign * 0.016, 0.010, -0.120, 0.007, 0.003),
        ]
        for fdx, fdy, fdz, fr_base, fr_tip in finger_defs:
            f_base_center = palm_center + Vector((fdx * 0.4, fdy * 0.3, 0))
            f_tip_center = palm_center + Vector((fdx, fdy, fdz))
            f_ring1, f_ring2 = [], []
            for fi in range(4):
                fang = math.pi * 0.25 + fi * math.pi * 0.5
                v1 = bm_arm.verts.new(f_base_center + Vector((fr_base * math.cos(fang), fr_base * math.sin(fang), 0)))
                v2 = bm_arm.verts.new(f_tip_center + Vector((fr_tip * math.cos(fang), fr_tip * math.sin(fang), 0)))
                f_ring1.append(v1)
                f_ring2.append(v2)
            tip_vert = bm_arm.verts.new(f_tip_center + Vector((0, 0, -0.015)))
            for fi in range(4):
                fi_next = (fi + 1) % 4
                f1 = bm_arm.faces.new([f_ring1[fi], f_ring1[fi_next], f_ring2[fi_next], f_ring2[fi]])
                f1.smooth = True
                f2 = bm_arm.faces.new([f_ring2[fi], f_ring2[fi_next], tip_vert])
                f2.smooth = True
            bm_arm.faces.new(reversed(f_ring1))

        m_arm = bpy.data.meshes.new(f"Arm_{'L' if is_left else 'R'}")
        bm_arm.to_mesh(m_arm)
        bm_arm.free()
        arm_obj = bpy.data.objects.new(f"Arm_{'L' if is_left else 'R'}", m_arm)
        bpy.context.scene.collection.objects.link(arm_obj)
        common.assign_material(arm_obj, p['ghost_skin'])
        parts.append(arm_obj)

    # 6. LONG STRINGY DARK HAIR STRANDS (~0.85m long, hugging back of skull, nape, and back)
    def create_hair_ribbon(points, w_start=0.045, w_end=0.012, name="HairRibbon"):
        bm = bmesh.new()
        rings = []
        n_pts = len(points)
        for idx, pt in enumerate(points):
            t = idx / float(n_pts - 1)
            w = w_start * (1.0 - t * 0.60)
            th = 0.014 * (1.0 - t * 0.40)
            if idx < n_pts - 1:
                tang = (points[idx+1] - pt).normalized()
            else:
                tang = (pt - points[idx-1]).normalized()
            norm = Vector((0, 0, 1)).cross(tang)
            if norm.length < 1e-4:
                norm = Vector((1, 0, 0))
            norm.normalize()
            binorm = tang.cross(norm).normalized()

            v1 = bm.verts.new(pt - norm * (w * 0.5) - binorm * (th * 0.5))
            v2 = bm.verts.new(pt + norm * (w * 0.5) - binorm * (th * 0.5))
            v3 = bm.verts.new(pt + norm * (w * 0.5) + binorm * (th * 0.5))
            v4 = bm.verts.new(pt - norm * (w * 0.5) + binorm * (th * 0.5))
            rings.append([v1, v2, v3, v4])
        for r in range(len(rings) - 1):
            r1, r2 = rings[r], rings[r+1]
            for i in range(4):
                inxt = (i + 1) % 4
                f = bm.faces.new([r1[i], r1[inxt], r2[inxt], r2[i]])
                f.smooth = True
        bm.faces.new(rings[0])
        bm.faces.new(reversed(rings[-1]))
        m = bpy.data.meshes.new(name)
        bm.to_mesh(m)
        bm.free()
        o = bpy.data.objects.new(name, m)
        bpy.context.scene.collection.objects.link(o)
        return o

    # 6 hair ribbons strictly hugging the back of head, nape, back, and framing face:
    # All start points p0 penetrate >= 5cm into the skull.
    hair_configs = [
        # 0. Center spine strand (down spine to waist)
        [Vector((0.000, 0.160, 2.030)),
         Vector((0.005, 0.085, 1.860)),
         Vector((0.005, 0.010, 1.680)),
         Vector((0.008, -0.020, 1.480)),
         Vector((0.005, -0.050, 1.250))],

        # 1. Left back strand
        [Vector((-0.040, 0.155, 2.025)),
         Vector((-0.050, 0.080, 1.850)),
         Vector((-0.065, 0.008, 1.670)),
         Vector((-0.055, -0.022, 1.460)),
         Vector((-0.040, -0.045, 1.240))],

        # 2. Right back strand
        [Vector((0.040, 0.155, 2.025)),
         Vector((0.050, 0.080, 1.850)),
         Vector((0.065, 0.008, 1.670)),
         Vector((0.055, -0.022, 1.460)),
         Vector((0.040, -0.045, 1.250))],

        # 3. Left outer back / shoulder drape (falling down behind left shoulder)
        [Vector((-0.070, 0.165, 2.015)),
         Vector((-0.080, 0.100, 1.860)),
         Vector((-0.105, 0.035, 1.690)),
         Vector((-0.115, 0.010, 1.500)),
         Vector((-0.100, -0.015, 1.280))],

        # 4. Right outer back / shoulder drape (falling down behind right shoulder)
        [Vector((0.070, 0.165, 2.015)),
         Vector((0.080, 0.100, 1.860)),
         Vector((0.105, 0.035, 1.690)),
         Vector((0.115, 0.010, 1.500)),
         Vector((0.100, -0.015, 1.280))],

        # 5. Face-framing wet strand (down left cheek and falling onto upper chest)
        [Vector((-0.045, 0.190, 2.020)),
         Vector((-0.055, 0.195, 1.880)),
         Vector((-0.050, 0.170, 1.700)),
         Vector((-0.045, 0.145, 1.500)),
         Vector((-0.035, 0.120, 1.300))],
    ]

    for idx, pts in enumerate(hair_configs):
        h_obj = create_hair_ribbon(pts, name=f"Hair_{idx}")
        common.assign_material(h_obj, p['ghost_hair'])
        parts.append(h_obj)

    ghost_mesh = common.join_objects(parts, "Ghost_Mesh")
    ghost_mesh.data.validate(verbose=False)
    stats = common.get_stats(ghost_mesh)

    common.export_glb(out_path)
    return stats

def build_player_body(out_path):
    """
    Builds the Player Body asset:
    - ~1.8m tall survivor
    - Boots, dark denim jeans, tactical jacket/hoodie, hands, head/hair
    - Origin at feet (Z=0 in Blender, Y=0 in Godot), facing +Y (Godot -Z forward)
    """
    common.clean_scene()
    p = palette.get_palette()
    
    parts = []
    
    # 1. Boots (Z: 0 to 0.25)
    for sign in [1, -1]:
        sole = create_cube(size=1.0, location=(sign * 0.14, 0.03, 0.04), scale=(0.12, 0.26, 0.08))
        common.assign_material(sole, p['player_boots'])
        parts.append(sole)
        
        ankle = create_cylinder(radius=0.07, depth=0.18, vertices=8, location=(sign * 0.14, 0.0, 0.16))
        common.assign_material(ankle, p['player_boots'])
        parts.append(ankle)
    
    # 2. Jeans / legs (Z: 0.25 to 0.95)
    for sign in [1, -1]:
        calf = create_cylinder(radius=0.075, depth=0.40, vertices=8, location=(sign * 0.14, 0.0, 0.42))
        common.assign_material(calf, p['player_jeans'])
        parts.append(calf)
        
        knee = create_icosphere(radius=0.078, subdivisions=1, location=(sign * 0.14, 0.02, 0.62))
        common.assign_material(knee, p['player_jeans'])
        parts.append(knee)
        
        thigh = create_cylinder(radius=0.095, depth=0.38, vertices=8, location=(sign * 0.13, 0.0, 0.78))
        common.assign_material(thigh, p['player_jeans'])
        parts.append(thigh)
        
    pelvis = create_cube(size=1.0, location=(0, 0, 0.95), scale=(0.32, 0.22, 0.16))
    common.assign_material(pelvis, p['player_jeans'])
    parts.append(pelvis)
    
    # 3. Torso / Jacket (Z: 0.98 to 1.52)
    jacket_hem = create_cube(size=1.0, location=(0, 0, 1.02), scale=(0.35, 0.24, 0.12))
    common.assign_material(jacket_hem, p['player_jacket'])
    parts.append(jacket_hem)
    
    torso = create_cylinder(radius=0.18, depth=0.44, vertices=10, location=(0, 0, 1.25), scale=(1.05, 0.75, 1.0))
    common.assign_material(torso, p['player_jacket'])
    parts.append(torso)
    
    chest = create_cube(size=1.0, location=(0, 0, 1.42), scale=(0.42, 0.24, 0.18))
    common.assign_material(chest, p['player_jacket'])
    parts.append(chest)
    
    collar = create_cylinder(radius=0.12, depth=0.10, vertices=8, location=(0, -0.01, 1.52))
    common.assign_material(collar, p['player_jacket'])
    parts.append(collar)
    
    # 4. Arms & Hands
    for sign in [1, -1]:
        sh_pad = create_icosphere(radius=0.08, subdivisions=1, location=(sign * 0.24, 0.0, 1.44), scale=(0.9, 0.9, 1.1))
        common.assign_material(sh_pad, p['player_jacket'])
        parts.append(sh_pad)
        
        uarm = create_cylinder(radius=0.065, depth=0.32, vertices=8, location=(sign * 0.26, 0.0, 1.28))
        common.assign_material(uarm, p['player_jacket'])
        parts.append(uarm)
        
        elbow = create_icosphere(radius=0.06, subdivisions=1, location=(sign * 0.27, -0.01, 1.12))
        common.assign_material(elbow, p['player_jacket'])
        parts.append(elbow)
        
        farm = create_cylinder(radius=0.055, depth=0.30, vertices=8, location=(sign * 0.28, 0.01, 0.98))
        common.assign_material(farm, p['player_jacket'])
        parts.append(farm)
        
        hand = create_cube(size=1.0, location=(sign * 0.29, 0.02, 0.79), scale=(0.045, 0.08, 0.11))
        common.assign_material(hand, p['player_skin'])
        parts.append(hand)
    
    # 5. Head and Hair (Z: 1.54 to 1.80)
    neck = create_cylinder(radius=0.06, depth=0.10, vertices=8, location=(0, 0, 1.54))
    common.assign_material(neck, p['player_skin'])
    parts.append(neck)
    
    head = create_icosphere(radius=0.12, subdivisions=2, location=(0, 0.02, 1.66), scale=(0.85, 0.95, 1.05))
    common.assign_material(head, p['player_skin'])
    parts.append(head)
    
    hair_top = create_icosphere(radius=0.125, subdivisions=2, location=(0, 0.01, 1.71), scale=(0.9, 1.0, 0.8))
    common.assign_material(hair_top, p['player_hair'])
    parts.append(hair_top)
    
    hair_back = create_cube(size=1.0, location=(0, -0.05, 1.67), scale=(0.18, 0.08, 0.15))
    common.assign_material(hair_back, p['player_hair'])
    parts.append(hair_back)
    
    player_mesh = common.join_objects(parts, "Player_Body")
    player_mesh.data.validate(verbose=False)
    
    stats = common.get_stats(player_mesh)
    common.export_glb(out_path)
    return stats

def build_rat(out_path):
    """
    Builds the low-poly Rat asset for Farmhouse ritual:
    - Length ~0.28m, height ~0.10m, width ~0.09m
    - Oblong rounded body, small tapered head with 2 rounded ears and snout
    - 4 short legs with paws touching ground at Z = 0.000
    - Long thin tail (~0.20m) tapering behind
    - Grey-brown fur with pink paws/ears/snout and black beady eyes
    - Origin at ground under belly (feet at Z = 0.000), facing +Y (Godot -Z forward)
    - Triangle count: < 400 tris
    """
    common.clean_scene()
    p = palette.get_palette()
    parts = []
    
    # 1. Main Torso Body (oval/ellipsoid, centered at Y = 0.01, Z = 0.055)
    # Length: 0.14m (-0.06 to +0.08), Width: 0.075m, Height: 0.065m (Z = 0.025 to 0.090)
    body = create_icosphere(radius=0.045, subdivisions=1, location=(0, 0.01, 0.055), scale=(0.82, 1.55, 0.72))
    common.assign_material(body, p['rat_fur'])
    parts.append(body)
    
    # 2. Tapering Head (Y = 0.07 to 0.14, Z = 0.035 to 0.075)
    head = create_icosphere(radius=0.030, subdivisions=1, location=(0, 0.085, 0.052), scale=(0.75, 1.30, 0.75))
    common.assign_material(head, p['rat_fur'])
    parts.append(head)
    
    # Pointed snout cone
    snout = create_cylinder(radius=0.015, depth=0.032, vertices=5, location=(0, 0.122, 0.048), rotation=(math.radians(90), 0, 0), scale=(0.8, 1.0, 0.6))
    common.assign_material(snout, p['rat_fur'])
    parts.append(snout)
    
    # Pink nose tip
    nose = create_cube(size=1.0, location=(0, 0.138, 0.046), scale=(0.008, 0.008, 0.008))
    common.assign_material(nose, p['rat_pink'])
    parts.append(nose)
    
    # 2 Rounded Ears (top of head, tilted back slightly)
    for sign in [1, -1]:
        ear = create_cylinder(radius=0.013, depth=0.004, vertices=6, location=(sign * 0.024, 0.075, 0.078), rotation=(math.radians(20), math.radians(sign * 25), 0))
        common.assign_material(ear, p['rat_pink'])
        parts.append(ear)
        
    # 2 Black Beady Eyes
    for sign in [1, -1]:
        eye = create_cube(size=1.0, location=(sign * 0.022, 0.098, 0.058), scale=(0.008, 0.008, 0.008))
        common.assign_material(eye, p['rat_eye'])
        parts.append(eye)
        
    # 3. 4 Short Legs & Paws (feet at Z = 0.000)
    # Front legs (Y = 0.050)
    for sign in [1, -1]:
        fleg = create_cylinder(radius=0.007, depth=0.025, vertices=6, location=(sign * 0.028, 0.050, 0.018))
        common.assign_material(fleg, p['rat_fur'])
        parts.append(fleg)
        
        fpaw = create_cube(size=1.0, location=(sign * 0.028, 0.056, 0.004), scale=(0.012, 0.018, 0.008))
        common.assign_material(fpaw, p['rat_pink'])
        parts.append(fpaw)
        
    # Hind legs / haunches (Y = -0.035, wider base)
    for sign in [1, -1]:
        haunch = create_cylinder(radius=0.016, depth=0.032, vertices=6, location=(sign * 0.034, -0.030, 0.038), scale=(0.8, 1.2, 0.9))
        common.assign_material(haunch, p['rat_fur'])
        parts.append(haunch)
        
        hleg = create_cylinder(radius=0.007, depth=0.024, vertices=6, location=(sign * 0.032, -0.035, 0.016))
        common.assign_material(hleg, p['rat_fur'])
        parts.append(hleg)
        
        hpaw = create_cube(size=1.0, location=(sign * 0.032, -0.028, 0.004), scale=(0.014, 0.022, 0.008))
        common.assign_material(hpaw, p['rat_pink'])
        parts.append(hpaw)
        
    # 4. Long Thin Tail (~0.16m length behind body, total rat length ~0.28m)
    tail_segments = [
        # (x, y, z, r1, len, rot_x, rot_z)
        (0.000, -0.070, 0.046, 0.0055, 0.038, 75, 0),
        (0.004, -0.104, 0.036, 0.0045, 0.038, 80, 8),
        (0.012, -0.138, 0.024, 0.0035, 0.038, 85, 12),
        (0.020, -0.172, 0.014, 0.0025, 0.038, 88, 6),
    ]
    for tx, ty, tz, tr, tlen, rx, rz in tail_segments:
        tseg = create_cylinder(
            radius=tr, depth=tlen, vertices=6, location=(tx, ty, tz),
            rotation=(math.radians(rx), 0, math.radians(rz))
        )
        common.assign_material(tseg, p['rat_pink'])
        parts.append(tseg)
        
    rat_mesh = common.join_objects(parts, "Rat")
    rat_mesh.data.validate(verbose=False)
    
    stats = common.get_stats(rat_mesh)
    common.export_glb(out_path)
    return stats
