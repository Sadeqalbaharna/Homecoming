"""
AI Frame Interpolation for Kai Animation Transitions

This script uses FILM (Frame Interpolation for Large Motion) to generate
smooth bridging frames between Kai's animation states.

Requirements:
- Python 3.8+
- TensorFlow 2.x
- opencv-python
- numpy

Usage:
    python ai_frame_interpolation.py --start idle_last_frame.png --end attention_first_frame.png --output transition_frames --count 8

Author: Homecoming App
Date: 2024-11-04
"""

import os
import sys
import argparse
from pathlib import Path

try:
    import cv2
    import numpy as np
    print("✅ OpenCV and NumPy installed")
except ImportError:
    print("❌ Missing dependencies. Install with:")
    print("   pip install opencv-python numpy")
    sys.exit(1)

# Check for TensorFlow (optional - will guide user if missing)
try:
    import tensorflow as tf
    import tensorflow_hub as hub
    print(f"✅ TensorFlow {tf.__version__} installed")
    TF_AVAILABLE = True
except ImportError:
    print("⚠️  TensorFlow not installed (needed for ML interpolation)")
    print("   Install with: pip install tensorflow tensorflow-hub")
    TF_AVAILABLE = False


class FrameInterpolator:
    """Handles frame interpolation between animation states"""
    
    def __init__(self, method='film'):
        """
        Initialize interpolator
        
        Args:
            method: 'blend' (simple), 'optical_flow' (advanced), or 'film' (ML-based, best quality)
        """
        self.method = method
        self.model = None
        
        if method == 'film' and TF_AVAILABLE:
            self._load_film_model()
        elif method == 'film' and not TF_AVAILABLE:
            print("⚠️  FILM requires TensorFlow. Falling back to optical_flow")
            self.method = 'optical_flow'
    
    def _load_film_model(self):
        """Load pre-trained FILM model from TensorFlow Hub"""
        print("🔄 Loading FILM model from TensorFlow Hub...")
        print("   (This may take a minute on first run)")
        
        try:
            # Load FILM model from TensorFlow Hub
            model_url = "https://tfhub.dev/google/film/1"
            self.model = hub.load(model_url)
            print("✅ FILM model loaded successfully!")
            print("   This is Google's state-of-the-art frame interpolation model")
        except Exception as e:
            print(f"❌ Failed to load FILM model: {e}")
            print("   Falling back to optical flow method")
            self.method = 'optical_flow'
            self.model = None
    
    def interpolate(self, frame1_path, frame2_path, num_frames=8, output_dir='output'):
        """
        Generate interpolated frames between two images
        
        Args:
            frame1_path: Path to starting frame
            frame2_path: Path to ending frame
            num_frames: Number of in-between frames to generate
            output_dir: Directory to save output frames
        """
        # Load images
        frame1 = cv2.imread(str(frame1_path), cv2.IMREAD_UNCHANGED)
        frame2 = cv2.imread(str(frame2_path), cv2.IMREAD_UNCHANGED)
        
        if frame1 is None or frame2 is None:
            raise ValueError("Could not load one or both frames")
        
        # Ensure both frames have same dimensions
        if frame1.shape != frame2.shape:
            print(f"⚠️  Frame size mismatch: {frame1.shape} vs {frame2.shape}")
            print("   Resizing to match first frame...")
            frame2 = cv2.resize(frame2, (frame1.shape[1], frame1.shape[0]))
        
        # Create output directory
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        
        print(f"\n🎬 Generating {num_frames} interpolated frames...")
        print(f"   Method: {self.method}")
        print(f"   Size: {frame1.shape[1]}x{frame1.shape[0]}")
        
        # Generate frames based on method
        if self.method == 'blend':
            frames = self._interpolate_blend(frame1, frame2, num_frames)
        elif self.method == 'optical_flow':
            frames = self._interpolate_optical_flow(frame1, frame2, num_frames)
        elif self.method == 'film':
            frames = self._interpolate_film(frame1, frame2, num_frames)
        else:
            raise ValueError(f"Unknown method: {self.method}")
        
        # Save frames
        for i, frame in enumerate(frames):
            output_path = Path(output_dir) / f"frame_{i:04d}.png"
            cv2.imwrite(str(output_path), frame)
            print(f"   ✓ Saved: {output_path.name}")
        
        print(f"\n✅ Done! {len(frames)} frames saved to {output_dir}/")
        return frames
    
    def _interpolate_blend(self, frame1, frame2, num_frames):
        """Simple linear blending (alpha compositing)"""
        frames = []
        
        for i in range(num_frames):
            # Calculate blend factor (0 = frame1, 1 = frame2)
            alpha = (i + 1) / (num_frames + 1)
            
            # Blend frames
            blended = cv2.addWeighted(frame1, 1 - alpha, frame2, alpha, 0)
            frames.append(blended)
        
        return frames
    
    def _interpolate_optical_flow(self, frame1, frame2, num_frames):
        """Optical flow-based interpolation (smoother motion)"""
        frames = []
        
        # Convert to grayscale for flow calculation
        gray1 = cv2.cvtColor(frame1, cv2.COLOR_BGRA2GRAY) if frame1.shape[2] == 4 else cv2.cvtColor(frame1, cv2.COLOR_BGR2GRAY)
        gray2 = cv2.cvtColor(frame2, cv2.COLOR_BGRA2GRAY) if frame2.shape[2] == 4 else cv2.cvtColor(frame2, cv2.COLOR_BGR2GRAY)
        
        # Calculate optical flow
        flow = cv2.calcOpticalFlowFarneback(
            gray1, gray2, None,
            pyr_scale=0.5, levels=3, winsize=15,
            iterations=3, poly_n=5, poly_sigma=1.2, flags=0
        )
        
        h, w = flow.shape[:2]
        
        for i in range(num_frames):
            alpha = (i + 1) / (num_frames + 1)
            
            # Create interpolated flow
            flow_scaled = flow * alpha
            
            # Create mesh grid
            flow_map = np.zeros((h, w, 2), dtype=np.float32)
            flow_map[:, :, 0] = np.arange(w)
            flow_map[:, :, 1] = np.arange(h)[:, np.newaxis]
            
            # Apply flow
            flow_map += flow_scaled
            
            # Warp frame1 toward frame2
            warped = cv2.remap(frame1, flow_map, None, cv2.INTER_LINEAR)
            
            # Blend with frame2 for smoother result
            blended = cv2.addWeighted(warped, 1 - alpha * 0.5, frame2, alpha * 0.5, 0)
            
            frames.append(blended)
        
        return frames
    
    def _interpolate_film(self, frame1, frame2, num_frames):
        """ML-based interpolation using FILM model (Best Quality)"""
        if self.model is None:
            print("⚠️  FILM model not loaded, falling back to optical flow")
            return self._interpolate_optical_flow(frame1, frame2, num_frames)
        
        print("   🎬 Using FILM ML model (Google Research)")
        frames = []
        
        try:
            # Prepare images for FILM
            img1 = self._prepare_for_film(frame1)
            img2 = self._prepare_for_film(frame2)
            
            # For simplicity, generate frames one by one at different time steps
            # time=0.0 is frame1, time=1.0 is frame2
            print(f"   🔬 Running FILM inference for {num_frames} frames...")
            
            for i in range(num_frames):
                # Calculate time step (evenly distributed between frames)
                time_step = (i + 1) / (num_frames + 1)
                
                # Use FILM to interpolate at this time step
                # FILM expects time shape (batch_size, 1)
                batch_dt = tf.constant([[time_step]], dtype=tf.float32)
                
                result = self.model({
                    'x0': img1,
                    'x1': img2,
                    'time': batch_dt
                })
                
                interpolated = result['image']
                
                # Convert back to numpy and original format
                film_frame = interpolated.numpy()[0]
                film_frame = (film_frame * 255).astype(np.uint8)
                
                # Convert RGB back to BGRA if original had alpha
                if frame1.shape[2] == 4:
                    # Create alpha channel (full opacity)
                    alpha = np.ones((film_frame.shape[0], film_frame.shape[1], 1), dtype=np.uint8) * 255
                    film_frame = cv2.cvtColor(film_frame, cv2.COLOR_RGB2BGR)
                    film_frame = np.concatenate([film_frame, alpha], axis=2)
                else:
                    film_frame = cv2.cvtColor(film_frame, cv2.COLOR_RGB2BGR)
                
                frames.append(film_frame)
                print(f"   ✓ Generated frame {len(frames)}/{num_frames} (t={time_step:.3f})")
            
            print("   ✅ FILM interpolation complete!")
            
        except Exception as e:
            print(f"   ❌ FILM inference failed: {e}")
            print("   📉 Falling back to optical flow method")
            return self._interpolate_optical_flow(frame1, frame2, num_frames)
        
        return frames
    
    def _prepare_for_film(self, frame):
        """Prepare frame for FILM model input"""
        # Convert BGRA to RGB if needed
        if frame.shape[2] == 4:
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGRA2RGB)
        else:
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
        # Normalize to [0, 1]
        frame_normalized = frame_rgb.astype(np.float32) / 255.0
        
        # Add batch dimension [1, H, W, 3]
        frame_batch = tf.convert_to_tensor(frame_normalized[np.newaxis, ...])
        
        return frame_batch


