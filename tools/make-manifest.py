#!/usr/bin/env python3
"""Spis plików instalacji (obs-game-overlay/manifest.json): ścieżka → SHA-256.
Kreator startu (launcher) sprawdza nim, czy wszystkie pliki są na miejscu i nieuszkodzone.
Pliki tekstowe liczone bez znaków CR i BOM – tak samo jak Get-VMHash w update.ps1.
Użycie: python3 tools/make-manifest.py         (zapisuje)
        python3 tools/make-manifest.py --check (kod 1, gdy spis jest nieaktualny)"""
import hashlib, json, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / 'obs-game-overlay'
TEXT = {'.ps1', '.bat', '.vbs', '.html', '.js', '.css', '.json', '.md', '.txt', '.svg', '.tsv', '.xml'}

def digest(p):
    b = p.read_bytes()
    if p.suffix.lower() in TEXT:
        b = b.decode('utf-8').lstrip('﻿').replace('\r', '').encode('utf-8')
    return hashlib.sha256(b).hexdigest()

def build():
    out = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', 'obs-game-overlay'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    files = {}
    for line in sorted(set(out.split('\n'))):
        if not line:
            continue
        p = ROOT / line
        rel = p.relative_to(APP).as_posix()
        if rel == 'manifest.json' or not p.is_file():
            continue
        files[rel] = digest(p)
    ver = json.loads((APP / 'version.json').read_text(encoding='utf-8'))['version']
    return {'version': ver, 'files': files}

if __name__ == '__main__':
    m = build()
    text = json.dumps(m, ensure_ascii=False, indent=1) + '\n'
    target = APP / 'manifest.json'
    if '--check' in sys.argv:
        ok = target.exists() and target.read_text(encoding='utf-8') == text
        print('manifest: OK' if ok else 'manifest: nieaktualny – uruchom python3 tools/make-manifest.py')
        sys.exit(0 if ok else 1)
    target.write_text(text, encoding='utf-8')
    print(f'manifest: {len(m["files"])} plików, wersja {m["version"]}')
