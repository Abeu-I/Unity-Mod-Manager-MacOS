#!/bin/bash
#
# Native Unity Mod Manager setup for A Dance of Fire and Ice on macOS.
#
# This uses the x86_64 slice of the macOS game through Rosetta, a universal
# UnityDoorstop 4 build patched for Unity 6 universal Mach-O files, and Unity
# Mod Manager's managed runtime.
# It does not use Wine, Whisky, CrossOver, or disable SIP.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ACTION="install"
GAME_APP=""
MOD_SOURCE=""
MOD_ZIP=""
MOD_ID=""
UMM_ZIP=""
DOORSTOP_ZIP=""
DRY_RUN=0

DOORSTOP_VERSION="4.5.0"
DOORSTOP_URL="https://github.com/NeighTools/UnityDoorstop/releases/download/v${DOORSTOP_VERSION}/doorstop_macos_release_${DOORSTOP_VERSION}.zip"
DOORSTOP_SHA256="f53e0906b60fdcaab1ed0259420863d0e9183285d2358e2edd9939a47f8c61e8"
BUNDLED_DOORSTOP="$SCRIPT_DIR/libdoorstop_adofai_macos.dylib"
BUNDLED_DOORSTOP_SHA256="ebbaee94803053d9bfb7dea3a8311dca242ed52d660a96c00d7cc3fdea59f08c"
BUNDLED_LAUNCH_HELPER="$SCRIPT_DIR/adofai_umm_launcher"
BUNDLED_LAUNCH_HELPER_SHA256="a00927565a61457ba998955ec9665b4f1e197c085b8657104262c8e609f99759"
BUNDLED_STEAM_BUNDLE_LAUNCHER="$SCRIPT_DIR/adofai_steam_bundle_launcher"
BUNDLED_STEAM_BUNDLE_LAUNCHER_SHA256="a02322f612dd2595d781b5b152f3b47e7e002a5f7227b202eb5723a5b727c6a0"

# Official UMM download linked by the upstream project. This URL is mutable,
# so its currently verified package hash is pinned. A newer official package
# can be supplied explicitly with --umm-zip after the user has downloaded it.
UMM_URL="https://www.dropbox.com/s/wz8x8e4onjdfdbm/UnityModManager.zip?dl=1"
UMM_SHA256="2d394abdbc3ad37a241c0a1dde8683a77646bc8c72c034b133153d376a9d5be7"

TEMP_DIR=""
GAME_ROOT=""
GAME_BIN=""
EXECUTABLE_NAME=""
MANAGED_DIR=""
UMM_DIR=""
MODS_DIR=""
TOOL_DIR=""
LAUNCHER=""
STEAM_LAUNCHER=""
BACKUP_ROOT=""
ORIGINAL_GAME_BIN=""
STEAM_THIN_GAME_BIN=""
STEAM_BUNDLE_MARKER=""

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME install [options]
  $SCRIPT_NAME add-mod --mod PATH [options]
  $SCRIPT_NAME doctor [options]
  $SCRIPT_NAME uninstall [options]
  $SCRIPT_NAME list-mods [options]
  $SCRIPT_NAME install-zip --zip PATH [options]
  $SCRIPT_NAME enable-mod --mod-id ID [options]
  $SCRIPT_NAME disable-mod --mod-id ID [options]
  $SCRIPT_NAME remove-mod --mod-id ID [options]
  $SCRIPT_NAME install-recommended --mod-id ID [options]

Actions:
  install      Install Doorstop 4 and the managed UMM runtime. Pass --mod
               to install an unpacked mod at the same time.
  add-mod      Add or update one unpacked UMM mod folder.
  doctor       Inspect prerequisites and the current installation.
  uninstall    Remove the loader and launcher. Installed mods are preserved.

Options:
  --game-app PATH   Full path to ADanceOfFireAndIce.app.
  --mod PATH        Unpacked mod folder containing Info.json.
  --umm-zip PATH    Use a locally downloaded UnityModManager.zip.
  --doorstop-zip PATH
                    Use the official macOS Doorstop 4 release zip locally.
  --dry-run         Download/build/validate, but do not change the game.
  -h, --help        Show this help.

Examples:
  ./$SCRIPT_NAME install --mod "$HOME/Downloads/AdofaiTweaks"
  ./$SCRIPT_NAME add-mod --mod "$HOME/Downloads/SomeOtherMod"
  ./$SCRIPT_NAME doctor
  ./$SCRIPT_NAME uninstall
EOF
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '%s\n' "$*"
}

cleanup() {
    case "${TEMP_DIR:-}" in
        /private/tmp/adofai-umm-macos.*)
            if [ -d "$TEMP_DIR" ]; then
                rm -rf "$TEMP_DIR"
            fi
            ;;
    esac
}

trap cleanup EXIT INT TERM

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

marker_launcher_hash() {
    [ -f "$STEAM_BUNDLE_MARKER" ] || return 0
    sed -nE 's/^Steam-compatible bundle launcher SHA-256 ([0-9a-f]{64})$/\1/p' "$STEAM_BUNDLE_MARKER" | head -n 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

download_file() {
    url="$1"
    output="$2"
    info "Downloading: $url"
    curl -fL --retry 2 --connect-timeout 20 "$url" -o "$output"
}

parse_args() {
    if [ "$#" -gt 0 ]; then
        case "$1" in
            install|add-mod|doctor|uninstall|list-mods|install-zip|enable-mod|disable-mod|remove-mod|install-recommended)
                ACTION="$1"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
        esac
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --game-app)
                [ "$#" -ge 2 ] || fail "--game-app requires a path"
                GAME_APP="$2"
                shift 2
                ;;
            --mod)
                [ "$#" -ge 2 ] || fail "--mod requires a path"
                MOD_SOURCE="$2"
                shift 2
                ;;
            --zip)
                [ "$#" -ge 2 ] || fail "--zip requires a path"
                MOD_ZIP="$2"
                shift 2
                ;;
            --mod-id)
                [ "$#" -ge 2 ] || fail "--mod-id requires a value"
                MOD_ID="$2"
                shift 2
                ;;
            --umm-zip)
                [ "$#" -ge 2 ] || fail "--umm-zip requires a path"
                UMM_ZIP="$2"
                shift 2
                ;;
            --doorstop-zip)
                [ "$#" -ge 2 ] || fail "--doorstop-zip requires a path"
                DOORSTOP_ZIP="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "Unknown argument: $1"
                ;;
        esac
    done
}

