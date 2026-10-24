import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix, Euler

def clean_scene():
    """Wipes all data blocks for a fresh start."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Ensure active scene exists
    if not bpy.data.scenes:
        bpy.data.scenes.new("Scene")

def create_material(name, base_color, roughness=0.8, metallic=0.0, emission=None, emission_strength=1.0):
    """Creates or retrieves a Principled BSDF material."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
    
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    node_out = nodes.new(type="ShaderNodeOutputMaterial")
    node_bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    
    # In Blender 4.x Principled BSDF inputs:
    # "Base Color", "Roughness", "Metallic", "Emission Color", "Emission Strength"
    node_bsdf.inputs["Base Color"].default_value = (
        base_color[0], base_color[1], base_color[2], base_color[3] if len(base_color) > 3 else 1.0
    )
    node_bsdf.inputs["Roughness"].default_value = roughness
    node_bsdf.inputs["Metallic"].default_value = metallic
    
    if emission is not None:
        if "Emission Color" in node_bsdf.inputs:
            node_bsdf.inputs["Emission Color"].default_value = (
                emission[0], emission[1], emission[2], 1.0
            )
            node_bsdf.inputs["Emission Strength"].default_value = emission_strength
        elif "Emission" in node_bsdf.inputs:
            node_bsdf.inputs["Emission"].default_value = (
                emission[0], emission[1], emission[2], 1.0
            )
    
    mat.node_tree.links.new(node_bsdf.outputs["BSDF"], node_out.inputs["Surface"])
    return mat

def assign_material(obj, mat):
    """Assigns material to object."""
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)

def join_objects(objects, target_name):
    """Joins a list of mesh objects into a single mesh object."""
    if not objects:
        return None
    valid_objs = [o for o in objects if o is not None and o.type == 'MESH']
    if not valid_objs:
        return None
    if len(valid_objs) == 1:
        valid_objs[0].name = target_name
        return valid_objs[0]
    
    ctx = bpy.context
    for o in ctx.scene.objects:
        o.select_set(False)
    
    for o in valid_objs:
        o.select_set(True)
    ctx.view_layer.objects.active = valid_objs[0]
    bpy.ops.object.join()
    active = ctx.active_object
    active.name = target_name
    active.data.name = target_name
    active.data.validate()
    return active

def apply_transforms(obj, location=True, rotation=True, scale=True):
    """Applies object transforms."""
    ctx = bpy.context
    for o in ctx.scene.objects:
        o.select_set(False)
    obj.select_set(True)
    ctx.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=location, rotation=rotation, scale=scale)

def get_stats(obj):
    """Returns triangle count, vertex count, and bounding box dimensions in meters."""
    if obj is None:
        return {"tris": 0, "verts": 0, "dims": (0, 0, 0)}
    
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(depsgraph)
    mesh = eval_obj.to_mesh()
    mesh.calc_loop_triangles()
    tris = len(mesh.loop_triangles)
    verts = len(mesh.vertices)
    dims = (round(obj.dimensions.x, 3), round(obj.dimensions.y, 3), round(obj.dimensions.z, 3))
    eval_obj.to_mesh_clear()
    return {"tris": tris, "verts": verts, "dims": dims}

def export_glb(filepath):
    """Exports scene to GLB."""
    os.makedirs(os.path.dirname(os.path.abspath(filepath)), exist_ok=True)
    # Purge unlinked data blocks
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        use_selection=False,
        export_yup=True,
        export_apply=False  # Do not force apply modifiers to keep armature skinning intact
    )

