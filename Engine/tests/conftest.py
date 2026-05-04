"""
Shared test fixtures and import-path setup.

Adds Engine/ to sys.path so `import falldetection_v1`, `import main`,
and `import rag_service` resolve when tests run from the repo root.
"""
import sys
from pathlib import Path

ENGINE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ENGINE_DIR))