find_game_app() {
    if [ -n "$GAME_APP" ]; then
        [ -d "$GAME_APP" ] || fail "Game app not found: $GAME_APP"
        return
    fi

    default_app="$HOME/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice/ADanceOfFireAndIce.app"
    if [ -d "$default_app" ]; then
        GAME_APP="$default_app"
        return
    fi

    legacy_app="$HOME/Library/Application Support/Steam/steamapps/common/A Dance of Fire and Ice/ADOFAI.app"
    if [ -d "$legacy_app" ]; then
        GAME_APP="$legacy_app"
        return
    fi

    library_file="$HOME/Library/Application Support/Steam/config/libraryfolders.vdf"
    if [ -f "$library_file" ]; then
        while IFS= read -r library_path; do
            candidate="$library_path/steamapps/common/A Dance of Fire and Ice/ADanceOfFireAndIce.app"
            if [ -d "$candidate" ]; then
                GAME_APP="$candidate"
                return
            fi
        done <<EOF
$(awk -F'"' '$2 == "path" { print $4 }' "$library_file")
EOF
    fi

    fail "ADOFAI was not found. Pass --game-app with its full .app path."
}

resolve_game_layout() {
    find_game_app

    GAME_ROOT="$(dirname "$GAME_APP")"

    executable_name=""
    if [ -f "$GAME_APP/Contents/Info.plist" ]; then
        executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$GAME_APP/Contents/Info.plist" 2>/dev/null || true)"
    fi

    if [ -n "$executable_name" ] && [ -f "$GAME_APP/Contents/MacOS/$executable_name" ]; then
        GAME_BIN="$GAME_APP/Contents/MacOS/$executable_name"
    else
        GAME_BIN="$(find "$GAME_APP/Contents/MacOS" -maxdepth 1 -type f -perm +111 | head -n 1 || true)"
    fi
    [ -n "$GAME_BIN" ] && [ -f "$GAME_BIN" ] || fail "Game executable not found inside $GAME_APP"
    EXECUTABLE_NAME="$(basename "$GAME_BIN")"

    if [ -d "$GAME_APP/Contents/Resources/Data/Managed" ]; then
        MANAGED_DIR="$GAME_APP/Contents/Resources/Data/Managed"
    else
        MANAGED_DIR="$(find "$GAME_APP/Contents" -maxdepth 5 -type d -name Managed | head -n 1 || true)"
    fi
    [ -n "$MANAGED_DIR" ] && [ -d "$MANAGED_DIR" ] || fail "Unity Managed directory not found inside $GAME_APP"
    [ -f "$MANAGED_DIR/Assembly-CSharp.dll" ] || fail "Assembly-CSharp.dll is missing; this does not look like the supported Mono build."

    UMM_DIR="$MANAGED_DIR/UnityModManager"
    MODS_DIR="$GAME_ROOT/Mods"
    TOOL_DIR="$GAME_ROOT/.adofai-umm-macos"
    LAUNCHER="$GAME_ROOT/run_adofai_umm_macos.sh"
    STEAM_LAUNCHER="$GAME_ROOT/run_adofai_umm_from_steam.sh"
    BACKUP_ROOT="$GAME_ROOT/ADOFAI UMM Backups"
    ORIGINAL_GAME_BIN="$TOOL_DIR/original-game-executable"
    STEAM_THIN_GAME_BIN="$GAME_APP/Contents/MacOS/$EXECUTABLE_NAME.adofai-umm-x86_64"
    STEAM_BUNDLE_MARKER="$TOOL_DIR/steam-bundle-launcher-installed.txt"
}

check_x86_support() {
    architecture_source="$GAME_BIN"
    if [ -f "$ORIGINAL_GAME_BIN" ]; then
        architecture_source="$ORIGINAL_GAME_BIN"
    fi
    archs="$(lipo -archs "$architecture_source" 2>/dev/null || true)"
    case " $archs " in
        *" x86_64 "*) ;;
        *) fail "The installed game has no x86_64 slice. Rosetta mode cannot be used." ;;
    esac

    if ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
        fail "Rosetta is not available. Install Apple's Rosetta 2, then retry."
    fi
}

prepare_temp_dir() {
    if [ -z "$TEMP_DIR" ]; then
        TEMP_DIR="$(mktemp -d /private/tmp/adofai-umm-macos.XXXXXX)"
    fi
}

prepare_umm_package() {
    prepare_temp_dir
    package="$TEMP_DIR/UnityModManager.zip"

    if [ -n "$UMM_ZIP" ]; then
        [ -f "$UMM_ZIP" ] || fail "UMM package not found: $UMM_ZIP"
        cp "$UMM_ZIP" "$package"
    else
        download_file "$UMM_URL" "$package"
        actual_hash="$(sha256_file "$package")"
        if [ "$actual_hash" != "$UMM_SHA256" ]; then
            fail "The official UMM download changed (SHA-256: $actual_hash). Download and inspect the new package, then pass it with --umm-zip."
        fi
    fi

    mkdir -p "$TEMP_DIR/umm"
    unzip -q "$package" -d "$TEMP_DIR/umm"
    UMM_SOURCE_DIR="$(find "$TEMP_DIR/umm" -maxdepth 3 -type f -name UnityModManager.dll -exec dirname {} \; | head -n 1 || true)"
    [ -n "$UMM_SOURCE_DIR" ] || fail "UnityModManager.dll was not found in the supplied UMM package."

    for required in UnityModManager.dll 0Harmony.dll dnlib.dll; do
        [ -f "$UMM_SOURCE_DIR/$required" ] || fail "UMM package is missing $required"
    done
}

