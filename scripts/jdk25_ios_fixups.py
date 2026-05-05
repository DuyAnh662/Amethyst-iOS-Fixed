#!/usr/bin/env python3
"""Apply iOS fixups to OpenJDK 25 source that the JDK 21 patch couldn't.

The JDK 21 iOS base patch (patches/jre_21/ios/1_jdk21u_ios.diff) applies
mostly clean to JDK 25 source, but ~14 hunks reject because OpenJDK source
moved between 21 and 25. This script finishes the job by applying targeted
text replacements for each rejected hunk.

Idempotent — safe to re-run. Reports skip/ok/warn for each file.

Usage: python3 jdk25_ios_fixups.py [/path/to/openjdk-25]
"""
import sys, os
from pathlib import Path

JDK = Path(sys.argv[1] if len(sys.argv) > 1 else 'openjdk-25')
os.chdir(JDK)

ok = warn = skip = 0


def patch(path, transformations):
    """Apply (old_text, new_text) tuples to file. Each transformation is
    independent — reports per file at end."""
    global ok, warn, skip
    p = Path(path)
    if not p.exists():
        print(f"  [WARN] missing file: {path}")
        warn += 1
        return
    s = original = p.read_text()
    file_status = []
    for label, old, new in transformations:
        if new in s and old not in s:
            file_status.append(f"skip:{label}")
            continue
        if old in s:
            s = s.replace(old, new, 1)
            file_status.append(f"ok:{label}")
        else:
            file_status.append(f"WARN:{label}")
    if s != original:
        p.write_text(s)
    statuses = ", ".join(file_status)
    print(f"  {path}: {statuses}")
    if "WARN:" in statuses:
        warn += 1
    elif "ok:" in statuses:
        ok += 1
    else:
        skip += 1


# 1. flags-ldflags.m4 — comment out OS_LDFLAGS for iOS (keeping JDK 25's
#    -Wl,-reproducible suffix which JDK 21 didn't have)
patch('make/autoconf/flags-ldflags.m4', [
    ("comment-os-ldflags",
     '    OS_LDFLAGS="-mmacosx-version-min=$MACOSX_VERSION_MIN -Wl,-reproducible"',
     '    #OS_LDFLAGS="-mmacosx-version-min=$MACOSX_VERSION_MIN -Wl,-reproducible"'),
])

# 2. MakeBase.gmk — original hunk just removes a blank line. Cosmetic, skip.

# 3. LauncherCommon.gmk — JDK 25 moved per-launcher LIBS into individual
#    module Lib.gmk files, so the Cocoa→Foundation swap that was here in
#    JDK 21 is now handled by the individual module patches below. Skip.

# 4. java.base/Lib.gmk — (a) add CFNetwork to libnet, (b) skip libosxsecurity
patch('make/modules/java.base/Lib.gmk', [
    ("libnet-add-cfnetwork",
     "    LIBS_macosx := \\\n        -framework CoreFoundation \\\n        -framework CoreServices, \\\n))\n\nTARGETS += $(BUILD_LIBNET)",
     "    LIBS_macosx := \\\n        -framework CoreFoundation \\\n        -framework CoreServices \\\n        -framework CFNetwork, \\\n))\n\nTARGETS += $(BUILD_LIBNET)"),
    ("skip-libosxsecurity-on-ios",
     "ifeq ($(call isTargetOs, macosx), true)\n  ##############################################################################\n  ## Build libosxsecurity",
     "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  ##############################################################################\n  ## Build libosxsecurity"),
])

# 5. java.base/lib/CoreLibraries.gmk — libjli: ApplicationServices+Cocoa → Foundation
patch('make/modules/java.base/lib/CoreLibraries.gmk', [
    ("libjli-foundation-only",
     "    LIBS_macosx := \\\n        -framework ApplicationServices \\\n        -framework Cocoa \\\n        -framework Security, \\\n    LIBS_windows := advapi32.lib comctl32.lib user32.lib, \\",
     "    LIBS_macosx := \\\n        -framework Foundation \\\n        -framework Security, \\\n    LIBS_windows := advapi32.lib comctl32.lib user32.lib, \\"),
])

