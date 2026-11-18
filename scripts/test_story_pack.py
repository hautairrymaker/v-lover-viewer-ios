"""Controlled PCK integrity checks; no game media is loaded."""
import contextlib
import hashlib
import io
import struct
import tempfile
from pathlib import Path
from verify_story_pack import verify


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / "assets"
    source.mkdir()
    (source / "input.json").write_bytes(b"{}")
    name = b"assets/input.json"
    header_size = 100
    entry_size = 4 + len(name) + 8 + 8 + 16 + 4
    offset = header_size + entry_size
    header = b"GDPC" + struct.pack("<5IQ", 2, 4, 4, 1, 0, 0) + bytes(64)
    entry = (struct.pack("<I", len(name)) + name
             + struct.pack("<QQ", offset, 2) + hashlib.md5(b"{}").digest()
             + struct.pack("<I", 0))
    pack = root / "fixture.pck"
    pack.write_bytes(header + struct.pack("<I", 1) + entry + b"{}")
    with contextlib.redirect_stdout(io.StringIO()):
        verify(pack, root)
    passed = 1
    for replacement in (b"[]", b"longer"):
        (source / "input.json").write_bytes(replacement)
        try:
            verify(pack, root)
        except ValueError:
            passed += 1
        else:
            raise AssertionError("Accepted corrupt input")
    (source / "input.json").write_bytes(b"{}")
    (source / "missing.moc3").write_bytes(b"controlled input")
    try:
        verify(pack, root)
    except ValueError:
        passed += 1
    else:
        raise AssertionError("Accepted missing input")
    print(f"{passed}/4 controlled checks passed")
