#!/usr/bin/env python3
"""
scripts/load_video.py
Display Sink RTL - Custom Video Ingestion & Frame Preprocessing Tool

Extracts, formats, and installs user video frames into media/video1/ or media/video2/
for real-time hardware simulation playback.

Features:
- Animated GIF support (frame-by-frame extraction via Pillow)
- MP4 / AVI / MOV / MKV video support (via ffmpeg when available)
- Image directory / single image support (PNG, JPG, BMP, WebP)
- Built-in --demo generator to create custom test video animations
- Automatic resolution scaling (default: 640x480 for 480p hardware upscaler testing)
- Generates clean Netpbm PPM (P6 binary) and BMP frames readable by C++ with zero external dependencies.

Usage:
  python3 scripts/load_video.py <input_file_or_dir> [slot: 1 or 2] [--res 480p|720p|1080p]
  python3 scripts/load_video.py --demo 1
  python3 scripts/load_video.py --demo 2
  python3 scripts/load_video.py --clear 1
"""

import sys
import os
import shutil
import math
import subprocess
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageSequence
except ImportError:
    print("[ERROR] Pillow (PIL) is not installed. Run: pip install Pillow")
    sys.exit(1)

RESOLUTIONS = {
    "480p":  (640, 480),
    "720p":  (1280, 720),
    "1080p": (1920, 1080)
}

REPO_ROOT = Path(__file__).resolve().parent.parent
MEDIA_DIR = REPO_ROOT / "media"
SLOT_DIRS = {
    1: MEDIA_DIR / "video1",
    2: MEDIA_DIR / "video2"
}

def ensure_slot_dir(slot: int) -> Path:
    target = SLOT_DIRS[slot]
    target.mkdir(parents=True, exist_ok=True)
    return target

def clear_slot(slot: int):
    target = SLOT_DIRS[slot]
    if target.exists():
        for f in target.iterdir():
            if f.name != ".gitkeep":
                if f.is_file():
                    f.unlink()
                elif f.is_dir():
                    shutil.rmtree(f)
    gitkeep = target / ".gitkeep"
    if not gitkeep.exists():
        gitkeep.touch()
    print(f"[INFO] Cleared video slot {slot} ({target})")

def save_frame_ppm(img: Image.Image, output_path: Path):
    """Save an RGB PIL Image as a binary P6 Netpbm PPM file."""
    img_rgb = img.convert("RGB")
    w, h = img_rgb.size
    header = f"P6\n{w} {h}\n255\n".encode("ascii")
    with open(output_path, "wb") as f:
        f.write(header)
        f.write(img_rgb.tobytes())

def generate_demo_video(slot: int, num_frames=30, res="480p"):
    """Generates a synthetic animated custom video demo in the specified slot."""
    target = ensure_slot_dir(slot)
    clear_slot(slot)
    w, h = RESOLUTIONS.get(res, (640, 480))
    print(f"[INFO] Generating {num_frames}-frame custom demo animation in Slot {slot} ({w}x{h})...")

    for i in range(num_frames):
        im = Image.new("RGB", (w, h), (15, 20, 30))
        draw = ImageDraw.Draw(im)

        # Draw moving radar / spinning star
        cx, cy = w // 2, h // 2
        radius = min(w, h) // 3
        angle = (2 * math.pi * i) / num_frames

        # Concentric circles
        for r in range(40, radius + 20, 40):
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(60, 80, 110), width=1)

        # Rotating beam
        ex = cx + int(radius * math.cos(angle))
        ey = cy + int(radius * math.sin(angle))
        beam_color = (0, 255, 200) if slot == 1 else (255, 120, 0)
        draw.line([cx, cy, ex, ey], fill=beam_color, width=3)

        # Satellite blip
        bx = cx + int((radius * 0.7) * math.cos(angle * 1.5))
        by = cy + int((radius * 0.7) * math.sin(angle * 1.5))
        draw.ellipse([bx - 8, by - 8, bx + 8, by + 8], fill=(255, 255, 255))

        # Title text header
        label = f"CUSTOM VIDEO {slot} - FRAME {i+1:02d}/{num_frames:02d}"
        draw.text((20, 20), label, fill=(255, 255, 255))
        draw.text((20, 40), f"Display Sink RTL Hardware Ingestion [{res}]", fill=(180, 180, 180))

        out_name = target / f"frame_{i:04d}.ppm"
        save_frame_ppm(im, out_name)

    print(f"[SUCCESS] Slot {slot} loaded with {num_frames} frames ({res}) in {target}")
    print(f"          Launch viewer with 'make view', then press F{4 + slot} or 'V' to view!")

