# ============================================================================
# startup_blender.py — run via  blender --python-startup startup_blender.py
#
# Auto-configures Cycles compute devices:
#   1) prefer OPTIX  (fastest on T4 / P100 when the driver is present)
#   2) fall back to CUDA
#   3) fall back to CPU
# All detected GPUs are enabled (2x T4 → both used by Cycles multi-GPU).
# Prints a summary you can see in the Blender console / blender.log.
# ============================================================================
import bpy
import traceback

def main():
    cycles = bpy.context.preferences.addons.get("cycles")
    if cycles is None:
        print("[aureline] cycles addon not found")
        return
    cp = cycles.preferences
    chosen = None
    for dtype in ("OPTIX", "CUDA"):
        try:
            cp.compute_device_type = dtype
            cp.get_devices()
        except Exception:
            continue
        gpus = [d for d in cp.devices if d.type == dtype]
        if gpus:
            chosen = dtype
            break
    if chosen:
        for d in cp.devices:
            d.use = (d.type == chosen)
    else:
        cp.compute_device_type = "NONE"
        for d in cp.devices:
            d.use = (d.type == "CPU")
        chosen = "CPU"

    lines = ["=" * 52]
    lines.append(f"  Cycles compute backend: {chosen}")
    for d in cp.devices:
        state = "ON " if d.use else "off"
        mem_bytes = getattr(d, "memory", 0)
        mem = f" {mem_bytes / (1024**3):.1f} GB" if mem_bytes else ""
        lines.append(f"  - {d.name} [{d.type}] {state}{mem}")
    if chosen in ("OPTIX", "CUDA") and any(d.use for d in cp.devices if d.type == chosen):
        lines.append("  ✔ GPU rendering enabled (all detected GPUs)")
    else:
        lines.append("  ⚠ CPU-only rendering")
    lines.append("=" * 52)
    print("\n".join(lines))

try:
    main()
except Exception:
    print("[aureline] startup config failed:\n" + traceback.format_exc())
