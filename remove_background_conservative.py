#!/usr/bin/env python3
"""
Conservative background removal - only removes pure black background.
Preserves Kai's dark features like eyes, outlines, clothing, etc.
"""
from PIL import Image
import numpy as np
from pathlib import Path

def remove_background_conservative(img_array):
    """
    Remove only pure black background pixels.
    Use flood fill from corners to identify continuous background region.
    """
    h, w = img_array.shape[:2]
    rgb = img_array[:, :, :3]
    
    # Create mask for background (start as all opaque)
    background_mask = np.zeros((h, w), dtype=bool)
    
    # Define "pure black" as very dark pixels (RGB < 15)
    is_dark = np.all(rgb < 15, axis=2)
    
    # Flood fill from all 4 corners to find connected background
    from scipy import ndimage
    
    # Start from corners - they should be background
    seed_points = [
        (0, 0), (0, w-1), (h-1, 0), (h-1, w-1),
        # Add some edge points too
        (0, w//2), (h-1, w//2), (h//2, 0), (h//2, w-1)
    ]
    
    # Label connected dark regions
    labeled, num_features = ndimage.label(is_dark)
    
    # Find which labels touch the corners (these are background)
    background_labels = set()
    for y, x in seed_points:
        if y < h and x < w:
            label = labeled[y, x]
            if label > 0:  # 0 means not dark
                background_labels.add(label)
    
    # Mark all pixels with background labels as transparent
    for label in background_labels:
        background_mask[labeled == label] = True
    
    # Create alpha channel
    alpha = np.ones((h, w), dtype=np.uint8) * 255
    alpha[background_mask] = 0
    
    # Smooth edges slightly (1 pixel feather)
    from scipy.ndimage import binary_dilation
    edge = binary_dilation(background_mask) & ~background_mask
    alpha[edge] = 128  # Semi-transparent edge
    
    # Create RGBA image
    rgba = np.dstack((rgb, alpha))
    return rgba

def process_frames(frame_dir):
    """Process all frames in a directory to remove background."""
    frame_path = Path(frame_dir)
    frames = sorted(frame_path.glob('frame_*.png'))
    total = len(frames)
    
    print(f"\n{'='*60}")
    print(f"📁 Processing {total} frames in {frame_dir}")
    
    total_before = 0
    total_after = 0
    
    for i, frame_file in enumerate(frames):
        # Read frame
        img = Image.open(frame_file)
        original_size = frame_file.stat().st_size
        total_before += original_size
        
        # Convert to numpy array
        img_array = np.array(img)
        
        # Remove background conservatively
        rgba_array = remove_background_conservative(img_array)
        
        # Convert back to PIL Image
        result = Image.fromarray(rgba_array.astype(np.uint8), 'RGBA')
        
        # Save with transparency
        result.save(frame_file, 'PNG', optimize=True, compress_level=9)
        
        new_size = frame_file.stat().st_size
        total_after += new_size
        
        if (i + 1) % 20 == 0 or i == total - 1:
            print(f"  Progress: {i+1}/{total} frames ({(i+1)/total*100:.1f}%)")
    
    print(f"✅ Before: {total_before/1024/1024:.1f}MB, After: {total_after/1024/1024:.1f}MB")

if __name__ == '__main__':
    base_dir = Path('assets/avatar')
    
    # Process all animation directories
    dirs = ['idle_frames', 'attention_frames', 'thinking_frames', 'speaking_frames']
    
    print("⚠️  Conservative mode: Only removes pure black background")
    print("   Preserves Kai's dark features (eyes, outlines, etc)")
    
    for dir_name in dirs:
        process_frames(base_dir / dir_name)
    
    print(f"\n{'='*60}")
    print("🎉 Background removed while preserving Kai's features!")