prepare_doorstop() {
    prepare_temp_dir
    if [ -n "$DOORSTOP_ZIP" ]; then
        archive="$TEMP_DIR/doorstop.zip"
        [ -f "$DOORSTOP_ZIP" ] || fail "Doorstop package not found: $DOORSTOP_ZIP"
        cp "$DOORSTOP_ZIP" "$archive"
        actual_hash="$(sha256_file "$archive")"
        [ "$actual_hash" = "$DOORSTOP_SHA256" ] || fail "Doorstop package hash mismatch: $actual_hash"

        mkdir -p "$TEMP_DIR/doorstop"
        unzip -q "$archive" -d "$TEMP_DIR/doorstop"
        DOORSTOP_BUILT="$(find "$TEMP_DIR/doorstop" -maxdepth 3 -type f -name libdoorstop.dylib | head -n 1 || true)"
        [ -n "$DOORSTOP_BUILT" ] || fail "libdoorstop.dylib was not found in the Doorstop package."
    else
        if [ ! -f "$BUNDLED_DOORSTOP" ]; then
            info "Building the native macOS components from source..."
            "$SCRIPT_DIR/build_native_components.sh"
        fi
        [ -f "$BUNDLED_DOORSTOP" ] || fail "Could not build libdoorstop_adofai_macos.dylib."
        actual_hash="$(sha256_file "$BUNDLED_DOORSTOP")"
        BUNDLED_DOORSTOP_SHA256="$actual_hash"
        DOORSTOP_BUILT="$BUNDLED_DOORSTOP"
    fi

    built_archs="$(lipo -archs "$DOORSTOP_BUILT")"
    case " $built_archs " in
        *" x86_64 "*) ;;
        *) fail "Doorstop library is missing x86_64: $built_archs" ;;
    esac
    case " $built_archs " in
        *" arm64 "*) ;;
        *) fail "Doorstop library is missing arm64: $built_archs" ;;
    esac
}

build_launch_helper() {
    prepare_temp_dir
    LAUNCH_HELPER_BUILT="$TEMP_DIR/adofai_umm_launcher"

    if [ -f "$BUNDLED_LAUNCH_HELPER" ]; then
        actual_hash="$(sha256_file "$BUNDLED_LAUNCH_HELPER")"
        [ "$actual_hash" = "$BUNDLED_LAUNCH_HELPER_SHA256" ] || fail "Bundled launch helper hash mismatch: $actual_hash"
        cp "$BUNDLED_LAUNCH_HELPER" "$LAUNCH_HELPER_BUILT"
        chmod +x "$LAUNCH_HELPER_BUILT"
    else
        require_command clang
        helper_source="$TEMP_DIR/adofai_umm_launcher.c"

        cat > "$helper_source" <<'EOF'
#include <errno.h>
#include <mach/machine.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static int prepend_environment(const char *name, const char *value)
{
    const char *old_value = getenv(name);
    char *combined = NULL;
    int result;

    if (old_value != NULL && old_value[0] != '\0') {
        if (asprintf(&combined, "%s:%s", value, old_value) < 0) {
            return ENOMEM;
        }
        result = setenv(name, combined, 1);
        free(combined);
        return result == 0 ? 0 : errno;
    }

    return setenv(name, value, 1) == 0 ? 0 : errno;
}

int main(int argc, char **argv)
{
    pid_t child_pid;
    posix_spawnattr_t attributes;
    const char *architecture = getenv("ADOFAI_UMM_ARCH");
    cpu_type_t preferred_cpu = CPU_TYPE_X86_64;
    size_t preference_count = 0;
    char **child_argv;
    int error;
    int status;
    int index;

    if (argc < 4) {
        fprintf(stderr, "Usage: %s GAME_BINARY DOORSTOP_DYLIB UMM_DLL [GAME_ARGS...]\n", argv[0]);
        return 64;
    }

    if (architecture != NULL && strcmp(architecture, "x86_64") == 0) {
        preferred_cpu = CPU_TYPE_X86_64;
    } else if (architecture != NULL &&
               architecture[0] != '\0' &&
               strcmp(architecture, "arm64") != 0) {
        fprintf(stderr, "ADOFAI_UMM_ARCH must be arm64 or x86_64.\n");
        return 64;
    }

    if (prepend_environment("DYLD_INSERT_LIBRARIES", argv[2]) != 0 ||
        setenv("DOORSTOP_ENABLE", "TRUE", 1) != 0 ||
        setenv("DOORSTOP_INVOKE_DLL_PATH", argv[3], 1) != 0 ||
        setenv("DOORSTOP_ENABLED", "1", 1) != 0 ||
        setenv("DOORSTOP_TARGET_ASSEMBLY", argv[3], 1) != 0 ||
        setenv("SteamAppId", "977950", 1) != 0 ||
        setenv("SteamGameId", "977950", 1) != 0) {
        perror("setenv");
        return 70;
    }
    child_argv = calloc((size_t)argc - 2, sizeof(char *));
    if (child_argv == NULL) {
        perror("calloc");
        return 70;
    }
    child_argv[0] = argv[1];
    for (index = 4; index < argc; index++) {
        child_argv[index - 3] = argv[index];
    }
    child_argv[argc - 3] = NULL;

    error = posix_spawnattr_init(&attributes);
    if (error == 0) {
        error = posix_spawnattr_setbinpref_np(
            &attributes, 1, &preferred_cpu, &preference_count);
    }
    if (error == 0 && preference_count != 1) {
        error = ENOEXEC;
    }
    if (error == 0) {
        error = posix_spawn(
            &child_pid, argv[1], NULL, &attributes, child_argv, environ);
    }
    posix_spawnattr_destroy(&attributes);
    free(child_argv);

    if (error != 0) {
        fprintf(stderr, "Could not launch the requested game architecture: %s\n", strerror(error));
        return 71;
    }

    do {
        error = waitpid(child_pid, &status, 0);
    } while (error < 0 && errno == EINTR);

    if (error < 0) {
        perror("waitpid");
        return 71;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }
    return 71;
}
EOF

        clang -O2 -Wall -Wextra -arch arm64 -arch x86_64 \
            -mmacosx-version-min=12.0 \
            -o "$LAUNCH_HELPER_BUILT" "$helper_source"
        codesign --force --sign - "$LAUNCH_HELPER_BUILT" >/dev/null
    fi

    helper_archs="$(lipo -archs "$LAUNCH_HELPER_BUILT")"
    case " $helper_archs " in
        *" arm64 "*) ;;
        *) fail "Launch helper is missing arm64: $helper_archs" ;;
    esac
    case " $helper_archs " in
        *" x86_64 "*) ;;
        *) fail "Launch helper is missing x86_64: $helper_archs" ;;
    esac
}

