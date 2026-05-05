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
#     "unsupported". Wrap the entire body in an extra iOS guard so it compiles
#     to nothing on iOS. The NMT memory-map printing is non-essential.
patch('src/hotspot/os/bsd/memMapPrinter_macosx.cpp', [
    ("guard-out-on-ios",
     "#if defined(__APPLE__)\n\n#include \"nmt/memMapPrinter.hpp\"",
     "#include <TargetConditionals.h>\n#if defined(__APPLE__) && !TARGET_OS_IPHONE\n\n#include \"nmt/memMapPrinter.hpp\""),
])

# 12. icache_bsd_aarch64.hpp — wrap __clear_cache with iOS-compatible version
#     using sys_icache_invalidate. JDK 25 has `initialize(int phase)` (vs
#     plain `initialize()` in JDK 21), so context is slightly different.
patch('src/hotspot/os_cpu/bsd_aarch64/icache_bsd_aarch64.hpp', [
    ("ios-clear-cache-wrapper",
     "  static void initialize(int phase);\n  static void invalidate_word(address addr) {\n    __clear_cache((char *)addr, (char *)(addr + 4));\n  }\n  static void invalidate_range(address start, int nbytes) {\n    __clear_cache((char *)start, (char *)(start + nbytes));\n  }",
     "  static void initialize(int phase);\n#if defined(__APPLE__) && defined(__arm64__)\n  static void __clear_cache_(void *start, void *end) {\n    sys_icache_invalidate(start, (char *)end - (char *)start);\n  }\n#else\n  #define __clear_cache_ __clear_cache\n#endif\n  static void invalidate_word(address addr) {\n    __clear_cache_((char *)addr, (char *)(addr + 4));\n  }\n  static void invalidate_range(address start, int nbytes) {\n    __clear_cache_((char *)start, (char *)(start + nbytes));\n  }"),
])

print(f"\nfixups: ok={ok} skip={skip} warn={warn}")
sys.exit(1 if warn > 0 else 0)
