import os
import uuid
import zipfile
import rarfile
import tempfile
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
from werkzeug.utils import secure_filename
from celery import Celery
import config

app = Flask(__name__)
app.config.from_object(config)
CORS(app)  # Enable CORS for frontend access

# Initialize Celery
celery = Celery(
    app.name,
    broker=app.config['CELERY_BROKER_URL'],
    backend=app.config['CELERY_RESULT_BACKEND']
)
celery.conf.update(app.config)

# Import tasks after Celery is initialized
from tasks import render_blend_file


def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in app.config['ALLOWED_EXTENSIONS']


@app.route('/api/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'message': 'Blender Render API is running'})


@app.route('/api/upload', methods=['POST'])
def upload_file():
    """Handle .blend file upload and initiate rendering"""
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400

    file = request.files['file']

    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400

    if not allowed_file(file.filename):
        return jsonify({'error': 'Invalid file type. Only .blend, .zip, and .rar files are allowed'}), 400

    # Get render parameters from request
    output_format = request.form.get('format', 'PNG')
    samples = int(request.form.get('samples', config.DEFAULT_SAMPLES))
    resolution_x = int(request.form.get('resolution_x', config.DEFAULT_RESOLUTION_X))
    resolution_y = int(request.form.get('resolution_y', config.DEFAULT_RESOLUTION_Y))
    frame_start = request.form.get('frame_start')
    frame_end = request.form.get('frame_end')

    if output_format not in config.SUPPORTED_FORMATS:
        return jsonify({'error': f'Unsupported format. Supported: {config.SUPPORTED_FORMATS}'}), 400

    # Generate unique job ID
    job_id = str(uuid.uuid4())

    # Save uploaded file
    filename = secure_filename(file.filename)
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], f"{job_id}_{filename}")
    file.save(filepath)
    
    # Handle ZIP/RAR files - extract them
    blend_filepath = filepath
    if filename.lower().endswith('.zip') or filename.lower().endswith('.rar'):
        extract_dir = os.path.join(app.config['UPLOAD_FOLDER'], f"{job_id}_extracted")
        os.makedirs(extract_dir, exist_ok=True)
        
        try:
            # Handle ZIP files
            if filename.lower().endswith('.zip'):
                with zipfile.ZipFile(filepath, 'r') as zip_ref:
                    zip_ref.extractall(extract_dir)
            # Handle RAR files
            elif filename.lower().endswith('.rar'):
                with rarfile.RarFile(filepath, 'r') as rar_ref:
                    rar_ref.extractall(extract_dir)
            
            # Find the .blend file in the extracted contents
            blend_files = []
            for root, dirs, files in os.walk(extract_dir):
                for f in files:
                    if f.endswith('.blend'):
                        blend_files.append(os.path.join(root, f))
            
            if not blend_files:
                return jsonify({'error': 'No .blend file found in archive'}), 400
            
            # Use the first .blend file found
            blend_filepath = blend_files[0]
            
            # Clean up the uploaded archive file
            os.remove(filepath)
            
        except zipfile.BadZipFile:
            return jsonify({'error': 'Invalid ZIP file'}), 400
        except rarfile.Error:
            return jsonify({'error': 'Invalid RAR file'}), 400
        except Exception as e:
            return jsonify({'error': f'Error extracting archive: {str(e)}'}), 500

    # Queue render task
    task = render_blend_file.apply_async(
        args=[blend_filepath, job_id, output_format],
        kwargs={
            'samples': samples,
            'resolution_x': resolution_x,
            'resolution_y': resolution_y,
            'frame_start': int(frame_start) if frame_start else None,
            'frame_end': int(frame_end) if frame_end else None
        }
    )

    return jsonify({
        'job_id': job_id,
        'task_id': task.id,
        'message': 'Render job queued successfully',
        'status': 'queued'
    }), 202


@app.route('/api/status/<task_id>', methods=['GET'])
def get_status(task_id):
    """Get render job status"""
    task = celery.AsyncResult(task_id)

    if task.state == 'PENDING':
        response = {
            'state': task.state,
            'status': 'Pending...',
            'progress': 0
        }
    elif task.state == 'PROGRESS':
        response = {
            'state': task.state,
            'status': task.info.get('status', ''),
            'progress': task.info.get('progress', 0)
        }
    elif task.state == 'SUCCESS':
        response = {
            'state': task.state,
            'status': 'Render completed',
            'progress': 100,
            'result': task.info
        }
    else:
        # Something went wrong
        response = {
            'state': task.state,
            'status': str(task.info),  # Exception message
            'progress': 0
        }

    return jsonify(response)


@app.route('/api/download/<job_id>', methods=['GET'])
def download_file(job_id):
    """Download rendered output"""
    render_dir = os.path.join(app.config['RENDER_FOLDER'], job_id)

    if not os.path.exists(render_dir):
        return jsonify({'error': 'Render not found'}), 404

    # Find the output file(s)
    files = [f for f in os.listdir(render_dir) if not f.startswith('.')]

    if not files:
        return jsonify({'error': 'No output files found'}), 404

    # If single file, send it directly
    if len(files) == 1:
        filepath = os.path.join(render_dir, files[0])
        return send_file(filepath, as_attachment=True)

    # If multiple files (animation frames), create a zip
    import zipfile
    from io import BytesIO

    memory_file = BytesIO()
    with zipfile.ZipFile(memory_file, 'w', zipfile.ZIP_DEFLATED) as zf:
        for file in files:
            filepath = os.path.join(render_dir, file)
            zf.write(filepath, file)

    memory_file.seek(0)
    return send_file(
        memory_file,
        mimetype='application/zip',
        as_attachment=True,
        download_name=f'{job_id}_render.zip'
    )


@app.route('/api/jobs', methods=['GET'])
def list_jobs():
    """List all render jobs"""
    jobs = []

    if os.path.exists(app.config['RENDER_FOLDER']):
        for job_id in os.listdir(app.config['RENDER_FOLDER']):
            job_path = os.path.join(app.config['RENDER_FOLDER'], job_id)
            if os.path.isdir(job_path):
                files = [f for f in os.listdir(job_path) if not f.startswith('.')]
                jobs.append({
                    'job_id': job_id,
                    'file_count': len(files),
                    'files': files
                })

    return jsonify({'jobs': jobs})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
