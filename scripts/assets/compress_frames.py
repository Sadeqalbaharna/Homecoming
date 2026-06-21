#!/usr/bin/env python3
"""
Compress PNG frame sequences to reduce app size.
Reduces quality and resolution while maintaining animation quality.
"""
from PIL import Image
import os
from pathlib import Path

# Configuration
TARGET_WIDTH = 200  # Reduce from original size to 200px width
QUALITY = 75  # JPEG quality (we'll convert PNG to optimized format)
OPTIMIZE_PNG = True

def compress_frames(input_dir, output_dir=None):
    """Compress all PNG frames in a directory."""
    input_path = Path(input_dir)
    output_path = Path(output_dir) if output_dir else input_path
    output_path.mkdir(parents=True, exist_ok=True)
    
    frames = sorted(input_path.glob('frame_*.png'))
    total = len(frames)
    
    print(f"📁 Processing {total} frames in {input_dir}")
    
    total_before = 0
    total_after = 0
    
    for i, frame_path in enumerate(frames):
        # Read original
        img = Image.open(frame_path)
        original_size = frame_path.stat().st_size
        total_before += original_size
        
        # Calculate new dimensions maintaining aspect ratio
        aspect = img.height / img.width
        new_width = TARGET_WIDTH
        new_height = int(new_width * aspect)
        
        # Resize
        img_resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # Convert RGBA to RGB if has alpha
        if img_resized.mode == 'RGBA':
            # Create white background
            background = Image.new('RGB', img_resized.size, (255, 255, 255))
            background.paste(img_resized, mask=img_resized.split()[3])  # Use alpha as mask
            img_resized = background
        
        # Save optimized
        output_file = output_path / frame_path.name
        img_resized.save(output_file, 'PNG', optimize=True, compress_level=9)
        
        new_size = output_file.stat().st_size
        total_after += new_size
        
        if (i + 1) % 20 == 0 or i == total - 1:
            print(f"  Progress: {i+1}/{total} frames ({(i+1)/total*100:.1f}%)")
    
    compression_ratio = (1 - total_after / total_before) * 100
    print(f"✅ Done! Before: {total_before/1024/1024:.1f}MB, After: {total_after/1024/1024:.1f}MB")
    print(f"   Saved: {(total_before - total_after)/1024/1024:.1f}MB ({compression_ratio:.1f}% reduction)")

if __name__ == '__main__':
    base_dir = Path('assets/avatar')
    
    # Compress all three animation directories
    dirs = ['attention_frames', 'thinking_frames', 'speaking_frames']
    
    for dir_name in dirs:
        print(f"\n{'='*60}")
        compress_frames(base_dir / dir_name)
    
    print(f"\n{'='*60}")
    print("🎉 All frames compressed!")
