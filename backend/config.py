import os

# Flask Configuration
SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')
UPLOAD_FOLDER = os.path.join(os.path.dirname(__file__), 'uploads')
RENDER_FOLDER = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'rendered')
MAX_CONTENT_LENGTH = 50 * 1024 * 1024 * 1024  # 50GB max file size
ALLOWED_EXTENSIONS = {'blend', 'zip', 'rar'}

# Celery Configuration
CELERY_BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://localhost:6379/0')
CELERY_RESULT_BACKEND = os.environ.get('CELERY_RESULT_BACKEND', 'redis://localhost:6379/0')

# Blender Configuration
BLENDER_PATH = os.environ.get('BLENDER_PATH', '/home/mason/BlenderRenderFarm-main/blender-5.0.0-linux-x64/blender')  # Path to Blender 5.0 with CUDA support
USE_GPU = True  # Enable NVIDIA GPU rendering
GPU_TYPE = 'OPTIX'  # CUDA or OPTIX (OPTIX is faster on RTX cards)

# Render Configuration
DEFAULT_SAMPLES = 128
DEFAULT_RESOLUTION_X = 1920
DEFAULT_RESOLUTION_Y = 1080
SUPPORTED_FORMATS = ['PNG', 'JPEG', 'OPEN_EXR', 'FFMPEG']  # FFMPEG for video

# Create directories if they don't exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(RENDER_FOLDER, exist_ok=True)
