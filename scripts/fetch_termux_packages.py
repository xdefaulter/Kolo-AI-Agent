#!/usr/bin/env python3
"""Extract Termux .deb packages and repackage as tar.gz for Flutter assets.

Uses .tar.gz instead of .tar.xz because Android's toybox tar supports gzip
natively but does NOT support xz decompression.
"""

import struct
import subprocess
import os
import sys
import tempfile
import urllib.request
import shutil

REPO_URL = "https://packages.termux.dev/apt/termux-main"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUTPUT_DIR = os.environ.get("OUTPUT_DIR", os.path.join(PROJECT_DIR, "assets", "bootstrap"))

WORK_DIR = tempfile.mkdtemp(prefix="termux_bootstrap_")

def cleanup():
    shutil.rmtree(WORK_DIR, ignore_errors=True)

import atexit
atexit.register(cleanup)

def info(msg):
    print(f"[INFO] {msg}", flush=True)

def warn(msg):
    print(f"[WARN] {msg}", flush=True)

def download_package_index():
    """Download and parse the Termux aarch64 Packages index."""
    url = f"{REPO_URL}/dists/stable/main/binary-aarch64/Packages"
    info(f"Downloading package index from {url}...")
    data = urllib.request.urlopen(url).read().decode()
    
    packages = {}
    current = {}
    
    for line in data.split('\n'):
        if line.startswith('Package: '):
            if current.get('name') and current.get('filename'):
                packages[current['name']] = current
            current = {'name': line.split('Package: ', 1)[1].strip()}
        elif line.startswith('Filename: '):
            current['filename'] = line.split('Filename: ', 1)[1].strip()
        elif line.strip() == '':
            if current.get('name') and current.get('filename'):
                packages[current['name']] = current
            current = {}
    
    if current.get('name') and current.get('filename'):
        packages[current['name']] = current
    
    info(f"Found {len(packages)} packages in index")
    return packages

def extract_ar_member(deb_path, member_name):
    """Extract a specific member from an ar archive."""
    with open(deb_path, 'rb') as f:
        magic = f.read(8)
        if magic != b'!<arch>\n':
            raise ValueError(f"Not an ar archive: {deb_path}")
        
        while True:
            header = f.read(60)
            if len(header) < 60:
                break
            
            name = header[0:16].decode('ascii').rstrip()
            size_str = header[48:58].decode('ascii').strip()
            
            if not size_str:
                break
                
            file_size = int(size_str)
            data_size = file_size + (file_size % 2)
            
            # Handle extended names
            if name.startswith('/') and name[1:].isdigit():
                f.read(data_size)
                continue
            
            clean_name = name.rstrip('/')
            
            if clean_name == member_name:
                return f.read(file_size)
            else:
                f.read(data_size)
    
    return None

def extract_deb(deb_path, stage_dir):
    """Extract a .deb file into stage_dir."""
    for suffix in ['xz', 'gz', 'zst']:
        member_name = f'data.tar.{suffix}'
        data = extract_ar_member(deb_path, member_name)
        if data is None:
            continue
        
        tmp_tar = os.path.join(WORK_DIR, f'temp_data.tar.{suffix}')
        with open(tmp_tar, 'wb') as f:
            f.write(data)
        
        try:
            if suffix == 'xz':
                result = subprocess.run(
                    ['sh', '-c', f'xz -dc "{tmp_tar}" | tar xf - -C "{stage_dir}"'],
                    capture_output=True, text=True, timeout=120
                )
            elif suffix == 'gz':
                result = subprocess.run(
                    ['tar', 'xzf', tmp_tar, '-C', stage_dir],
                    capture_output=True, text=True, timeout=120
                )
            elif suffix == 'zst':
                result = subprocess.run(
                    ['sh', '-c', f'zstd -dc "{tmp_tar}" | tar xf - -C "{stage_dir}"'],
                    capture_output=True, text=True, timeout=120
                )
            else:
                continue
            
            if result.returncode == 0:
                os.unlink(tmp_tar)
                return True
            else:
                warn(f"  Extract failed: {result.stderr[:200]}")
        except subprocess.TimeoutExpired:
            warn(f"  Extract timed out for {suffix}")
        finally:
            if os.path.exists(tmp_tar):
                os.unlink(tmp_tar)
    
    return False