def render_preview_and_get_bounds(glb_path, preview_path, camera_angle_deg=0.0, light_background=False):
    """
    Re-imports exported GLB in a fresh scene, computes exact world bounds
    (width, depth, height, min_z), and renders a Workbench preview
    with camera auto-framing.
    - camera_angle_deg: 0 for front view (+Y facing -Y), 35 for three-quarter view.
    - light_background: If True, uses studio light gray background (0.75, 0.75, 0.78) at 560x760
      for geometric silhouette audit.
    """
    clean_scene()
    scene = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    mesh_objs = [o for o in scene.objects if o.type == 'MESH']
    if not mesh_objs:
        return {
            'width': 0.0, 'depth': 0.0, 'height': 0.0, 'min_z': 0.0,
            'min_x': 0.0, 'max_x': 0.0, 'min_y': 0.0, 'max_y': 0.0, 'max_z': 0.0
        }
        
    bounds_min = Vector((1e9, 1e9, 1e9))
    bounds_max = Vector((-1e9, -1e9, -1e9))
    for obj in mesh_objs:
        for b in obj.bound_box:
            wb = obj.matrix_world @ Vector(b)
            bounds_min.x = min(bounds_min.x, wb.x)
            bounds_min.y = min(bounds_min.y, wb.y)
            bounds_min.z = min(bounds_min.z, wb.z)
            bounds_max.x = max(bounds_max.x, wb.x)
            bounds_max.y = max(bounds_max.y, wb.y)
            bounds_max.z = max(bounds_max.z, wb.z)
            
    center = (bounds_min + bounds_max) / 2.0
    dim_x = max(bounds_max.x - bounds_min.x, 0.02)
    dim_y = max(bounds_max.y - bounds_min.y, 0.02)
    dim_z = max(bounds_max.z - bounds_min.z, 0.02)
    
    # Camera auto-framing
    cam = bpy.data.cameras.new('PreviewCam')
    cam.sensor_fit = 'VERTICAL'
    cam.lens = 50
    fov_y = 2.0 * math.atan((cam.sensor_height / 2.0) / cam.lens)
    res_x = 560
    res_y = 760 if light_background else 720
    aspect = float(res_x) / float(res_y)
    margin = 1.30
    
    # Compute horizontal bounding radius for arbitrary azimuth angle
    horiz_span = max(dim_x, dim_y)
    d_v = ((dim_z * margin) / 2.0) / math.tan(fov_y / 2.0)
    d_h = ((horiz_span * margin) / 2.0) / (math.tan(fov_y / 2.0) * aspect)
    dist = max(d_v, d_h) + (horiz_span / 2.0)
    
    cam_obj = bpy.data.objects.new('PreviewCam', cam)
    scene.collection.objects.link(cam_obj)
    
    # Position camera around target center based on angle
    rad = math.radians(camera_angle_deg)
    cam_x = center.x + dist * math.sin(rad)
    cam_y = center.y + dist * math.cos(rad)
    cam_z = center.z + dist * 0.08  # slightly elevated view
    
    cam_obj.location = Vector((cam_x, cam_y, cam_z))
    # Point camera at center
    direction = (center - cam_obj.location).normalized()
    rot_quat = direction.to_track_quat('-Z', 'Y')
    cam_obj.rotation_euler = rot_quat.to_euler()
    scene.camera = cam_obj
    
    # Workbench settings
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    scene.display.shading.studio_light = 'Default'
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.render_aa = 'FXAA'
    
    if light_background:
        # Bright studio background for geometric silhouette validation
        scene.display.shading.background_type = 'VIEWPORT'
        scene.display.shading.background_color = (0.75, 0.75, 0.78)
        world = bpy.data.worlds.new('LightWorld')
        scene.world = world
        world.use_nodes = False
        world.color = (0.75, 0.75, 0.78)
    else:
        # Dark horror background #0c0d10
        world = bpy.data.worlds.new('DarkWorld')
        scene.world = world
        world.use_nodes = False
        world.color = (0.047, 0.051, 0.063)
    
    os.makedirs(os.path.dirname(os.path.abspath(preview_path)), exist_ok=True)
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.filepath = preview_path
    scene.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    
    return {
        'min_x': round(bounds_min.x, 3), 'max_x': round(bounds_max.x, 3),
        'min_y': round(bounds_min.y, 3), 'max_y': round(bounds_max.y, 3),
        'min_z': round(bounds_min.z, 3), 'max_z': round(bounds_max.z, 3),
        'width': round(bounds_max.x - bounds_min.x, 3),
        'depth': round(bounds_max.y - bounds_min.y, 3),
        'height': round(bounds_max.z - bounds_min.z, 3),
    }
