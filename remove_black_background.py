#!/usr/bin/env python3
"""
Remove black background from animation frames using smart color keying.
Detects background color and makes it transparent.
"""
from PIL import Image
import numpy as np
from pathlib import Path

def remove_background(img_array):
    """
    Remove black/dark background from image using color similarity.
    Preserves dark areas that are part of the subject.
    """
    # Get the corner pixels to determine background color
    h, w = img_array.shape[:2]
    corners = [
        img_array[0, 0],
        img_array[0, -1],
        img_array[-1, 0],
        img_array[-1, -1]
    ]
    bg_color = np.mean(corners, axis=0)[:3]
    
    # Calculate color distance from background for each pixel
    rgb = img_array[:, :, :3].astype(float)
    bg_distance = np.sqrt(np.sum((rgb - bg_color) ** 2, axis=2))
    
    # Create alpha channel based on distance from background
    # Threshold: pixels similar to background become transparent
    threshold = 30  # Adjust this if needed
    alpha = np.zeros((h, w), dtype=np.uint8)
    alpha[bg_distance > threshold] = 255
    
    # Smooth edges using gradient
    edge_range = 20
    for dist in range(threshold, threshold + edge_range):
        mask = (bg_distance > dist) & (bg_distance <= dist + 1)
        alpha_value = int(255 * (dist - threshold) / edge_range)
        alpha[mask] = alpha_value
    
    # Create RGBA image
    rgba = np.dstack((img_array[:, :, :3], alpha))
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
        
        # Remove background
        rgba_array = remove_background(img_array)
        
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
    
    for dir_name in dirs:
        process_frames(base_dir / dir_name)
    
    print(f"\n{'='*60}")
    print("🎉 All backgrounds removed! Kai is now transparent!")