prepare_steam_bundle_launcher() {
    if [ ! -f "$BUNDLED_STEAM_BUNDLE_LAUNCHER" ]; then
        "$SCRIPT_DIR/build_native_components.sh"
    fi
    [ -f "$BUNDLED_STEAM_BUNDLE_LAUNCHER" ] || fail "Could not build the Steam bundle launcher."
    actual_hash="$(sha256_file "$BUNDLED_STEAM_BUNDLE_LAUNCHER")"
    BUNDLED_STEAM_BUNDLE_LAUNCHER_SHA256="$actual_hash"
    bundle_archs="$(lipo -archs "$BUNDLED_STEAM_BUNDLE_LAUNCHER" 2>/dev/null || true)"
    [ "$bundle_archs" = "x86_64" ] || fail "Steam bundle launcher must be Intel-only: $bundle_archs"
    codesign --verify "$BUNDLED_STEAM_BUNDLE_LAUNCHER" >/dev/null 2>&1 || fail "Steam bundle launcher signature is invalid."
}

write_umm_config() {
    config_path="$1"
    cat > "$config_path" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Config Name="A Dance of Fire and Ice">
  <Folder>ADOFAI</Folder>
  <ModsDirectory>Mods</ModsDirectory>
  <ModInfo>Info.json</ModInfo>
  <EntryPoint>[UnityEngine.CoreModule.dll]UnityEngine.MonoBehaviour.cctor:Before</EntryPoint>
  <StartingPoint>[Assembly-CSharp.dll]ADOStartup.Startup:Before</StartingPoint>
  <UIStartingPoint>[Assembly-CSharp.dll]ADOStartup.Startup:After</UIStartingPoint>
  <GameExe>A Dance of Fire and Ice.exe</GameExe>
  <MinimalManagerVersion>0.22.14</MinimalManagerVersion>
</Config>
EOF
}

make_backup_dir() {
    timestamp="$(date '+%Y%m%d-%H%M%S')"
    backup_dir="$BACKUP_ROOT/$timestamp"
    suffix=0
    while [ -e "$backup_dir" ]; do
        suffix=$((suffix + 1))
        backup_dir="$BACKUP_ROOT/$timestamp-$suffix"
    done
    mkdir -p "$backup_dir"
    printf '%s' "$backup_dir"
}

backup_existing_installation() {
    backup_dir="$1"

    if [ -d "$UMM_DIR" ]; then
        mkdir -p "$backup_dir/Managed"
        cp -pR "$UMM_DIR" "$backup_dir/Managed/UnityModManager"
    fi
    if [ -d "$TOOL_DIR" ]; then
        cp -pR "$TOOL_DIR" "$backup_dir/.adofai-umm-macos"
    fi
    if [ -f "$LAUNCHER" ]; then
        cp -p "$LAUNCHER" "$backup_dir/run_adofai_umm_macos.sh"
    fi
    if [ -f "$STEAM_LAUNCHER" ]; then
        cp -p "$STEAM_LAUNCHER" "$backup_dir/run_adofai_umm_from_steam.sh"
    fi
}

install_umm_files() {
    mkdir -p "$UMM_DIR" "$MODS_DIR" "$TOOL_DIR"

    cp "$UMM_SOURCE_DIR/UnityModManager.dll" "$UMM_DIR/UnityModManager.dll"
    cp "$UMM_SOURCE_DIR/0Harmony.dll" "$UMM_DIR/0Harmony.dll"
    cp "$UMM_SOURCE_DIR/dnlib.dll" "$UMM_DIR/dnlib.dll"
    if [ -f "$UMM_SOURCE_DIR/UnityModManager.xml" ]; then
        cp "$UMM_SOURCE_DIR/UnityModManager.xml" "$UMM_DIR/UnityModManager.xml"
    fi
    write_umm_config "$UMM_DIR/Config.xml"

    cp "$DOORSTOP_BUILT" "$TOOL_DIR/libdoorstop.dylib"
    codesign --force --sign - "$TOOL_DIR/libdoorstop.dylib" >/dev/null
    if [ -f "$TOOL_DIR/libdoorstop_x86_64.dylib" ]; then
        rm -f "$TOOL_DIR/libdoorstop_x86_64.dylib"
    fi
    cp "$LAUNCH_HELPER_BUILT" "$TOOL_DIR/adofai_umm_launcher"
    chmod +x "$TOOL_DIR/adofai_umm_launcher"
    codesign --force --sign - "$TOOL_DIR/adofai_umm_launcher" >/dev/null

    cat > "$TOOL_DIR/installed-files.txt" <<EOF
UnityDoorstop ${DOORSTOP_VERSION}
UnityModManager.dll SHA-256 $(sha256_file "$UMM_DIR/UnityModManager.dll")
0Harmony.dll SHA-256 $(sha256_file "$UMM_DIR/0Harmony.dll")
Launch helper SHA-256 $(sha256_file "$TOOL_DIR/adofai_umm_launcher")
Game app: $GAME_APP
Installed: $(date '+%Y-%m-%d %H:%M:%S %z')
EOF
}

