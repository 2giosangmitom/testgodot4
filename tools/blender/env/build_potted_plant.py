"""Build potted_plant.glb (see build_pieces.py for the piece description)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_pieces  # noqa: E402

build_pieces.PIECES["potted_plant"]().export()