# 6. java.desktop/Lib.gmk — (a) AudioUnit → AVFoundation in libjsound,
#    (b) skip libosxapp on iOS
patch('make/modules/java.desktop/Lib.gmk', [
    ("libjsound-avfoundation",
     "      LIBS_macosx := \\\n          -framework AudioToolbox \\\n          -framework AudioUnit \\\n          -framework CoreAudio \\",
     "      LIBS_macosx := \\\n          -framework AudioToolbox \\\n          -framework AVFoundation \\\n          -framework CoreAudio \\"),
    ("skip-libosxapp-on-ios",
     "ifeq ($(call isTargetOs, macosx), true)\n  ##############################################################################\n  # Build libosxapp",
     "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  ##############################################################################\n  # Build libosxapp"),
])

# 7. java.instrument/Lib.gmk — libinstrument: ApplicationServices+Cocoa → Foundation
patch('make/modules/java.instrument/Lib.gmk', [
    ("libinstrument-foundation-only",
     "    LIBS_macosx := \\\n        -framework ApplicationServices \\\n        -framework Cocoa \\\n        -framework Security, \\\n    LIBS_windows := advapi32.lib, \\",
     "    LIBS_macosx := \\\n        -framework Foundation \\\n        -framework Security, \\\n    LIBS_windows := advapi32.lib, \\"),
])

# 8. java.security.jgss/Lib.gmk — skip libosxkrb5 on iOS
patch('make/modules/java.security.jgss/Lib.gmk', [
    ("skip-libosxkrb5-on-ios",
     "  ifeq ($(call isTargetOs, macosx), true)\n    ############################################################################\n    ## Build libosxkrb5",
     "  ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n    ############################################################################\n    ## Build libosxkrb5"),
])

# 9. jdk.hotspot.agent/Lib.gmk — skip building libsaproc on iOS (was libsa
#    in JDK 21, renamed to libsaproc in JDK 25; see SetupJdkLibrary block name)
patch('make/modules/jdk.hotspot.agent/Lib.gmk', [
    ("skip-libsaproc-target",
     "TARGETS += $(BUILD_LIBSAPROC)",
     "#TARGETS += $(BUILD_LIBSAPROC)  # disabled for iOS"),
])

# 10. jdk.jpackage/Lib.gmk — applauncher: Cocoa → Foundation
patch('make/modules/jdk.jpackage/Lib.gmk', [
    ("jpackage-applauncher-foundation",
     "    LIBS_macosx := -framework Cocoa, \\",
     "    LIBS_macosx := -framework Foundation, \\"),
])

# 11. signals_posix.cpp — add includes for os_bsd.hpp + sys/mman.h
patch('src/hotspot/os/posix/signals_posix.cpp', [
    ("add-os-bsd-include",
     '#include "utilities/vmError.hpp"\n\n#include <signal.h>',
     '#include "utilities/vmError.hpp"\n#include "os_bsd.hpp"\n\n#include <signal.h>\n#include <sys/mman.h>'),
])

# 13. memMapPrinter_macosx.cpp — uses <mach/mach_vm.h> which iOS SDK marks
#     "unsupported". Wrap the entire macOS body in an extra iOS guard, then
#     append an iOS stub so the linker still resolves
#     MemMapPrinter::pd_print_all_mappings called from shared NMT code.
def patch_memmapprinter():
    p = Path('src/hotspot/os/bsd/memMapPrinter_macosx.cpp')
    if not p.exists():
        print(f"  [WARN] missing file: {p}")
        return
    s = original = p.read_text()
    if 'TARGET_OS_IPHONE' in s:
        print(f"  {p}: skip (already patched)")
        return
    # Replace top guard
    s = s.replace(
        "#if defined(__APPLE__)\n\n#include \"nmt/memMapPrinter.hpp\"",
        "#include <TargetConditionals.h>\n#if defined(__APPLE__) && !TARGET_OS_IPHONE\n\n#include \"nmt/memMapPrinter.hpp\"",
        1,
    )
    # Append iOS stub at end of file
    stub = (
        "\n\n#if defined(__APPLE__) && TARGET_OS_IPHONE\n"
        "// iOS stub: NMT memory-map printing requires <mach/mach_vm.h> which the\n"
        "// iOS SDK marks unsupported. Provide an empty implementation so the\n"
        "// shared NMT module's call resolves at link time.\n"
        "#include \"nmt/memMapPrinter.hpp\"\n"
        "void MemMapPrinter::pd_print_all_mappings(const MappingPrintSession&) {}\n"
        "#endif\n"
    )
    s = s + stub
    if s != original:
        p.write_text(s)
        print(f"  {p}: ok:guard-and-stub-on-ios")
        global ok
        ok += 1