def process_gif(gif_path: Path, slot: int, target_res: tuple):
    target = ensure_slot_dir(slot)
    clear_slot(slot)
    print(f"[INFO] Processing GIF: {gif_path} -> Slot {slot}...")
    im = Image.open(gif_path)
    count = 0
    for frame in ImageSequence.Iterator(im):
        resized = frame.copy().resize(target_res, Image.Resampling.LANCZOS)
        out_path = target / f"frame_{count:04d}.ppm"
        save_frame_ppm(resized, out_path)
        count += 1
    print(f"[SUCCESS] Extracted and installed {count} frames to Slot {slot} ({target})")

def process_image_dir(dir_path: Path, slot: int, target_res: tuple):
    target = ensure_slot_dir(slot)
    clear_slot(slot)
    files = sorted([f for f in dir_path.iterdir() if f.suffix.lower() in [".png", ".jpg", ".jpeg", ".bmp", ".webp", ".ppm"]])
    if not files:
        print(f"[ERROR] No valid image files found in {dir_path}")
        return
    print(f"[INFO] Processing {len(files)} image files -> Slot {slot}...")
    count = 0
    for f in files:
        try:
            im = Image.open(f)
            resized = im.resize(target_res, Image.Resampling.LANCZOS)
            out_path = target / f"frame_{count:04d}.ppm"
            save_frame_ppm(resized, out_path)
            count += 1
        except Exception as e:
            print(f"[WARNING] Skipping {f.name}: {e}")
    print(f"[SUCCESS] Installed {count} frames to Slot {slot} ({target})")

def process_video_file(video_path: Path, slot: int, target_res: tuple):
    target = ensure_slot_dir(slot)
    clear_slot(slot)
    w, h = target_res
    print(f"[INFO] Processing video container: {video_path} -> Slot {slot}...")

    # Check ffmpeg availability
    ffmpeg_bin = shutil.which("ffmpeg")
    if ffmpeg_bin:
        cmd = [
            ffmpeg_bin, "-y", "-i", str(video_path),
            "-vf", f"scale={w}:{h}",
            "-vframes", "180",  # Limit to 180 frames for swift testing
            str(target / "frame_%04d.bmp")
        ]
        print(f"[CMD] {' '.join(cmd)}")
        res = subprocess.run(cmd)
        if res.returncode == 0:
            count = len(list(target.glob("*.bmp")))
            print(f"[SUCCESS] Extracted {count} frames via ffmpeg into Slot {slot}!")
            return
        else:
            print(f"[WARNING] ffmpeg execution returned code {res.returncode}")

    print("[NOTICE] 'ffmpeg' is not found in system PATH.")
    print("         Options to import video without ffmpeg:")
    print("         1. Convert your clip to an animated .gif (e.g. via online converter) and run:")
    print(f"            python3 scripts/load_video.py my_video.gif {slot}")
    print("         2. Export frames as a folder of PNG/BMP images and run:")
    print(f"            python3 scripts/load_video.py path/to/frames_folder/ {slot}")
    print("         3. Generate a demo animation with:")
    print(f"            python3 scripts/load_video.py --demo {slot}")

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)

    # Flags
    if sys.argv[1] == "--demo":
        slot = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        generate_demo_video(slot)
        return

    if sys.argv[1] == "--clear":
        slot = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        clear_slot(slot)
        return

    input_path = Path(sys.argv[1])
    slot = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] in ["1", "2"] else 1
    res_str = "480p"
    if "--res" in sys.argv:
        idx = sys.argv.index("--res")
        if idx + 1 < len(sys.argv):
            res_str = sys.argv[idx + 1]

    target_res = RESOLUTIONS.get(res_str, (640, 480))

    if not input_path.exists():
        print(f"[ERROR] Input path does not exist: {input_path}")
        sys.exit(1)

    if input_path.is_dir():
        process_image_dir(input_path, slot, target_res)
    elif input_path.suffix.lower() == ".gif":
        process_gif(input_path, slot, target_res)
    elif input_path.suffix.lower() in [".mp4", ".mov", ".avi", ".mkv", ".webm"]:
        process_video_file(input_path, slot, target_res)
    elif input_path.suffix.lower() in [".png", ".jpg", ".jpeg", ".bmp", ".webp"]:
        # Single image
        target = ensure_slot_dir(slot)
        clear_slot(slot)
        im = Image.open(input_path).resize(target_res, Image.Resampling.LANCZOS)
        out_path = target / "frame_0000.ppm"
        save_frame_ppm(im, out_path)
        print(f"[SUCCESS] Installed single-frame custom image in Slot {slot} ({target})")
    else:
        print(f"[ERROR] Unsupported file format: {input_path.suffix}")

if __name__ == "__main__":
    main()