def batch_process_transitions(animations_dir, output_dir, num_frames=8, method='film'):
    """
    Process all animation transitions in a directory
    
    Expected directory structure:
    animations_dir/
        idle/ or idle_frames/
            frame_0000.png
            frame_0001.png
            ...
        attention/ or attention_frames/
            frame_0000.png
            ...
        thinking/ or thinking_frames/
            ...
        speaking/ or speaking_frames/
            ...
    """
    animations_dir = Path(animations_dir)
    output_dir = Path(output_dir)
    
    # Define animation states and transitions
    state_names = ['idle', 'attention', 'thinking', 'speaking']
    
    # Find actual directories (try with and without _frames suffix)
    state_dirs = {}
    for state in state_names:
        if (animations_dir / state).exists():
            state_dirs[state] = animations_dir / state
        elif (animations_dir / f"{state}_frames").exists():
            state_dirs[state] = animations_dir / f"{state}_frames"
        else:
            print(f"⚠️  Warning: Could not find directory for '{state}' state")
    
    if len(state_dirs) < 2:
        print(f"\n❌ Error: Need at least 2 animation states to create transitions")
        print(f"   Found: {list(state_dirs.keys())}")
        return
    
    # Define transitions based on available states
    transitions = []
    ordered_states = ['idle', 'attention', 'thinking', 'speaking']
    available_ordered = [s for s in ordered_states if s in state_dirs]
    
    # Create transitions in order (state-to-state)
    for i in range(len(available_ordered)):
        start = available_ordered[i]
        end = available_ordered[(i + 1) % len(available_ordered)]
        transitions.append((start, end))
    
    # Add loop transitions (last frame to first frame of same animation)
    for state in available_ordered:
        transitions.append((state, state))  # Loop transition
    
    interpolator = FrameInterpolator(method=method)
    
    print(f"\n🎭 Processing Animation Transitions")
    print(f"   Source: {animations_dir}")
    print(f"   Output: {output_dir}")
    print(f"   Frames per transition: {num_frames}")
    print(f"   Found states: {', '.join(available_ordered)}\n")
    
    for start_state, end_state in transitions:
        # Determine transition type
        is_loop = (start_state == end_state)
        transition_type = "LOOP" if is_loop else "TRANSITION"
        
        print(f"\n{'='*60}")
        print(f"🔄 {transition_type}: {start_state.upper()} → {end_state.upper()}")
        print(f"{'='*60}")
        
        # Get last frame of start state
        start_dir = state_dirs[start_state]
        start_frames = sorted(start_dir.glob('*.png'))
        if not start_frames:
            print(f"⚠️  No PNG frames found in {start_dir}")
            continue
        frame1_path = start_frames[-1]  # Last frame
        print(f"   Start: {frame1_path.name} from {start_dir.name}/")
        
        # Get first frame of end state
        end_dir = state_dirs[end_state]
        end_frames = sorted(end_dir.glob('*.png'))
        if not end_frames:
            print(f"⚠️  No PNG frames found in {end_dir}")
            continue
        frame2_path = end_frames[0]  # First frame
        print(f"   End: {frame2_path.name} from {end_dir.name}/")
        
        # Create transition
        if is_loop:
            transition_output = output_dir / f"{start_state}_loop"
        else:
            transition_output = output_dir / f"{start_state}_to_{end_state}"
        interpolator.interpolate(
            frame1_path,
            frame2_path,
            num_frames=num_frames,
            output_dir=str(transition_output)
        )


