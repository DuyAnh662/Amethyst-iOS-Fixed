#!/usr/bin/env bash
# Downloads Adoptium Temurin 25 GA (macOS aarch64), retags Mach-O platform from
# macOS to iOS with vtool, ad-hoc signs with ldid, and produces a pruned JRE
# bundle at $DEST_DIR (default: ../depends/java-25-openjdk).
#
# Mirrors the layout the existing crystall1ne JRE bundles use, which Pojav
# expects: <root>/lib/{libjvm.dylib,libjli.dylib,modules,...} with no bin/.
#
# Requires: curl, tar, vtool, ldid, file, find. Designed to run on macos-14
# in GitHub Actions (vtool ships with Xcode CLT; ldid via brew).

set -euo pipefail

JDK_URL="${JDK_URL:-https://api.adoptium.net/v3/binary/latest/25/ga/mac/aarch64/jdk/hotspot/normal/eclipse}"
DEST_DIR="${DEST_DIR:-$(cd "$(dirname "$0")/.." && pwd)/depends/java-25-openjdk}"
WORK_DIR="${WORK_DIR:-$(mktemp -d -t jre25-XXXXXX)}"

if [ -f "$DEST_DIR/release" ] && [ -f "$DEST_DIR/lib/libjvm.dylib" ]; then
    echo "[jre25] $DEST_DIR already present, skipping download/retag"
    exit 0
fi

echo "[jre25] downloading Adoptium Temurin JDK 25 GA (macOS aarch64)..."
curl -L --fail -o "$WORK_DIR/jdk25.tar.gz" "$JDK_URL"

echo "[jre25] extracting to $WORK_DIR..."
tar xzf "$WORK_DIR/jdk25.tar.gz" -C "$WORK_DIR"

# Adoptium tarball structure: jdk-25.X.X+Y/Contents/Home/{bin,lib,...}
HOME_DIR="$(echo "$WORK_DIR"/jdk-25*/Contents/Home)"
if [ ! -d "$HOME_DIR" ]; then
    echo "[jre25] ERROR: could not find Contents/Home in extracted tarball"
    ls -la "$WORK_DIR"
    exit 1
fi

mkdir -p "$DEST_DIR"
echo "[jre25] copying $HOME_DIR -> $DEST_DIR..."
cp -R "$HOME_DIR/." "$DEST_DIR/"

# Strip what Pojav doesn't need: bin (we use libjli directly), include, jmods,
# legal, man, demo, sample, jspawnhelper, src.zip, libjsig.dylib (signal-chain
# helper not used in-process). Keep lib/{*.dylib,modules,*.jsa,security,...}.
echo "[jre25] stripping unnecessary files..."
rm -rf "$DEST_DIR"/{bin,include,jmods,legal,man,demo,sample,LICENSE,NOTICE,README,ASSEMBLY_EXCEPTION,THIRD_PARTY_README,DISCLAIMER}
rm -f "$DEST_DIR/lib/src.zip" "$DEST_DIR/lib/jspawnhelper" "$DEST_DIR/lib/libjsig.dylib"

# Retag Mach-O platform from macOS (1) to iOS (2) and re-sign with ldid.
# Skip files that aren't Mach-O (e.g. modules archive, .jsa) to avoid noise.
echo "[jre25] retagging Mach-O files for iOS..."
RETAGGED=0
SKIPPED=0
while IFS= read -r -d '' f; do
    if file "$f" | grep -q "Mach-O"; then
        if vtool -arch arm64 -set-build-version 2 14.0 16.0 -replace -output "$f" "$f" 2>/dev/null; then
            ldid -S "$f" 2>/dev/null || true
            RETAGGED=$((RETAGGED + 1))
        else
            SKIPPED=$((SKIPPED + 1))
        fi
    fi
done < <(find "$DEST_DIR" -type f -print0)

echo "[jre25] retagged $RETAGGED Mach-O files ($SKIPPED skipped/failed)"

# Sanity check: libjvm.dylib must exist and be Mach-O for iOS.
if [ ! -f "$DEST_DIR/lib/libjvm.dylib" ]; then
    echo "[jre25] ERROR: libjvm.dylib missing from $DEST_DIR/lib/"
    exit 1
fi

if ! vtool -show "$DEST_DIR/lib/libjvm.dylib" 2>/dev/null | grep -q "platform IOS"; then
    echo "[jre25] WARNING: libjvm.dylib platform tag may not be IOS"
    vtool -show "$DEST_DIR/lib/libjvm.dylib" || true
fi

rm -rf "$WORK_DIR"
echo "[jre25] done. Final size:"
du -sh "$DEST_DIR"