install_steam_bundle_launcher() {
    current_hash="$(sha256_file "$GAME_BIN")"

    if [ -f "$STEAM_BUNDLE_MARKER" ]; then
        installed_launcher_hash="$(sed -nE 's/^Steam-compatible bundle launcher SHA-256 ([0-9a-f]{64})$/\1/p' "$STEAM_BUNDLE_MARKER" | head -n 1)"
        if [ -z "$installed_launcher_hash" ] || [ "$current_hash" != "$installed_launcher_hash" ]; then
            current_archs="$(lipo -archs "$GAME_BIN" 2>/dev/null || true)"
            case " $current_archs " in
                *" arm64 "*)
                    info "Steam supplied a newer universal game executable; refreshing the original backup."
                    cp -p "$GAME_BIN" "$ORIGINAL_GAME_BIN.new"
                    mv -f "$ORIGINAL_GAME_BIN.new" "$ORIGINAL_GAME_BIN"
                    ;;
                *)
                    fail "The installed launcher does not match its marker. Run Diagnostics and restore or verify the game before reinstalling."
                    ;;
            esac
        fi
    else
        cp -p "$GAME_BIN" "$ORIGINAL_GAME_BIN.new"
        mv -f "$ORIGINAL_GAME_BIN.new" "$ORIGINAL_GAME_BIN"
    fi

    [ -f "$ORIGINAL_GAME_BIN" ] || fail "The original game-executable backup is missing. Verify the game files in Steam, then reinstall."

    original_archs="$(lipo -archs "$ORIGINAL_GAME_BIN" 2>/dev/null || true)"
    case " $original_archs " in
        *" x86_64 "*) ;;
        *) fail "Original ADOFAI executable backup has no x86_64 slice: $original_archs" ;;
    esac

    entitlements="$TEMP_DIR/adofai-entitlements.plist"
    cat > "$entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.allow-dyld-environment-variables</key>
  <true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
  <true/>
  <key>com.apple.security.cs.disable-executable-page-protection</key>
  <true/>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
</dict>
</plist>
EOF

    thin_game="$TEMP_DIR/$EXECUTABLE_NAME.adofai-umm-x86_64"
    lipo "$ORIGINAL_GAME_BIN" -thin x86_64 -output "$thin_game"
    chmod +x "$thin_game"
    codesign --force --sign - --entitlements "$entitlements" "$thin_game" >/dev/null
    codesign --verify "$thin_game" >/dev/null 2>&1 || fail "Could not sign the Intel ADOFAI executable."

    cp -p "$thin_game" "$STEAM_THIN_GAME_BIN.new"
    mv -f "$STEAM_THIN_GAME_BIN.new" "$STEAM_THIN_GAME_BIN"
    cp -p "$BUNDLED_STEAM_BUNDLE_LAUNCHER" "$GAME_BIN.new"
    chmod +x "$GAME_BIN.new"
    mv -f "$GAME_BIN.new" "$GAME_BIN"

    cat > "$STEAM_BUNDLE_MARKER" <<EOF
Steam-compatible bundle launcher SHA-256 $BUNDLED_STEAM_BUNDLE_LAUNCHER_SHA256
Original executable SHA-256 $(sha256_file "$ORIGINAL_GAME_BIN")
Intel game executable SHA-256 $(sha256_file "$STEAM_THIN_GAME_BIN")
Installed: $(date '+%Y-%m-%d %H:%M:%S %z')
EOF
}

write_launcher() {
    escaped_game_root="$(printf '%q' "$GAME_ROOT")"
    escaped_game_bin="$(printf '%q' "$GAME_BIN")"
    escaped_doorstop="$(printf '%q' "$TOOL_DIR/libdoorstop.dylib")"
    escaped_umm="$(printf '%q' "$UMM_DIR/UnityModManager.dll")"
    escaped_helper="$(printf '%q' "$TOOL_DIR/adofai_umm_launcher")"

    cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Generated by $SCRIPT_NAME. Defaults to Intel/Rosetta because Harmony's
# runtime patcher is not implemented for this game's native ARM Mono runtime.
# Set ADOFAI_UMM_ARCH=arm64 only for loader diagnostics.
set -euo pipefail

GAME_ROOT=$escaped_game_root
GAME_BIN=$escaped_game_bin
DOORSTOP_LIB=$escaped_doorstop
UMM_ASSEMBLY=$escaped_umm
LAUNCH_HELPER=$escaped_helper

cd "\$GAME_ROOT"

ADOFAI_UMM_ARCH="\${ADOFAI_UMM_ARCH:-x86_64}"
export ADOFAI_UMM_ARCH

if [ "\$ADOFAI_UMM_ARCH" = "x86_64" ] && ! arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    echo "Rosetta 2 is required to launch ADOFAI with this UMM setup." >&2
    exit 1
fi

exec "\$LAUNCH_HELPER" "\$GAME_BIN" "\$DOORSTOP_LIB" "\$UMM_ASSEMBLY" "\$@"
EOF
    chmod +x "$LAUNCHER"

    escaped_launcher="$(printf '%q' "$LAUNCHER")"
    cat > "$STEAM_LAUNCHER" <<EOF
#!/bin/bash
# Steam launch-options wrapper. Steam expands %command% after this script;
# those arguments are intentionally ignored because the native helper must
# select ADOFAI's Intel slice itself.
set -euo pipefail
exec $escaped_launcher
EOF
    chmod +x "$STEAM_LAUNCHER"
}

