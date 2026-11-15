#!/usr/bin/env python3
"""Buduje aplikację Nora (nora/ → obs-game-overlay/nora/): Nora.exe + biblioteki WebView2.
Wymaga .NET SDK (dotnet). Na Linuksie też działa (cel: .NET Framework 4.8, x64).
Użycie: python3 tools/build-nora.py"""
import pathlib, shutil, subprocess, sys, tempfile
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'obs-game-overlay' / 'nora'
KEEP = ['Nora.exe', 'Nora.exe.config', 'Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.WinForms.dll', 'WebView2Loader.dll']
with tempfile.TemporaryDirectory() as tmp:
    r = subprocess.run(['dotnet', 'build', str(ROOT / 'nora' / 'Nora.csproj'), '-c', 'Release', '-o', tmp, '-nologo', '-v', 'q'], capture_output=True, text=True)
    print(r.stdout[-3000:]); print(r.stderr[-2000:])
    if r.returncode: sys.exit(r.returncode)
    t = pathlib.Path(tmp)
    for name in KEEP:
        src = t / name
        if not src.exists():
            alt = list(t.rglob(name))
            if not alt: sys.exit(f'brak {name} w wyniku budowania')
            src = alt[0]
        shutil.copy2(src, OUT / name)
        print('→', name, src.stat().st_size, 'B')
