#!/usr/bin/env python3
import os, pathlib, plistlib, re, subprocess, sys

def fail(message): raise SystemExit('Release validation: ' + message)
def command(args): return subprocess.run(args, capture_output=True, text=True)

app = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else 'dist/TidyFolder.app')
try: metadata = plistlib.loads((app/'Contents/Info.plist').read_bytes())
except Exception: fail('missing or invalid Info.plist')
if metadata.get('CFBundleIdentifier') != 'io.github.dmsznv-dot.tidyfolder': fail('wrong bundle identifier')
if metadata.get('CFBundleShortVersionString') != os.environ.get('EXPECTED_VERSION','0.1.1'): fail('wrong bundle version')
if metadata.get('LSMinimumSystemVersion') != '14.0': fail('wrong minimum macOS version')
binary = app/'Contents/MacOS/TidyFolder'
if metadata.get('CFBundleExecutable') != 'TidyFolder' or not binary.is_file() or not os.access(binary,os.X_OK): fail('missing executable')
for language in ['en','ru']:
    if not (app/f'Contents/Resources/{language}.lproj/Localizable.strings').is_file(): fail('missing localization ' + language)
icon = app/'Contents/Resources/AppIcon.icns'
if metadata.get('CFBundleIconFile') != 'AppIcon.icns' or not icon.is_file(): fail('missing application icon')
icon_data = icon.read_bytes()
if len(icon_data) < 8 or icon_data[:4] != b'icns' or int.from_bytes(icon_data[4:8], 'big') != len(icon_data): fail('invalid application icon')
arch = command(['lipo','-archs',str(binary)])
expected = os.environ.get('EXPECTED_ARCH','universal')
required = {'arm64','x86_64'} if expected == 'universal' else {expected}
if arch.returncode or not required.issubset(set(arch.stdout.split())): fail('wrong executable architecture: '+arch.stdout.strip())
load = command(['otool','-l',str(binary)])
minimums = re.findall(r'\bminos\s+(\d+\.\d+(?:\.\d+)?)',load.stdout)
if not minimums or any(value not in ['14.0','14.0.0'] for value in minimums): fail('wrong executable minimum deployment target')
verify = command(['codesign','--verify','--deep','--strict',str(app)])
if verify.returncode: fail('invalid signature: ' + verify.stderr.strip())
details = command(['codesign','-dv','--verbose=4',str(app)]).stderr
mode = os.environ.get('SIGNING_MODE','ad-hoc')
if mode not in ['ad-hoc','developer-id']: fail('unknown signing mode')
if mode == 'developer-id' and ('Authority=Developer ID Application:' not in details or 'runtime' not in details): fail('signature lacks Developer ID or hardened runtime')
if mode == 'ad-hoc' and 'Signature=adhoc' not in details: fail('expected ad-hoc signature')
print(f'Validated {metadata["CFBundleShortVersionString"]}, {arch.stdout.strip()}, macOS 14.0+, signing={mode}')
