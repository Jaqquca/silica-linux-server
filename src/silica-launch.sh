#!/bin/bash
# Silica launch: starts the server, with MelonLoader (server-side mods) when MELONLOADER=1.
# Shared by the egg (startup command) and the standalone start.sh. Runs after silica-config.sh.
# If MelonLoader is missing or the system is too old for it, the server starts without mods instead of not at all.

# SILICA_DIR is set by the standalone start.sh; in Pterodactyl/Pelican the server lives in /home/container
cd "${SILICA_DIR:-/home/container}" 2>/dev/null || cd "$(dirname "$0")" || exit 1

if [ "${MELONLOADER:-0}" = "1" ]; then
    glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')
    if [ ! -f MelonLoader.Bootstrap.so ]; then
        echo "[silica-launch] MELONLOADER=1 but MelonLoader is not installed (reinstall the server / run the installer with --melonloader) - starting without mods"
    elif [ "$(printf '%s\n' 2.38 "${glibc:-0}" | sort -V | head -n 1)" != "2.38" ]; then
        echo "[silica-launch] MelonLoader needs glibc 2.38+, this system has ${glibc:-unknown} (panel: use the Ubuntu image) - starting without mods"
    else
        # MelonWiki "Linux Native Games": game folder in LD_LIBRARY_PATH, bootstrap preloaded by file name only.
        # Silica_Data/Plugins is needed as well: with MelonLoader in place the game no longer finds libsteam_api64.so otherwise.
        export LD_LIBRARY_PATH="$PWD:$PWD/Silica_Data/Plugins${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        export LD_PRELOAD="MelonLoader.Bootstrap.so${LD_PRELOAD:+:$LD_PRELOAD}"
        echo "[silica-launch] MelonLoader enabled - mods from $PWD/Mods"
    fi
fi

exec ./Silica.x86_64 -logFile -
