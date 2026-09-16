# ============================================================================
# render_test.py — headless smoke test.
# Run:  blender --background --python render_test.py
#
# Proves: Blender works, Cycles works, and (if a GPU is present) it is
# actually being used for the render. Writes $WORKDIR/test-render.png
# ============================================================================
import bpy
import os
import time

WORK = os.environ.get("WORKDIR", "/kaggle/working")
os.makedirs(WORK, exist_ok=True)
OUT = os.path.join(WORK, "test-render.png")

# --- device selection (same logic as startup_blender.py) ---------------------
def pick_backend():
    cp = bpy.context.preferences.addons["cycles"].preferences
    for dtype in ("OPTIX", "CUDA"):
        try:
            cp.compute_device_type = dtype
            cp.get_devices()
        except Exception:
            continue
        if any(d.type == dtype for d in cp.devices):
            for d in cp.devices:
                d.use = (d.type == dtype)
            return dtype, [d.name for d in cp.devices if d.type == dtype]
    cp.compute_device_type = "NONE"
    for d in cp.devices:
        d.use = (d.type == "CPU")
    return "CPU", ["CPU"]

backend, devices = pick_backend()
print(f"[render_test] backend={backend} devices={devices}")

# --- minimal scene: a beveled cube on a plane with a sun ---------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=1.4, location=(0, 0, 0.7))
bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
bpy.ops.object.shade_smooth()
sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", type="SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (0.9, 0.3, 0.6)
bpy.context.collection.objects.link(sun)
cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
cam.data.lens = 50
cam.location = (4.2, -4.6, 2.6)
cam.rotation_euler = (1.25, 0.05, 0.9)
bpy.context.collection.objects.link(cam)
bpy.context.scene.camera = cam

# --- cycles settings ----------------------------------------------------------
scn = bpy.context.scene
scn.render.engine = "CYCLES"
scn.cycles.samples = 96
scn.render.resolution_x = 480
scn.render.resolution_y = 270
if backend in ("OPTIX", "CUDA"):
    scn.cycles.device = "GPU"
else:
    scn.cycles.device = "CPU"

t0 = time.time()
scn.render.filepath = OUT
bpy.ops.render.render(write_still=True)
dt = time.time() - t0

print(f"[render_test] DONE in {dt:.1f}s → {OUT}")
print(f"[render_test] device={'GPU' if backend in ('OPTIX','CUDA') else 'CPU'} backend={backend}")