patch_memmapprinter()

# 12. icache_bsd_aarch64.hpp — wrap __clear_cache with iOS-compatible version
#     using sys_icache_invalidate. JDK 25 has `initialize(int phase)` (vs
#     plain `initialize()` in JDK 21), so context is slightly different.
patch('src/hotspot/os_cpu/bsd_aarch64/icache_bsd_aarch64.hpp', [
    ("ios-clear-cache-wrapper",
     "  static void initialize(int phase);\n  static void invalidate_word(address addr) {\n    __clear_cache((char *)addr, (char *)(addr + 4));\n  }\n  static void invalidate_range(address start, int nbytes) {\n    __clear_cache((char *)start, (char *)(start + nbytes));\n  }",
     "  static void initialize(int phase);\n#if defined(__APPLE__) && defined(__arm64__)\n  static void __clear_cache_(void *start, void *end) {\n    sys_icache_invalidate(start, (char *)end - (char *)start);\n  }\n#else\n  #define __clear_cache_ __clear_cache\n#endif\n  static void invalidate_word(address addr) {\n    __clear_cache_((char *)addr, (char *)(addr + 4));\n  }\n  static void invalidate_range(address start, int nbytes) {\n    __clear_cache_((char *)start, (char *)(start + nbytes));\n  }"),
])

# 14. AwtLibraries.gmk — JDK 25 renamed Awt2dLibraries.gmk to AwtLibraries.gmk.
#     The libjawt source for macOS lives in src/java.desktop/macosx which
#     6_buildjdk.sh moves to macosx_NOTIOS at build time, so SetupJdkLibrary
#     fails with "No sources found for BUILD_LIBJAWT". Wrap the SetupJdkLibrary
#     call AND the TARGETS line in a macosx_NOTIOS guard so iOS skips libjawt
#     entirely (Pojav iOS uses GLFW + LWJGL directly, no AWT needed).
def patch_awtlibraries():
    p = Path('make/modules/java.desktop/lib/AwtLibraries.gmk')
    if not p.exists():
        print(f"  [WARN] missing file: {p}")
        return
    s = original = p.read_text()
    if 'libjawt disabled for iOS' in s:
        print(f"  {p}: skip (already patched)")
        return
    old_block = (
        "$(eval $(call SetupJdkLibrary, BUILD_LIBJAWT, \\\n"
        "    NAME := jawt, \\\n"
        "    EXCLUDE_SRC_PATTERNS := $(LIBJAWT_EXCLUDE_SRC_PATTERNS), \\\n"
        "    OPTIMIZATION := LOW, \\\n"
        "    CFLAGS := $(LIBJAWT_CFLAGS), \\\n"
        "    CFLAGS_windows := -EHsc -DUNICODE -D_UNICODE, \\\n"
        "    CXXFLAGS_windows := -EHsc -DUNICODE -D_UNICODE, \\\n"
        "    DISABLED_WARNINGS_clang_jawt.m := sign-compare, \\\n"
        "    EXTRA_HEADER_DIRS := $(LIBJAWT_EXTRA_HEADER_DIRS), \\\n"
        "    LDFLAGS_windows := $(LDFLAGS_CXX_JDK), \\\n"
        "    LDFLAGS_macosx := -Wl$(COMMA)-rpath$(COMMA)@loader_path, \\\n"
        "    JDK_LIBS_unix := $(LIBJAWT_JDK_LIBS_unix), \\\n"
        "    JDK_LIBS_windows := libawt, \\\n"
        "    JDK_LIBS_macosx := libawt_lwawt, \\\n"
        "    LIBS_macosx := -framework Cocoa, \\\n"
        "    LIBS_windows := advapi32.lib $(LIBJAWT_LIBS_windows), \\\n"
        "))\n"
        "\n"
        "TARGETS += $(BUILD_LIBJAWT)"
    )
    if old_block not in s:
        print(f"  {p}: WARN libjawt block not found verbatim")
        global warn
        warn += 1
        return
    new_block = (
        "# libjawt disabled for iOS — no AWT support, src/java.desktop/macosx moved out\n"
        "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n"
        + old_block + "\n"
        "endif"
    )
    s = s.replace(old_block, new_block, 1)
    p.write_text(s)
    print(f"  {p}: ok:guard-libjawt-on-ios")
    global ok
    ok += 1