mod_id_from_info() {
    info_json="$1"
    mod_id="$(sed -nE 's/^[[:space:]]*"Id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$info_json" | head -n 1)"
    [ -n "$mod_id" ] || fail "Could not read Id from $info_json"
    case "$mod_id" in
        *[!A-Za-z0-9._-]*) fail "Unsafe mod Id in Info.json: $mod_id" ;;
    esac
    printf '%s' "$mod_id"
}

install_mod_folder() {
    source_dir="$1"
    [ -d "$source_dir" ] || fail "Mod folder not found: $source_dir"
    [ -f "$source_dir/Info.json" ] || [ -f "$source_dir/info.json" ] || fail "Mod folder must contain Info.json: $source_dir"

    if [ -f "$source_dir/Info.json" ]; then
        info_json="$source_dir/Info.json"
    else
        info_json="$source_dir/info.json"
    fi

    mod_id="$(mod_id_from_info "$info_json")"
    destination="$MODS_DIR/$mod_id"
    mkdir -p "$MODS_DIR"

    if [ -e "$destination" ]; then
        backup_dir="$(make_backup_dir)"
        mkdir -p "$backup_dir/Mods"
        cp -pR "$destination" "$backup_dir/Mods/$mod_id"
        info "Backed up existing mod to: $backup_dir/Mods/$mod_id"
        rm -rf "$destination"
    fi

    mkdir -p "$destination"
    cp -pR "$source_dir/." "$destination/"
    if [ "$mod_id" = "AdofaiTweaks" ] && \
       [ -f "$destination/adofai_tweaks.assets" ] && \
       [ ! -e "$destination/adofaitweaks.assets" ]; then
        cp -p "$destination/adofai_tweaks.assets" "$destination/adofaitweaks.assets"
        info "Added AdofaiTweaks asset-bundle compatibility name."
    fi
    info "Installed mod '$mod_id' to: $destination"
}

validate_mod_id() {
    value="$1"
    [ -n "$value" ] || fail "A mod ID is required."
    case "$value" in *[!A-Za-z0-9._-]*) fail "Unsafe mod ID: $value" ;; esac
}

extract_safe_mod_zip() {
    archive="$1"
    destination="$2"
    /usr/bin/python3 - "$archive" "$destination" <<'PY'
import os, stat, sys, zipfile
archive, destination = sys.argv[1:]
limit = 512 * 1024 * 1024
with zipfile.ZipFile(archive) as z:
    infos = z.infolist()
    if len(infos) > 5000:
        raise SystemExit("ZIP contains too many files.")
    if sum(i.file_size for i in infos) > limit:
        raise SystemExit("ZIP expands beyond the 512 MB safety limit.")
    for info in infos:
        name = info.filename.replace("\\", "/")
        parts = [p for p in name.split("/") if p not in ("", ".")]
        mode = (info.external_attr >> 16) & 0xFFFF
        if name.startswith("/") or ".." in parts or (mode and stat.S_ISLNK(mode)):
            raise SystemExit(f"Unsafe ZIP entry: {info.filename}")
        target = os.path.realpath(os.path.join(destination, *parts))
        if os.path.commonpath([os.path.realpath(destination), target]) != os.path.realpath(destination):
            raise SystemExit(f"ZIP entry escapes destination: {info.filename}")
    z.extractall(destination)
PY
}

install_zip_action() {
    [ -n "$MOD_ZIP" ] || fail "install-zip requires --zip PATH"
    [ -f "$MOD_ZIP" ] || fail "ZIP file not found: $MOD_ZIP"
    resolve_game_layout
    [ -f "$UMM_DIR/UnityModManager.dll" ] || fail "UMM is not installed. Install the loader first."
    prepare_temp_dir
    extracted="$TEMP_DIR/mod-zip"
    mkdir -p "$extracted"
    extract_safe_mod_zip "$MOD_ZIP" "$extracted"
    info_list="$(find "$extracted" -maxdepth 6 -type f \( -name Info.json -o -name info.json \) -print)"
    info_count="$(printf '%s\n' "$info_list" | sed '/^$/d' | wc -l | tr -d ' ')"
    [ "$info_count" = "1" ] || fail "ZIP must contain exactly one UMM mod Info.json (found $info_count)."
    info_file="$(printf '%s\n' "$info_list" | head -n 1)"
    install_mod_folder "$(dirname "$info_file")"
}

