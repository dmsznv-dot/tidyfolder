#!/usr/bin/env python3
"""Package already-sized PNG representations in an ICNS container.

Used when managed macOS environments cannot access iconutil's image encoder.
This changes the container only; sips supplies the image representations.
"""
import pathlib
import struct
import sys

iconset, output = map(pathlib.Path, sys.argv[1:])
representations = [
    ('icp4', 16, 'icon_16x16.png'),
    ('ic11', 32, 'icon_16x16@2x.png'),
    ('icp5', 32, 'icon_32x32.png'),
    ('ic12', 64, 'icon_32x32@2x.png'),
    ('ic07', 128, 'icon_128x128.png'),
    ('ic13', 256, 'icon_128x128@2x.png'),
    ('ic08', 256, 'icon_256x256.png'),
    ('ic14', 512, 'icon_256x256@2x.png'),
    ('ic09', 512, 'icon_512x512.png'),
    ('ic10', 1024, 'icon_512x512@2x.png'),
]
chunks = []
for code, size, name in representations:
    data = (iconset / name).read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (size, size):
        raise SystemExit('Invalid icon representation: ' + name)
    chunks.append(struct.pack('>4sI', code.encode('ascii'), len(data) + 8) + data)
payload = b''.join(chunks)
output.write_bytes(struct.pack('>4sI', b'icns', len(payload) + 8) + payload)
