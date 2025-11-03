#!/usr/bin/env python3
"""
Recompress PNG frames while preserving transparency.
This fixes the black/white background issue.
"""
from PIL import Image
from pathlib import Path

TARGET_WIDTH = 200

def recompress_frames(input_dir):
    """Recompress frames preserving alpha channel."""
    input_path = Path(input_dir)
    frames = sorted(input_path.glob('frame_*.png'))
    total = len(frames)
    
    print(f"📁 Processing {total} frames in {input_dir}")
    
    total_before = 0
    total_after = 0
    
    for i, frame_path in enumerate(frames):
        img = Image.open(frame_path)
        original_size = frame_path.stat().st_size
        total_before += original_size
        
        # Calculate new dimensions maintaining aspect ratio
        aspect = img.height / img.width
        new_width = TARGET_WIDTH
        new_height = int(new_width * aspect)
        
        # Resize with LANCZOS and KEEP RGBA mode
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        img_resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
        
        # Save as RGBA PNG with optimization
        img_resized.save(frame_path, 'PNG', optimize=True, compress_level=9)
        
        new_size = frame_path.stat().st_size
        total_after += new_size
        
        if (i + 1) % 20 == 0 or i == total - 1:
            print(f"  Progress: {i+1}/{total} frames ({(i+1)/total*100:.1f}%)")
    
    print(f"✅ Before: {total_before/1024/1024:.1f}MB, After: {total_after/1024/1024:.1f}MB")
    print(f"   Saved: {(total_before - total_after)/1024/1024:.1f}MB\n")

if __name__ == '__main__':
    base_dir = Path('assets/avatar')
    
    # Recompress all four animation directories with transparency
    dirs = ['idle_frames', 'attention_frames', 'thinking_frames', 'speaking_frames']
    
    for dir_name in dirs:
        print(f"{'='*60}")
        recompress_frames(base_dir / dir_name)
    
    print("🎉 All frames recompressed with transparency!")