def build_package(packages, name, deb_names):
    """Download and extract a group of .deb packages, then repackage."""
    info(f"Packages for {name}: {deb_names}")
    
    stage_dir = os.path.join(WORK_DIR, f'stage_{name}')
    os.makedirs(stage_dir, exist_ok=True)
    
    for deb_name in deb_names:
        if deb_name not in packages:
            warn(f"  '{deb_name}' not found in index — skipping")
            continue
        
        pkg = packages[deb_name]
        deb_url = f"{REPO_URL}/{pkg['filename']}"
        deb_file = os.path.join(WORK_DIR, os.path.basename(pkg['filename']))
        
        info(f"  Downloading {deb_name} ({os.path.basename(pkg['filename'])})...")
        urllib.request.urlretrieve(deb_url, deb_file)
        
        file_mb = os.path.getsize(deb_file) / (1024 * 1024)
        info(f"  Downloaded {file_mb:.1f} MB")
        
        if extract_deb(deb_file, stage_dir):
            info(f"  Extracted OK")
        else:
            warn(f"  Failed to extract {deb_name}")
        
        if os.path.exists(deb_file):
            os.unlink(deb_file)
    
    # Determine source directory
    termux_usr = os.path.join(stage_dir, 'data', 'data', 'com.termux', 'files', 'usr')
    if os.path.isdir(termux_usr):
        source_dir = termux_usr
    else:
        source_dir = stage_dir
    
    # Check if we got anything
    contents = os.listdir(source_dir)
    if not contents:
        warn(f"  No files extracted for {name}!")
        shutil.rmtree(stage_dir, ignore_errors=True)
        return False
    
    # Repackage as tar.gz (gzip — universally supported on Android)
    output_file = os.path.join(OUTPUT_DIR, f'{name}.tar.gz')
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    info(f"  Creating {name}.tar.gz...")
    result = subprocess.run(
        ['tar', 'czf', output_file, '-C', source_dir, '.'],
        capture_output=True, text=True, timeout=600
    )
    
    if result.returncode != 0:
        warn(f"  tar failed: {result.stderr[:200]}")
        shutil.rmtree(stage_dir, ignore_errors=True)
        return False
    
    size_mb = os.path.getsize(output_file) / (1024 * 1024)
    info(f"  ✓ {name}.tar.gz: {size_mb:.1f} MB")
    
    shutil.rmtree(stage_dir, ignore_errors=True)
    return True

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    # Remove old .tar.xz files
    for f in os.listdir(OUTPUT_DIR):
        if f.endswith('.tar.xz'):
            os.unlink(os.path.join(OUTPUT_DIR, f))
            info(f"Removed old {f}")
    
    packages = download_package_index()
    
    # ── Python 3 ──
    info("=" * 50)
    build_package(packages, 'python3', [
        'python', 'python-pip', 'libffi', 'openssl',
        'readline', 'libsqlite', 'zlib', 'libbz2', 'liblzma',
    ])
    
    # ── Node.js ──
    info("=" * 50)
    build_package(packages, 'nodejs', [
        'nodejs', 'nodejs-lts', 'libc++', 'openssl',
    ])
    
    # ── Git ──
    info("=" * 50)
    build_package(packages, 'git', [
        'git', 'libcurl', 'openssl', 'pcre2',
        'zlib', 'libexpat', 'ca-certificates',
    ])
    
    # ── aapt2 ──
    info("=" * 50)
    build_package(packages, 'aapt2', [
        'aapt2', 'libpng', 'zlib', 'libexpat', 'libc++',
    ])
    
    # ── OpenJDK 17 ──
    info("=" * 50)
    build_package(packages, 'openjdk-17', [
        'openjdk-17', 'openjdk-17-x', 'ca-certificates-java',
        'zlib', 'libpng', 'freetype', 'fontconfig', 'libiconv',
    ])
    
    # ── Clang ──
    info("=" * 50)
    build_package(packages, 'clang', [
        'clang', 'lld', 'llvm', 'libllvm', 'ndk-sysroot',
        'binutils-is-llvm', 'libc++', 'libcompiler-rt', 'zlib',
    ])
    
    # Summary
    info("=" * 50)
    info("BUILD COMPLETE")
    total_size = 0
    for f in sorted(os.listdir(OUTPUT_DIR)):
        if f.endswith('.tar.gz'):
            path = os.path.join(OUTPUT_DIR, f)
            size_mb = os.path.getsize(path) / (1024 * 1024)
            total_size += size_mb
            info(f"  {f}: {size_mb:.1f} MB")
    info(f"  Total: {total_size:.1f} MB")
    info(f"Assets in: {os.path.abspath(OUTPUT_DIR)}")

if __name__ == '__main__':
    main()