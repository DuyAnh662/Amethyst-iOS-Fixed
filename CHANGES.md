# Amethyst iOS – Changes Summary

## Files Modified

| File | Purpose |
|------|---------|
| `JavaApp/src/patchjna_agent/com/sun/jna/Platform.java` | Voice Chat + Sodium compatibility (JNA `isMac()` override) |
| `JavaApp/src/patchjna_agent/net/kdt/patchjna/PatchJNAAgent.java` | Sodium launcher/LWJGL checks bypass |
| `Natives/SurfaceViewController.m` | Microphone source selection UI logic |
| `Natives/LauncherPreferencesViewController.m` | Microphone source preferences entry |
| `Natives/PLPreferences.m` | Default value for `microphone_source` |
| `Natives/resources/en.lproj/Localizable.strings` | Mic labels (English) |
| `Natives/CMakeLists.txt` | Fix UnzipKit include path |
| `Makefile` | Build fix for actool + SPIRV_CROSS_SHARED |

---

## 1. Sodium Fix – "This launcher is not supported"

### Root cause
Sodium 0.6+ detects PojavLauncher via `PostLaunchChecks.isUsingPojavLauncher()` and blocks rendering. It also checks the LWJGL version in `PreLaunchChecks.isUsingKnownCompatibleLwjglVersion()`.

### Fix
Bytecode-level method patching in `PatchJNAAgent.java`:
- `PostLaunchChecks.isUsingPojavLauncher()` → returns `false`
- `PreLaunchChecks.isUsingKnownCompatibleLwjglVersion()` → returns `true`

Both methods return `boolean`, so the existing `patchReturnMethod()` helper is used.

---

## 2. Simple Voice Chat Fix – "Unsupported macOS launcher" + "Some modules failed to load"

### Root cause
Simple Voice Chat checks `Platform.isMac()` in multiple places. On iOS, `os.name` is `"iOS"` but PojavLauncher's JNA `Platform` class reports `MAC` as the OS type, so `isMac()` returns `true`. This triggers three problems:

1. **MicrophoneManager constructor** throws `UnsupportedOperationException("macOS is not supported")`, blocking mic entirely.
2. **VersionCheck.isMacOSNativeCompatible()** checks the macOS version – on iOS, `os.version` is `"16.7.16"`, which passes the `>= 13.0.0` check, so it returns `true`, letting `ClientManager.checkMicrophonePermissions()` call native AVFoundation code that shows "Your launcher does not support macOS microphone permissions".
3. **NativeValidator.initialize()** checks `!VersionCheck.isMacOSNativeCompatible()` – if we force VersionCheck to return `false` to fix problem 2, NativeValidator skips loading all native libraries (Opus, LAME, RNNoise, Speex), causing "Some modules failed to load".

### Fix (Platform.java – string-based class name matching)
Replace the old `Class.forName()` + `matchingClasses` approach (which failed because Fabric mod classes aren't visible to the system classloader) with a static `Set<String>` of voice-chat class names:

```java
private static final Set<String> matchingClassNames = new HashSet<>();
static {
    matchingClassNames.add("de.maxhenkel.voicechat.natives.NativeValidator");
    matchingClassNames.add("de.maxhenkel.voicechat.natives.OpusManager");
    matchingClassNames.add("de.maxhenkel.voicechat.macos.VersionCheck");
    // ... other voice chat classes
}
```

In `isMac()`, get the caller class name via `StackWalker` and check the set:

```java
Class caller = (Class)stackWalkerGetCaller.invoke(stackWalker);
if (matchingClassNames.contains(caller.getName())) {
    return false;
}
return true;
```

This makes `isMac()` return `false` ONLY for the listed voice-chat classes, regardless of classloader:

| Caller | `isMac()` returns | Effect |
|--------|-------------------|--------|
| `NativeValidator` | `false` | Skips macOS version check → **native libs load** |
| `OpusManager`, `LameManager`, etc. | `false` | (via inheritance) |
| `VersionCheck` | `false` | `isMacOSNativeCompatible()` returns `false` → **PermissionCheck returns AUTHORIZED** + **ClientManager skips permission check** |
| `MicrophoneManager` | `false` | Constructor does **not throw** |
| `VoicechatClient` | `false` | Skips macOS warning |
| Everything else (JNA, Minecraft, etc.) | `true` | Normal behavior |

**Key insight:** `NativeValidator` and `VersionCheck` are now in the same matching set. `NativeValidator` skips the macOS check and loads natives directly (no dependency on `VersionCheck`), while `VersionCheck` returning `false` suppresses the microphone permission error.

---

## 3. Microphone Source Selection (Native UI)

### Feature
Added a 4-option picker in Preferences → Audio:
- **Auto (Recommended)** – tries Front → Bottom → Back
- **Front microphone**
- **Bottom microphone**
- **Back microphone**

### Implementation
`SurfaceViewController.m` – `selectMicrophoneSource`:
1. Gets the `AVAudioSession` built-in mic port
2. Iterates `dataSources` matching the preferred name (case-insensitive)
3. Sets `preferredInput` + `preferredDataSource`

Tied to the `video.microphone_source` preference (default: `"auto"`), with `enableCondition` linked to `allow_microphone`.

---

## Build Notes

- Requires JDK 8 (`BOOTJDK`), cmake, ldid, and Xcode with iOS SDK
- Full build: `make PLATFORM=2 RELEASE=1`
- The `-javaagent:patchjna_agent.jar` is injected by `JavaLauncher.m`
