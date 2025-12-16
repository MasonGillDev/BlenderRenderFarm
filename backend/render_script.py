import bpy
import sys
import os
import argparse
import traceback

def main():
    """
    Blender Python script to configure and execute rendering with GPU support
    """
    # Parse arguments after '--'
    argv = sys.argv
    if '--' in argv:
        argv = argv[argv.index('--') + 1:]
    else:
        argv = []

    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=str, required=True)
    parser.add_argument('--format', type=str, default='PNG')
    parser.add_argument('--samples', type=int, default=128)
    parser.add_argument('--resolution-x', type=int, default=1920)
    parser.add_argument('--resolution-y', type=int, default=1080)
    parser.add_argument('--use-gpu', action='store_true')
    parser.add_argument('--gpu-type', type=str, default='CUDA', choices=['CUDA', 'OPTIX', 'METAL'])
    parser.add_argument('--frame-start', type=int, default=None)
    parser.add_argument('--frame-end', type=int, default=None)

    args = parser.parse_args(argv)

    # Get scene
    scene = bpy.context.scene
    
    # Fix missing textures by trying to find them relative to the blend file
    blend_dir = os.path.dirname(bpy.data.filepath)
    print(f"Blend file directory: {blend_dir}")
    
    # For ZIP extractions, textures might be in parent or same directory
    # Check both the blend file directory and parent directory
    search_dirs = [blend_dir]
    if '_extracted' in blend_dir:
        # This is from a ZIP extraction, also check parent
        search_dirs.append(os.path.dirname(blend_dir))
    
    # Attempt to fix missing textures
    missing_textures = []
    fixed_textures = []
    
    for img in bpy.data.images:
        if img.source == 'FILE' and img.filepath:
            current_path = bpy.path.abspath(img.filepath)
            if not os.path.exists(current_path):
                texture_name = os.path.basename(img.filepath)
                found = False
                
                # Try each search directory
                for search_dir in search_dirs:
                    possible_path = os.path.join(search_dir, texture_name)
                    if os.path.exists(possible_path):
                        img.filepath = possible_path
                        fixed_textures.append(texture_name)
                        found = True
                        break
                
                if not found:
                    missing_textures.append(texture_name)
    
    if fixed_textures:
        print(f"Fixed {len(fixed_textures)} texture paths: {', '.join(fixed_textures)}")
    
    if missing_textures:
        print(f"Warning: {len(missing_textures)} missing textures: {', '.join(missing_textures)}")

    # Configure GPU rendering if requested
    if args.use_gpu:
        # Enable GPU rendering
        cycles_prefs = bpy.context.preferences.addons['cycles'].preferences
        
        # Force CUDA initialization
        cycles_prefs.compute_device_type = 'NONE'
        cycles_prefs.get_devices()
        
        # Now set to CUDA
        cycles_prefs.compute_device_type = 'CUDA'
        
        # Important: Call get_devices() to refresh after changing compute_device_type
        cycles_prefs.get_devices()
        
        print(f"Compute device type set to: {cycles_prefs.compute_device_type}")
        
        # List all available devices
        print("Available devices after CUDA init:")
        for device in cycles_prefs.devices:
            print(f"  - {device.name} (Type: {device.type}, ID: {device.id})")
        
        # Enable GPU devices
        device_found = False
        for device in cycles_prefs.devices:
            if device.type == 'CUDA':
                device.use = True
                device_found = True
                print(f"Enabled CUDA device: {device.name}")
            elif device.type == 'CPU':
                device.use = False  # Disable CPU when using GPU
        
        if device_found:
            scene.cycles.device = 'GPU'
            print("GPU rendering enabled successfully")
            
            # Try to enable OptiX if requested
            if args.gpu_type == 'OPTIX':
                # In Blender 4.0, OptiX is a feature of Cycles, not a separate device type
                if hasattr(scene.cycles, 'use_optix'):
                    scene.cycles.use_optix = True
                    print("OptiX denoising/acceleration enabled")
                else:
                    print("Note: OptiX not available as separate option in this Blender version")
        else:
            print("WARNING: No CUDA devices found! Falling back to CPU")
            scene.cycles.device = 'CPU'
    else:
        scene.cycles.device = 'CPU'
        print("CPU rendering enabled")

    # Configure render settings
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = args.samples
    scene.render.resolution_x = args.resolution_x
    scene.render.resolution_y = args.resolution_y
    scene.render.resolution_percentage = 100

    # Set output path
    # For video formats, remove frame pattern from filename
    output_path = args.output
    if args.format == 'FFMPEG' and '####' in output_path:
        output_path = output_path.replace('frame_####', 'render')
        output_path = output_path.replace('####', '')
    scene.render.filepath = output_path

    # Configure output format
    # First check if we need to switch from video to image format or vice versa
    current_format = scene.render.image_settings.file_format
    is_video_format = current_format in ['FFMPEG', 'AVI_JPEG', 'AVI_RAW']
    wants_video = args.format == 'FFMPEG'
    
    # If switching between video and image formats, we need to reset first
    if is_video_format and not wants_video:
        # Switching from video to image - set to a neutral image format first
        scene.render.image_settings.file_format = 'PNG'
    elif not is_video_format and wants_video:
        # Switching from image to video
        scene.render.image_settings.file_format = 'FFMPEG'
    
    # Now set the desired format
    if args.format == 'PNG':
        scene.render.image_settings.file_format = 'PNG'
        scene.render.image_settings.color_mode = 'RGBA'
        scene.render.image_settings.compression = 15
    elif args.format == 'JPEG':
        scene.render.image_settings.file_format = 'JPEG'
        scene.render.image_settings.quality = 90
    elif args.format == 'OPEN_EXR':
        scene.render.image_settings.file_format = 'OPEN_EXR'
        scene.render.image_settings.color_depth = '32'
    elif args.format == 'FFMPEG':
        scene.render.image_settings.file_format = 'FFMPEG'
        scene.render.ffmpeg.format = 'MPEG4'
        scene.render.ffmpeg.codec = 'H264'
        scene.render.ffmpeg.constant_rate_factor = 'HIGH'

    # Set frame range for animation
    if args.frame_start is not None:
        scene.frame_start = args.frame_start
    if args.frame_end is not None:
        scene.frame_end = args.frame_end

    # Render
    print(f"Starting render...")
    print(f"Output: {args.output}")
    print(f"Format: {args.format}")
    print(f"Samples: {args.samples}")
    print(f"Resolution: {args.resolution_x}x{args.resolution_y}")
    print(f"Render Device: {scene.cycles.device}")
    print(f"Render Engine: {scene.render.engine}")

    # Ensure we have something to render
    if not scene.camera:
        print("ERROR: No active camera in scene!")
        # Try to find any camera
        cameras = [obj for obj in scene.objects if obj.type == 'CAMERA']
        if cameras:
            scene.camera = cameras[0]
            print(f"Set active camera to: {cameras[0].name}")
        else:
            print("ERROR: No cameras found in scene! Cannot render.")
            sys.exit(1)

    try:
        if args.frame_start is not None and args.frame_end is not None:
            print(f"Animation: frames {args.frame_start} to {args.frame_end}")
            bpy.ops.render.render(animation=True, write_still=True)
        else:
            print(f"Still image")
            bpy.ops.render.render(write_still=True)
        
        print("Render complete!")
        
        # For FFMPEG, Blender might create file with #### in name, fix it
        if args.format == 'FFMPEG' and '####' in args.output:
            wrong_path = args.output  # e.g., /path/frame_####.mp4
            correct_path = args.output.replace('frame_####', 'render').replace('####', '')
            
            # Check if file was created with the wrong name
            if os.path.exists(wrong_path):
                os.rename(wrong_path, correct_path)
                print(f"Renamed video file to: {os.path.basename(correct_path)}")
        
        # Verify output file was created
        expected_path = output_path if args.format == 'FFMPEG' else args.output
        if not os.path.exists(expected_path) and not os.path.exists(args.output.replace('####', '0001')):
            print(f"WARNING: Output file not found at {expected_path}")
            # List what's in the output directory
            output_dir = os.path.dirname(expected_path)
            if os.path.exists(output_dir):
                files = os.listdir(output_dir)
                if files:
                    print(f"Files in output directory: {files}")
                else:
                    print("Output directory is empty!")
    except Exception as e:
        print(f"ERROR during rendering: {str(e)}")
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
