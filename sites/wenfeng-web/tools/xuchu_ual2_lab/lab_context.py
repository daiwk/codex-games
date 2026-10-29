"""Read-only inputs and one guarded output root shared by offline lab stages."""
from pathlib import Path
import hashlib
import json
import os

TOOLS = Path(__file__).resolve().parents[1]
WEB = TOOLS.parent
REPO = WEB.parents[1]
EXPECTED_TARGET = "89f369ccbfce8b5ecd4735ed5f4a18467d23ca4dfc9ec684f51b9c7c30dad43c"
EXPECTED_SOURCE = "8cee20ab1bc55130092447e810e26df22dd2803eccc54f52137a7d54d7ab88a8"

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def validate_output(output):
    output = Path(output).expanduser().resolve()
    if output == Path("/") or output.is_relative_to(REPO):
        raise ValueError("Lab output must be outside the repository; formal GLBs are read-only.")
    if output.exists() and any(p.is_symlink() for p in output.rglob("*")):
        raise ValueError("Lab outputs cannot contain symlinks.")
    return output

_context_path = os.environ.get("WENFENG_UAL2_LAB_CONTEXT")
if not _context_path:
    raise RuntimeError("Run prepare_xuchu_ual2_lab.py; do not invoke internal stages directly.")
_context = json.loads(Path(_context_path).read_text())
OUTPUT = validate_output(_context["output_dir"])
SOURCE = Path(_context["source_glb"]).resolve()
TARGET = Path(_context["baseline_glb"]).resolve()
MANIFEST = Path(_context["manifest"]).resolve()
if SOURCE.is_relative_to(OUTPUT) or TARGET.is_relative_to(OUTPUT) or MANIFEST.is_relative_to(OUTPUT):
    raise ValueError("Inputs cannot be inside the output directory.")
if sha(TARGET) != EXPECTED_TARGET or sha(SOURCE) != EXPECTED_SOURCE:
    raise ValueError("Source/baseline hash changed; this experiment refuses an unreviewed baseline.")
if json.loads(MANIFEST.read_text())["xuchu"]["runtime_sha256"] != EXPECTED_TARGET:
    raise ValueError("Manifest Xu baseline does not match the frozen source model.")