def main():
    parser = argparse.ArgumentParser(
        description='AI Frame Interpolation for Kai Animations',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Single transition
  python ai_frame_interpolation.py --start idle_last.png --end attention_first.png --count 8
  
  # Batch process all transitions
  python ai_frame_interpolation.py --batch assets/animations --output transitions --count 12
  
  # Use optical flow method (better quality)
  python ai_frame_interpolation.py --batch assets/animations --method optical_flow
        """
    )
    
    # Single transition mode
    parser.add_argument('--start', type=str, help='Starting frame image path')
    parser.add_argument('--end', type=str, help='Ending frame image path')
    parser.add_argument('--output', type=str, default='output', help='Output directory')
    parser.add_argument('--count', type=int, default=8, help='Number of frames to generate')
    
    # Batch mode
    parser.add_argument('--batch', type=str, help='Batch process directory (contains idle/, attention/, etc.)')
    
    # Method selection
    parser.add_argument('--method', type=str, default='film',
                       choices=['blend', 'optical_flow', 'film'],
                       help='Interpolation method (default: film - best quality)')
    
    args = parser.parse_args()
    
    # Batch mode
    if args.batch:
        batch_process_transitions(
            args.batch,
            args.output,
            num_frames=args.count,
            method=args.method
        )
    # Single transition mode
    elif args.start and args.end:
        interpolator = FrameInterpolator(method=args.method)
        interpolator.interpolate(
            args.start,
            args.end,
            num_frames=args.count,
            output_dir=args.output
        )
    else:
        parser.print_help()
        print("\n❌ Error: Must specify either --batch or both --start and --end")
        sys.exit(1)


if __name__ == '__main__':
    main()
