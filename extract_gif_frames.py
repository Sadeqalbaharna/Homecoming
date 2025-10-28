#!/usr/bin/env python3
"""
Extract frames from an animated GIF and save them as individual PNG files.
This allows using them in a Flutter AnimationController instead of the gif package.
"""

from PIL import Image
import os

def extract_gif_frames(gif_path, output_dir):
    """Extract all frames from a GIF and save as PNGs."""
    
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Open the GIF
    gif = Image.open(gif_path)
    
    frame_count = 0
    durations = []
    
    try:
        while True:
            # Save current frame
            frame_path = os.path.join(output_dir, f'frame_{frame_count:04d}.png')
            
            # Convert RGBA if needed
            if gif.mode != 'RGBA':
                frame = gif.convert('RGBA')
            else:
                frame = gif.copy()
            
            frame.save(frame_path, 'PNG')
            
            # Get frame duration (in milliseconds)
            duration = gif.info.get('duration', 100)
            durations.append(duration)
            
            print(f"Extracted frame {frame_count}: {frame_path} (duration: {duration}ms)")
            
            frame_count += 1
            gif.seek(gif.tell() + 1)
            
    except EOFError:
        pass  # End of frames
    
    print(f"\nTotal frames extracted: {frame_count}")
    print(f"Average frame duration: {sum(durations) / len(durations):.2f}ms")
    print(f"Total animation duration: {sum(durations)}ms")
    
    return frame_count, durations

if __name__ == '__main__':
    gif_path = r'assets\avatar\idle.gif'
    output_dir = r'assets\avatar\idle_frames'
    
    if not os.path.exists(gif_path):
        print(f"Error: GIF file not found at {gif_path}")
        exit(1)
    
    frame_count, durations = extract_gif_frames(gif_path, output_dir)
    
    print(f"\n✓ Done! Use these {frame_count} frames in your Flutter app.")
    print(f"Output directory: {output_dir}")