list_mods_action() {
    resolve_game_layout
    [ -d "$MODS_DIR" ] || return 0
    for directory in "$MODS_DIR"/*; do
        [ -d "$directory" ] || continue
        info_file=""
        enabled="true"
        for candidate in "$directory/Info.json" "$directory/info.json"; do [ -f "$candidate" ] && info_file="$candidate" && break; done
        if [ -z "$info_file" ]; then
            for candidate in "$directory/Info.json.disabled" "$directory/info.json.disabled"; do [ -f "$candidate" ] && info_file="$candidate" && enabled="false" && break; done
        fi
        [ -n "$info_file" ] || continue
        /usr/bin/python3 - "$info_file" "$enabled" <<'PY'
import json, sys
path, enabled = sys.argv[1:]
with open(path, encoding="utf-8-sig") as f: data = json.load(f)
clean = lambda value: str(value or "").replace("\t", " ").replace("\n", " ")
print("MOD\t{}\t{}\t{}\t{}\t{}".format(clean(data.get("Id")), clean(data.get("DisplayName") or data.get("Id")), clean(data.get("Version")), enabled, clean(data.get("Author"))))
PY
    done
}

set_mod_enabled_action() {
    validate_mod_id "$MOD_ID"
    resolve_game_layout
    directory="$MODS_DIR/$MOD_ID"
    [ -d "$directory" ] || fail "Mod is not installed: $MOD_ID"
    if [ "$ACTION" = "disable-mod" ]; then
        if [ -f "$directory/Info.json" ]; then mv "$directory/Info.json" "$directory/Info.json.disabled"
        elif [ -f "$directory/info.json" ]; then mv "$directory/info.json" "$directory/info.json.disabled"
        else info "Mod is already disabled: $MOD_ID"; return; fi
        info "Disabled mod: $MOD_ID"
    else
        if [ -f "$directory/Info.json.disabled" ]; then mv "$directory/Info.json.disabled" "$directory/Info.json"
        elif [ -f "$directory/info.json.disabled" ]; then mv "$directory/info.json.disabled" "$directory/info.json"
        else info "Mod is already enabled: $MOD_ID"; return; fi
        info "Enabled mod: $MOD_ID"
    fi
}

remove_mod_action() {
    validate_mod_id "$MOD_ID"
    resolve_game_layout
    directory="$MODS_DIR/$MOD_ID"
    [ -d "$directory" ] || fail "Mod is not installed: $MOD_ID"
    backup_dir="$(make_backup_dir)"
    mkdir -p "$backup_dir/Mods"
    mv "$directory" "$backup_dir/Mods/$MOD_ID"
    info "Removed mod to recoverable backup: $backup_dir/Mods/$MOD_ID"
}

install_recommended_action() {
    validate_mod_id "$MOD_ID"
    case "$MOD_ID" in
        AdofaiTweaks) url="https://github.com/PizzaLovers007/AdofaiTweaks/releases/download/v2.9.2/AdofaiTweaks-2.9.2.zip"; expected="54f95784ed5833b7df091ce2fd2d544aa26d5014752041240c1e5dc4e5103c2d" ;;
        JALib) url="https://github.com/Jongye0l/JALib/releases/download/v1.0.0.45/JALib.zip"; expected="93938ff8020bb6b2aa3d9ff95f22de71b2d91ea2c14548c205450d8ea9b0fc61" ;;
        JipperResourcePack) url="https://github.com/Jongye0l/JipperResourcePack/releases/download/v1.4.9.0/JipperResourcePack.zip"; expected="15bf36cb31180bd4d2ca6b6cff5db03776084b09d208bf7761502c6fb6bfdd46" ;;
        JipperOverlayer) url="https://github.com/adofaiex/JipperOverlayer/releases/download/v1.1.4/JipperOverlayer-UMM.zip"; expected="520739a70078b205c163e57a162549f367405268badcfeffe4062916ede38227" ;;
        *) fail "Unknown recommended mod: $MOD_ID" ;;
    esac
    prepare_temp_dir
    MOD_ZIP="$TEMP_DIR/$MOD_ID.zip"
    download_file "$url" "$MOD_ZIP"
    actual="$(sha256_file "$MOD_ZIP")"
    [ "$actual" = "$expected" ] || fail "Downloaded mod checksum mismatch: $actual"
    install_zip_action
}

doctor_action() {
    resolve_game_layout

    info "ADOFAI macOS UMM doctor"
    info "  Mac architecture: $(uname -m)"
    info "  Game app: $GAME_APP"
    info "  Game binary: $GAME_BIN"
    info "  Game architectures: $(lipo -archs "$GAME_BIN" 2>/dev/null || echo unknown)"
    if arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
        info "  Rosetta x86_64 execution: available"
    else
        info "  Rosetta x86_64 execution: NOT AVAILABLE"
    fi
    info "  SIP: $(csrutil status 2>/dev/null || echo unknown)"

    entitlement_source="$GAME_BIN"
    if [ -f "$STEAM_THIN_GAME_BIN" ]; then
        entitlement_source="$STEAM_THIN_GAME_BIN"
    fi
    entitlements="$(codesign -d --entitlements - "$entitlement_source" 2>&1 || true)"
    for entitlement in \
        com.apple.security.cs.allow-dyld-environment-variables \
        com.apple.security.cs.allow-unsigned-executable-memory \
        com.apple.security.cs.disable-executable-page-protection \
        com.apple.security.cs.disable-library-validation; do
        if printf '%s\n' "$entitlements" | grep -q "$entitlement"; then
            info "  Entitlement $entitlement: present"
        else
            info "  Entitlement $entitlement: missing"
        fi
    done

    if [ -f "$UMM_DIR/UnityModManager.dll" ]; then
        info "  UMM runtime: installed"
    else
        info "  UMM runtime: not installed"
    fi
    if [ -f "$TOOL_DIR/libdoorstop.dylib" ]; then
        info "  Doorstop: installed ($(lipo -archs "$TOOL_DIR/libdoorstop.dylib" 2>/dev/null || echo unknown))"
    else
        info "  Doorstop: not installed"
    fi
    if [ -x "$TOOL_DIR/adofai_umm_launcher" ]; then
        info "  Native launch helper: installed ($(lipo -archs "$TOOL_DIR/adofai_umm_launcher" 2>/dev/null || echo unknown))"
    else
        info "  Native launch helper: not installed"
    fi
    if [ -x "$LAUNCHER" ]; then
        info "  Launcher: $LAUNCHER"
    else
        info "  Launcher: not installed"
    fi
    if [ -x "$STEAM_LAUNCHER" ]; then
        info "  Legacy Steam wrapper: present (do not use as a Steam launch option)"
    else
        info "  Legacy Steam wrapper: not installed"
    fi
    if [ -f "$STEAM_BUNDLE_MARKER" ] && [ -f "$ORIGINAL_GAME_BIN" ] && [ -f "$STEAM_THIN_GAME_BIN" ]; then
        current_hash="$(sha256_file "$GAME_BIN")"
        expected_hash="$(marker_launcher_hash)"
        if [ -n "$expected_hash" ] && [ "$current_hash" = "$expected_hash" ]; then
            info "  Steam-compatible bundle launch: installed"
        else
            info "  Steam-compatible bundle launch: NEEDS REINSTALL (Steam may have updated the game)"
        fi
    else
        info "  Steam-compatible bundle launch: not installed"
    fi

    if [ -d "$MODS_DIR" ]; then
        mod_count="$(find "$MODS_DIR" -mindepth 2 -maxdepth 2 -type f \( -name Info.json -o -name info.json \) | wc -l | tr -d ' ')"
        info "  UMM mods found: $mod_count"
        find "$MODS_DIR" -mindepth 2 -maxdepth 2 -type f \( -name Info.json -o -name info.json \) -print | sed 's#^#    #'
    else
        info "  UMM mods found: 0"
    fi
}

install_action() {
    resolve_game_layout
    check_x86_support
    require_command curl
    require_command unzip
    require_command codesign
    require_command lipo

    if [ -n "$MOD_SOURCE" ]; then
        [ -d "$MOD_SOURCE" ] || fail "Mod folder not found: $MOD_SOURCE"
        [ -f "$MOD_SOURCE/Info.json" ] || [ -f "$MOD_SOURCE/info.json" ] || fail "Mod folder must contain Info.json: $MOD_SOURCE"
    fi

    info "Preparing native macOS UMM installation..."
    prepare_umm_package
    prepare_doorstop
    build_launch_helper
    prepare_steam_bundle_launcher

    if [ "$DRY_RUN" -eq 1 ]; then
        info "Dry run passed. UMM package, Doorstop 4 universal library, native launch helpers, Rosetta, game layout, and mod folder are valid."
        info "No game files were changed."
        return
    fi

    backup_dir=""
    if [ -e "$UMM_DIR" ] || [ -e "$TOOL_DIR" ] || [ -e "$LAUNCHER" ] || [ -e "$STEAM_LAUNCHER" ]; then
        backup_dir="$(make_backup_dir)"
        backup_existing_installation "$backup_dir"
    fi
    install_umm_files
    install_steam_bundle_launcher
    write_launcher

    if [ -n "$MOD_SOURCE" ]; then
        install_mod_folder "$MOD_SOURCE"
    fi

    info ""
    info "Installation complete."
    info "Launcher: $LAUNCHER"
    info "Steam-compatible in-bundle launcher: installed"
    info "Open UMM in-game with Control+F10."
    if [ -n "$backup_dir" ]; then
        info "Previous loader files were backed up under: $backup_dir"
    fi
    info "Remove any old Steam launch option, then use the normal Steam Play button."
}

add_mod_action() {
    [ -n "$MOD_SOURCE" ] || fail "add-mod requires --mod PATH"
    resolve_game_layout
    [ -f "$UMM_DIR/UnityModManager.dll" ] || fail "UMM is not installed. Run '$SCRIPT_NAME install' first."
    install_mod_folder "$MOD_SOURCE"
}

restore_steam_bundle_launcher() {
    backup_dir="$1"
    [ -f "$STEAM_BUNDLE_MARKER" ] || return

    mkdir -p "$backup_dir/AppExecutable"
    if [ -f "$GAME_BIN" ]; then
        current_hash="$(sha256_file "$GAME_BIN")"
        expected_hash="$(marker_launcher_hash)"
        if [ -n "$expected_hash" ] && [ "$current_hash" = "$expected_hash" ]; then
            [ -f "$ORIGINAL_GAME_BIN" ] || fail "Cannot restore the original ADOFAI executable because its backup is missing."
            cp -p "$GAME_BIN" "$backup_dir/AppExecutable/$EXECUTABLE_NAME.mod-launcher"
            cp -p "$ORIGINAL_GAME_BIN" "$GAME_BIN.restore"
            mv -f "$GAME_BIN.restore" "$GAME_BIN"
            info "Restored ADOFAI's original Steam executable."
        else
            info "Steam already replaced the mod launcher; leaving its current game executable unchanged."
        fi
    fi
    if [ -f "$STEAM_THIN_GAME_BIN" ]; then
        mv "$STEAM_THIN_GAME_BIN" "$backup_dir/AppExecutable/$(basename "$STEAM_THIN_GAME_BIN")"
    fi
}

uninstall_action() {
    resolve_game_layout

    if [ ! -e "$UMM_DIR" ] && [ ! -e "$TOOL_DIR" ] && [ ! -e "$LAUNCHER" ] && [ ! -e "$STEAM_LAUNCHER" ]; then
        info "No installation created by this script was found."
        return
    fi

    backup_dir="$(make_backup_dir)"
    mkdir -p "$backup_dir"

    restore_steam_bundle_launcher "$backup_dir"

    if [ -d "$UMM_DIR" ]; then
        mkdir -p "$backup_dir/Managed"
        mv "$UMM_DIR" "$backup_dir/Managed/UnityModManager"
    fi
    if [ -f "$LAUNCHER" ]; then
        mv "$LAUNCHER" "$backup_dir/run_adofai_umm_macos.sh"
    fi
    if [ -f "$STEAM_LAUNCHER" ]; then
        mv "$STEAM_LAUNCHER" "$backup_dir/run_adofai_umm_from_steam.sh"
    fi
    if [ -d "$TOOL_DIR" ]; then
        mv "$TOOL_DIR" "$backup_dir/.adofai-umm-macos"
    fi

    info "UMM loader and launcher were removed."
    info "They can be recovered from: $backup_dir"
    info "The Mods directory was preserved: $MODS_DIR"
}

parse_args "$@"

case "$ACTION" in
    install) install_action ;;
    add-mod) add_mod_action ;;
    doctor) doctor_action ;;
    uninstall) uninstall_action ;;
    list-mods) list_mods_action ;;
    install-zip) install_zip_action ;;
    enable-mod|disable-mod) set_mod_enabled_action ;;
    remove-mod) remove_mod_action ;;
    install-recommended) install_recommended_action ;;
esac
