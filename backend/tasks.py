import os
import subprocess
from celery import Celery, current_task
import config

celery = Celery(
    'blender_render',
    broker=config.CELERY_BROKER_URL,
    backend=config.CELERY_RESULT_BACKEND
)


@celery.task(bind=True, name='tasks.render_blend_file')
def render_blend_file(self, blend_file_path, job_id, output_format,
                      samples=None, resolution_x=None, resolution_y=None,
                      frame_start=None, frame_end=None):
    """
    Celery task to render a Blender file
    """
    try:
        # Update task state to PROGRESS
        self.update_state(state='PROGRESS', meta={'status': 'Starting render...', 'progress': 0})

        # Create output directory
        output_dir = os.path.join(config.RENDER_FOLDER, job_id)
        os.makedirs(output_dir, exist_ok=True)

        # Set defaults
        samples = samples or config.DEFAULT_SAMPLES
        resolution_x = resolution_x or config.DEFAULT_RESOLUTION_X
        resolution_y = resolution_y or config.DEFAULT_RESOLUTION_Y

        
        format_map = {
            'PNG': 'png',
            'JPEG': 'jpg',
            'OPEN_EXR': 'exr',
            'FFMPEG': 'mp4'
        }

        file_ext = format_map.get(output_format, 'png')

        # For animations, use frame number pattern (except for video formats)
        if frame_start is not None and frame_end is not None and output_format != 'FFMPEG':
            # Image sequence for animations
            output_path = os.path.join(output_dir, f'frame_####.{file_ext}')
        else:
            # Single file for stills or video
            output_path = os.path.join(output_dir, f'render.{file_ext}')

        # Build Blender command
        render_script = os.path.join(os.path.dirname(__file__), 'render_script.py')

        cmd = [
            config.BLENDER_PATH,
            '-b',  # Background mode
            blend_file_path,
            '-P', render_script,  # Run Python script
            '--',
            '--output', output_path,
            '--format', output_format,
            '--samples', str(samples),
            '--resolution-x', str(resolution_x),
            '--resolution-y', str(resolution_y),
            '--gpu-type', config.GPU_TYPE
        ]

        if config.USE_GPU:
            cmd.extend(['--use-gpu'])

        if frame_start is not None:
            cmd.extend(['--frame-start', str(frame_start)])

        if frame_end is not None:
            cmd.extend(['--frame-end', str(frame_end)])

        # Execute Blender render
        self.update_state(state='PROGRESS', meta={'status': 'Rendering...', 'progress': 10})

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # Combine stderr with stdout
            universal_newlines=True
        )

        # Monitor progress
        output_lines = []
        total_frames = (frame_end - frame_start + 1) if frame_end and frame_start else 1
        import time
        start_time = time.time()
        frame_times = []
        
        for line in process.stdout:
            print(line.strip())  # Log output
            output_lines.append(line.strip())

            # Parse Blender output for detailed progress
            if 'Fra:' in line:  # Frame rendering indicator
                # Extract frame number from output like "Fra:123 Mem:..."
                try:
                    import re
                    frame_match = re.search(r'Fra:(\d+)', line)
                    if frame_match:
                        current_frame = int(frame_match.group(1))
                        if frame_start:
                            frames_done = current_frame - frame_start + 1
                            progress = min(int((frames_done / total_frames) * 90), 90)
                            
                            # Calculate ETA for animations
                            eta_text = ""
                            if frames_done > 0:
                                elapsed = time.time() - start_time
                                avg_time_per_frame = elapsed / frames_done
                                remaining_frames = total_frames - frames_done
                                eta_seconds = remaining_frames * avg_time_per_frame
                                
                                if eta_seconds > 60:
                                    eta_minutes = int(eta_seconds / 60)
                                    eta_text = f" - ETA: {eta_minutes}m {int(eta_seconds % 60)}s"
                                else:
                                    eta_text = f" - ETA: {int(eta_seconds)}s"
                            
                            self.update_state(state='PROGRESS', meta={
                                'status': f'Rendering frame {current_frame}/{frame_end or current_frame}{eta_text}',
                                'progress': progress,
                                'current_frame': current_frame,
                                'total_frames': frame_end or current_frame
                            })
                        else:
                            self.update_state(state='PROGRESS', meta={'status': f'Rendering...', 'progress': 50})
                except:
                    pass
            elif 'Saved:' in line:  # File saved indicator
                self.update_state(state='PROGRESS', meta={'status': 'Finalizing...', 'progress': 95})
            elif 'Sample' in line and '/' in line:  # Sample progress for single frame
                # Parse "Sample 32/128" type messages
                try:
                    import re
                    sample_match = re.search(r'Sample (\d+)/(\d+)', line)
                    if sample_match and not frame_end:  # Only for single frames
                        current_sample = int(sample_match.group(1))
                        total_samples = int(sample_match.group(2))
                        progress = int((current_sample / total_samples) * 90)
                        self.update_state(state='PROGRESS', meta={
                            'status': f'Sampling {current_sample}/{total_samples}',
                            'progress': progress
                        })
                except:
                    pass

        process.wait()

        if process.returncode != 0:
            full_output = '\n'.join(output_lines)
            raise Exception(f'Blender render failed with code {process.returncode}:\n{full_output}')

        # Clean up uploaded file
        if os.path.exists(blend_file_path):
            os.remove(blend_file_path)

        # Get output files
        output_files = [f for f in os.listdir(output_dir) if not f.startswith('.')]

        return {
            'job_id': job_id,
            'status': 'completed',
            'output_files': output_files,
            'output_dir': output_dir
        }

    except Exception as e:
        # Clean up on error
        if os.path.exists(blend_file_path):
            os.remove(blend_file_path)

        raise e
