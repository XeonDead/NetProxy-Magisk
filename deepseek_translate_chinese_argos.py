#!/usr/bin/env python3
"""
Translate all Chinese text in Git‑tracked files using offline Argos Translate.
No internet connection required after initial model download.
Usage: python translate_chinese_argos.py [repo_path] [--dry-run]
"""

import os
import re
import sys
import argparse
import subprocess
from pathlib import Path
from typing import Optional

import argostranslate.package
import argostranslate.translate

# ----------------------------------------------------------------------
# Chinese Unicode ranges
# ----------------------------------------------------------------------
HANZI = re.compile(r'[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]')
CHINESE_BLOCK = re.compile(
    r'[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff'
    r'\u3000-\u303f\uff00-\uffef]+'
)

# ----------------------------------------------------------------------
# Text‑file detection
# ----------------------------------------------------------------------
def is_text_file(filepath: Path) -> bool:
    try:
        with open(filepath, 'rb') as f:
            chunk = f.read(1024)
        if b'\x00' in chunk:
            return False
        chunk.decode('utf-8')
        return True
    except Exception:
        return False

# ----------------------------------------------------------------------
# Argos Translate setup (load once)
# ----------------------------------------------------------------------
def load_translation_model(source_code="zh", target_code="en"):
    """Return a function that translates text from source to target."""
    # Ensure the model is installed
    installed = argostranslate.package.get_installed_packages()
    if not any(pkg.from_code == source_code and pkg.to_code == target_code for pkg in installed):
        print("Error: Chinese→English model not installed.", file=sys.stderr)
        print("Run: argospm install translate-zh_en", file=sys.stderr)
        sys.exit(1)

    translation = argostranslate.translate.get_translation_from_codes(source_code, target_code)
    if translation is None:
        print("Error: could not load translation model.", file=sys.stderr)
        sys.exit(1)
    return translation

# ----------------------------------------------------------------------
# File translation
# ----------------------------------------------------------------------
def translate_file(filepath: Path, translation, dry_run: bool) -> bool:
    """Replace Chinese blocks inside a file, optionally just show changes."""
    if not is_text_file(filepath):
        return False

    encodings = ['utf-8', 'gb18030']
    content = None
    used_encoding = None
    for enc in encodings:
        try:
            with open(filepath, 'r', encoding=enc) as f:
                content = f.read()
            used_encoding = enc
            break
        except (UnicodeDecodeError, FileNotFoundError):
            continue
    if content is None:
        return False

    # Translate each Chinese block
    def translate_match(match: re.Match) -> str:
        original = match.group(0)
        if HANZI.search(original):
            try:
                return translation.translate(original)
            except Exception:
                return original
        return original

    new_content = CHINESE_BLOCK.sub(translate_match, content)

    if new_content == content:
        return False

    if dry_run:
        print(f"  Would translate: {filepath}")
        old_lines = content.splitlines()
        new_lines = new_content.splitlines()
        shown = 0
        for i, (old, new) in enumerate(zip(old_lines, new_lines)):
            if old != new:
                print(f"    L{i+1}: {old[:70]}...  →  {new[:70]}...")
                shown += 1
                if shown >= 3:
                    break
    else:
        with open(filepath, 'w', encoding=used_encoding, newline='') as f:
            f.write(new_content)
        print(f"  Translated: {filepath}")
    return True

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Translate Chinese in a Git repo using offline Argos Translate"
    )
    parser.add_argument("repo_path", nargs="?", default=".",
                        help="Path to Git repository (default: current dir)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be translated without modifying files")
    args = parser.parse_args()

    repo = Path(args.repo_path).resolve()
    os.chdir(repo)

    # Get tracked files
    try:
        result = subprocess.run(
            ["git", "ls-files", "-z"],
            capture_output=True, text=True, check=True
        )
        files = [repo / f for f in result.stdout.split('\0') if f]
    except subprocess.CalledProcessError:
        print("Error: not inside a Git repository or 'git ls-files' failed.")
        sys.exit(1)

    SKIP_EXT = {'.png', '.jpg', '.jpeg', '.gif', '.pdf', '.gz', '.zip',
                '.so', '.o', '.exe', '.dll', '.pyc', '.class', '.docx', '.xlsx'}
    files = [f for f in files if f.is_file() and f.suffix.lower() not in SKIP_EXT]

    print(f"Loading Chinese→English translation model...")
    translation_engine = load_translation_model()
    print(f"Model loaded. Found {len(files)} tracked files. Scanning...\n")

    translated_count = 0
    for fp in files:
        if translate_file(fp, translation_engine, args.dry_run):
            translated_count += 1

    print(f"\nDone. {translated_count} file(s) would be/are translated.")

if __name__ == "__main__":
    main()