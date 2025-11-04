#!/usr/bin/env python3
"""
Re-extract frames from GIFs and make backgrounds transparent using chroma key.
Only targets the specific black background color, not Kai's features.
"""
from PIL import Image
import numpy as np
from pathlib import Path

def extract_and_remove_bg(gif_path, output_dir, target_width=200):
    """Extract GIF frames and remove black background using precise color matching."""
    gif = Image.open(gif_path)
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    print(f"\nProcessing {gif_path.name} ({gif.n_frames} frames)")
    
    total_size = 0
    
    for i in range(gif.n_frames):
        gif.seek(i)
        frame = gif.convert('RGBA')
        
        # Get numpy array
        arr = np.array(frame)
        rgb = arr[:, :, :3]
        
        # Sample corner pixels to get exact background color
        corners = [
            rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1],
            rgb[5, 5], rgb[5, -5], rgb[-5, 5], rgb[-5, -5]  # Sample deeper
        ]
        bg_color = np.median(corners, axis=0).astype(int)
        
        print(f"  Frame {i}: Background color detected as RGB{tuple(bg_color)}")
        
        # Only remove pixels that EXACTLY match background (or very close)
        # This preserves Kai's dark features
        color_diff = np.abs(rgb.astype(int) - bg_color).sum(axis=2)
        
        # Very tight threshold - only pure background
        threshold = 10  # Only remove if RGB values are within 10 of background
        is_background = color_diff <= threshold
        
        # Create alpha channel
        alpha = np.ones(rgb.shape[:2], dtype=np.uint8) * 255
        alpha[is_background] = 0
        
        # Resize
        aspect = frame.height / frame.width
        new_height = int(target_width * aspect)
        
        rgba = np.dstack((rgb, alpha))
        img_rgba = Image.fromarray(rgba.astype(np.uint8), 'RGBA')
        img_resized = img_rgba.resize((target_width, new_height), Image.Resampling.LANCZOS)
        
        # Save
        output_file = output_path / f'frame_{i:04d}.png'
        img_resized.save(output_file, 'PNG', optimize=True, compress_level=9)
        total_size += output_file.stat().st_size
        
        if (i + 1) % 20 == 0 or i == gif.n_frames - 1:
            print(f"  Progress: {i+1}/{gif.n_frames} ({(i+1)/gif.n_frames*100:.1f}%)")
    
    print(f"Done! Total size: {total_size/1024/1024:.1f}MB")

if __name__ == '__main__':
    base_dir = Path('assets/avatar')
    
    gifs = [
        ('idle.gif', 'idle_frames'),
        ('kai_attention.gif', 'attention_frames'),
        ('kai_thinking.gif', 'thinking_frames'),
        ('kai_speaking.gif', 'speaking_frames'),
    ]
    
    print("="*60)
    print("Re-extracting frames with conservative background removal")
    print("Only removes exact background color, preserves Kai's features")
    print("="*60)
    
    for gif_name, frame_dir in gifs:
        extract_and_remove_bg(base_dir / gif_name, base_dir / frame_dir)
    
    print(f"\n{'='*60}")
    print("All frames re-extracted with Kai's features preserved!")