patch_awtlibraries()

# 15. ClientLibraries.gmk — JDK 25's libosxui block also depends on
#     src/java.desktop/macosx sources (Metal shaders + AquaFileView etc.)
#     which we move to macosx_NOTIOS. Skip the entire macosx libosxui block
#     by changing its outer ifeq to macosx_NOTIOS.
patch('make/modules/java.desktop/lib/ClientLibraries.gmk', [
    ("skip-libosxui-on-ios",
     "TARGETS += $(BUILD_LIBFONTMANAGER)\n\nifeq ($(call isTargetOs, macosx), true)\n  ##############################################################################\n  ## Build libosxui",
     "TARGETS += $(BUILD_LIBFONTMANAGER)\n\nifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  ##############################################################################\n  ## Build libosxui"),
])

# 16. AwtLibraries.gmk — port the JDK 21 patch's libawt/lwawt iOS strategy:
#     (a) BUILD_LIBAWT links macOS frameworks (ApplicationServices, Cocoa,
#         OpenGL, JavaRuntimeSupport) that don't exist on iOS — change
#         LIBS_macosx to LIBS_macosx_NOTIOS so iOS gets an empty link list.
#     (b) The libawt_excludeFiles macosx ifeq excludes initIDs/img_colors
#         only on real macOS (the iOS build needs them in libawt_headless).
#     (c) libawt_headless is gated off for windows+macosx — flip the guard
#         to macosx_NOTIOS so it builds on iOS instead.
#     (d) BUILD_LIBAWT_LWAWT is the AppKit-using path; skip entirely on iOS
#         since src/java.desktop/macosx is moved out and libosxapp doesn't
#         exist on iOS.
patch('make/modules/java.desktop/lib/AwtLibraries.gmk', [
    ("libawt-exclude-files-macosx-only-real-mac",
     "ifeq ($(call isTargetOs, macosx), true)\n  LIBAWT_EXCLUDE_FILES += initIDs.c img_colors.c\nendif",
     "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  LIBAWT_EXCLUDE_FILES += initIDs.c img_colors.c\nendif"),
    ("libawt-libs-macosx-not-ios",
     "    LIBS_aix := $(LIBDL), \\\n    LIBS_macosx := \\\n        -framework ApplicationServices \\\n        -framework AudioToolbox \\\n        -framework Cocoa \\\n        -framework JavaRuntimeSupport \\\n        -framework Metal \\\n        -framework OpenGL, \\",
     "    LIBS_aix := $(LIBDL), \\\n    LIBS_macosx_NOTIOS := \\\n        -framework ApplicationServices \\\n        -framework AudioToolbox \\\n        -framework Cocoa \\\n        -framework JavaRuntimeSupport \\\n        -framework Metal \\\n        -framework OpenGL, \\"),
    ("libawt-headless-build-on-ios",
     "# Mac and Windows only use the native AWT lib, do not build libawt_headless\nifeq ($(call isTargetOs, windows macosx), false)",
     "# Mac and Windows only use the native AWT lib, do not build libawt_headless\n# (iOS gets libawt_headless because we skip the Cocoa-using libawt_lwawt)\nifeq ($(call isTargetOs, windows macosx_NOTIOS), false)"),
    ("skip-libawt-lwawt-on-ios",
     "ifeq ($(call isTargetOs, macosx), true)\n  ##############################################################################\n  ## Build libawt_lwawt",
     "ifeq ($(call isTargetOs, macosx_NOTIOS), true)\n  ##############################################################################\n  ## Build libawt_lwawt"),
])

print(f"\nfixups: ok={ok} skip={skip} warn={warn}")
sys.exit(1 if warn > 0 else 0)
