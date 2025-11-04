#!/usr/bin/env python3
"""
AI-powered background removal using rembg.
This uses machine learning to intelligently separate subject from background.
"""
from rembg import remove
from PIL import Image
from pathlib import Path

def process_frames(frame_dir):
    """Process all frames using AI background removal."""
    frame_path = Path(frame_dir)
    frames = sorted(frame_path.glob('frame_*.png'))
    total = len(frames)
    
    print(f"\n{'='*60}")
    print(f"📁 Processing {total} frames in {frame_dir}")
    
    for i, frame_file in enumerate(frames):
        # Read image
        img = Image.open(frame_file)
        
        # Remove background using AI
        output = remove(img)
        
        # Save with transparency
        output.save(frame_file, 'PNG', optimize=True, compress_level=9)
        
        if (i + 1) % 10 == 0 or i == total - 1:
            print(f"  Progress: {i+1}/{total} frames ({(i+1)/total*100:.1f}%)")
    
    print(f"✅ Completed!")

if __name__ == '__main__':
    base_dir = Path('assets/avatar')
    
    # Restore frames first
    print("First, restoring original frames...")
    import subprocess
    subprocess.run(['git', 'checkout', 'HEAD~2', '--', 
                    'assets/avatar/idle_frames',
                    'assets/avatar/attention_frames', 
                    'assets/avatar/thinking_frames',
                    'assets/avatar/speaking_frames'])
    
    # Process all animation directories
    dirs = ['idle_frames', 'attention_frames', 'thinking_frames', 'speaking_frames']
    
    for dir_name in dirs:
        process_frames(base_dir / dir_name)
    
    print(f"\n{'='*60}")
    print("🎉 AI background removal complete! Kai preserved perfectly!")
