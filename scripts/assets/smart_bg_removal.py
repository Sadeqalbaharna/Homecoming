#!/usr/bin/env python3
"""
Smart background removal that preserves the subject (Kai).
Uses edge detection and flood fill to identify background vs subject.
"""
from PIL import Image, ImageFilter
import numpy as np
from pathlib import Path
from scipy import ndimage

def remove_background_smart(img_array):
    """
    Remove background using flood fill from edges.
    This preserves dark areas that are part of the subject.
    """
    h, w = img_array.shape[:2]
    
    # Convert to grayscale for edge detection
    if len(img_array.shape) == 3:
        gray = np.mean(img_array[:, :, :3], axis=2)
    else:
        gray = img_array
    
    # Create background mask using flood fill from corners
    background_mask = np.zeros((h, w), dtype=bool)
    
    # Flood fill from all four corners
    # This identifies connected regions that are similar to corner colors
    tolerance = 40  # Color similarity threshold
    
    def flood_fill(start_y, start_x):
        """Flood fill from a starting point."""
        if background_mask[start_y, start_x]:
            return
        
        seed_color = img_array[start_y, start_x, :3]
        stack = [(start_y, start_x)]
        
        while stack:
            y, x = stack.pop()
            if y < 0 or y >= h or x < 0 or x >= w:
                continue
            if background_mask[y, x]:
                continue
            
            pixel_color = img_array[y, x, :3]
            color_diff = np.sqrt(np.sum((pixel_color - seed_color) ** 2))
            
            if color_diff <= tolerance:
                background_mask[y, x] = True
                # Add neighbors
                for dy, dx in [(-1,0), (1,0), (0,-1), (0,1)]:
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and not background_mask[ny, nx]:
                        stack.append((ny, nx))
    
    # Start flood fill from corners
    corners = [(0, 0), (0, w-1), (h-1, 0), (h-1, w-1)]
    for y, x in corners:
        flood_fill(y, x)
    
    # Also fill from edges (top, bottom, left, right)
    for x in range(0, w, 10):
        if not background_mask[0, x]:
            flood_fill(0, x)
        if not background_mask[h-1, x]:
            flood_fill(h-1, x)
    for y in range(0, h, 10):
        if not background_mask[y, 0]:
            flood_fill(y, 0)
        if not background_mask[y, w-1]:
            flood_fill(y, w-1)
    
    # Create alpha channel
    alpha = np.ones((h, w), dtype=np.uint8) * 255
    alpha[background_mask] = 0
    
    # Smooth edges with morphological operations
    alpha = ndimage.binary_erosion(alpha, iterations=1).astype(np.uint8) * 255
    alpha = ndimage.gaussian_filter(alpha.astype(float), sigma=1.0)
    alpha = np.clip(alpha, 0, 255).astype(np.uint8)
    
    # Create RGBA
    rgba = np.dstack((img_array[:, :, :3], alpha))
    return rgba

def process_frames(frame_dir):
    """Process all frames in a directory."""
    frame_path = Path(frame_dir)
    frames = sorted(frame_path.glob('frame_*.png'))
    total = len(frames)
    
    print(f"\n{'='*60}")
    print(f"📁 Processing {total} frames in {frame_dir}")
    
    for i, frame_file in enumerate(frames):
        img = Image.open(frame_file)
        img_array = np.array(img)
        
        # Remove background smartly
        rgba_array = remove_background_smart(img_array)
        
        # Save with transparency
        result = Image.fromarray(rgba_array.astype(np.uint8), 'RGBA')
        result.save(frame_file, 'PNG', optimize=True, compress_level=9)
        
        if (i + 1) % 20 == 0 or i == total - 1:
            print(f"  Progress: {i+1}/{total} frames ({(i+1)/total*100:.1f}%)")
    
    print(f"✅ Completed!")

if __name__ == '__main__':
    base_dir = Path('assets/avatar')
    
    # Process all animation directories
    dirs = ['idle_frames', 'attention_frames', 'thinking_frames', 'speaking_frames']
    
    for dir_name in dirs:
        process_frames(base_dir / dir_name)
    
    print(f"\n{'='*60}")
    print("🎉 Smart background removal complete!")
