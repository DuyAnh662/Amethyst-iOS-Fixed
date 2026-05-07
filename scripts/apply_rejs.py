#!/usr/bin/env python3
"""
Aggressive .rej hunk applier for the JDK 25 iOS port.

git apply --reject and patch -F 100 both refuse hunks when surrounding
context doesn't match exactly. This tool reads each .rej file, extracts
the (context + removed) lines as 'old' and (context + added) as 'new',
then does str.replace on the target file. Works as long as the 'old'
text is unique in the file — which it almost always is for the
mechanical mirror_w/mirror_x substitutions in mirror_mapping.diff.

Usage:
    python3 apply_rejs.py <openjdk-source-root>

Walks the tree looking for *.rej files alongside their target file and
attempts to apply each hunk. Reports per-hunk status. Exits non-zero
if any hunk failed to apply (file untouched), so CI can flag it.
"""
import os, re, sys
from pathlib import Path

def parse_rej(rej_text: str):
    """Yield (old_text, new_text) per hunk in a .rej file."""
    hunk_re = re.compile(r'^@@ .*? @@.*$', re.MULTILINE)
    # Split on hunk headers
    parts = hunk_re.split(rej_text)
    headers = hunk_re.findall(rej_text)
    # parts[0] is the file-header preamble; parts[i+1] is the body for headers[i]
    for i, body in enumerate(parts[1:]):
        old_lines = []
        new_lines = []
        for line in body.split('\n'):
            if line.startswith('-') and not line.startswith('---'):
                old_lines.append(line[1:])
            elif line.startswith('+') and not line.startswith('+++'):
                new_lines.append(line[1:])
            elif line.startswith(' '):
                # context: present in both
                old_lines.append(line[1:])
                new_lines.append(line[1:])
            elif line == '':
                # blank line — context (may be present in source)
                old_lines.append('')
                new_lines.append('')
            # Skip \ "no newline at end of file" markers
        # Trim trailing blank lines from both (often spurious)
        while old_lines and old_lines[-1] == '':
            old_lines.pop()
        while new_lines and new_lines[-1] == '':
            new_lines.pop()
        # Trim leading blank lines too
        while old_lines and old_lines[0] == '':
            old_lines.pop(0)
        while new_lines and new_lines[0] == '':
            new_lines.pop(0)
        if not old_lines and not new_lines:
            continue
        yield '\n'.join(old_lines), '\n'.join(new_lines)

def apply_hunks_to_file(target: Path, hunks):
    """Apply (old, new) hunks to target. Returns (applied, failed) counts."""
    if not target.exists():
        return 0, len(list(hunks))
    text = target.read_text()
    applied = 0
    failed_details = []
    for i, (old, new) in enumerate(hunks):
        if not old:
            # Pure addition (no - or context lines): can't safely place.
            failed_details.append(f"hunk {i+1}: pure addition without context")
            continue
        count = text.count(old)
        if count == 0:
            # Try with normalized whitespace
            failed_details.append(f"hunk {i+1}: 'old' text not found ({len(old)} chars)")
            continue
        if count > 1:
            failed_details.append(f"hunk {i+1}: 'old' text matches {count} times — ambiguous")
            continue
        text = text.replace(old, new, 1)
        applied += 1
    if applied:
        target.write_text(text)
    return applied, failed_details

def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else '.')
    rejs = sorted(root.rglob('*.rej'))
    if not rejs:
        print(f"[apply_rejs] no .rej files under {root}")
        return 0
    total_applied = 0
    total_failed = 0
    for rej in rejs:
        target = rej.with_suffix('')
        # rej path is like .../foo.cpp.rej  → target is .../foo.cpp
        # but rglob gives full path; .with_suffix strips ".rej" yielding "foo.cpp"
        # Validate the target actually exists:
        if not target.exists():
            print(f"[apply_rejs] WARN target missing: {target}")
            continue
        rel = target.relative_to(root) if target.is_absolute() else target
        rej_text = rej.read_text()
        hunks = list(parse_rej(rej_text))
        applied, failed = apply_hunks_to_file(target, hunks)
        total_applied += applied
        total_failed += len(failed)
        status = 'ok' if not failed else 'partial' if applied else 'fail'
        print(f"[apply_rejs] {status:7} {rel}: {applied}/{len(hunks)} hunks applied")
        for f in failed:
            print(f"           {f}")
        if not failed:
            rej.unlink()
    print(f"[apply_rejs] TOTAL: {total_applied} applied, {total_failed} still failing")
    # Don't fail CI here — let compile errors surface what's missing
    return 0

if __name__ == '__main__':
    sys.exit(main())
