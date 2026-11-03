"""Builds the Silica release from one set of sources.

    python src/build_release.py

Reads  src/silica-config.sh, src/*.default.xml, src/install-silica-server.template.sh
Writes egg-silica-linux.json      (PTDL_v2 - imports into Pterodactyl and Pelican)
       install-silica-server.sh   (standalone Linux installer)
Both embed the same config script and templates, so a server behaves the same either way.
Edit the files in src/ and re-run this; never edit the two generated files by hand.
"""
import json, os

src = os.path.dirname(os.path.abspath(__file__))
out = os.path.dirname(src)

def read(name):
    with open(os.path.join(src, name), encoding="utf-8", newline="") as f:
        return f.read().replace("\r\n", "\n")

config_sh = read("silica-config.sh")
ss_default = read("ServerSettings.default.xml")
ms_default = read("MatchSettings.default.xml")
gs_default = read("GameSettings.default.xml")
for name, text in [("silica-config.sh", config_sh), ("ServerSettings.default.xml", ss_default),
                   ("MatchSettings.default.xml", ms_default), ("GameSettings.default.xml", gs_default)]:
    assert text.endswith("\n"), name + " must end with a newline (heredoc terminator)"

VERSION = "1.0.0"      # bump for every release: x.y.Z fixes, x.Y.0 new features, X.0.0 breaking changes
RELEASED = "2026-11-03"  # date of that release (YYYY-MM-DD)
APP_ID, GAME_APP_ID = "2738040", "1494420"
EGG_UUID = "6f0d6f43-6a1e-4a5b-9d7c-5c1a2b0e9e54"  # fixed, so Pelican updates the egg on re-import

def embed(template):
    return (template.replace("__SS_DEFAULT__", ss_default).replace("__MS_DEFAULT__", ms_default)
                    .replace("__GS_DEFAULT__", gs_default)
                    .replace("__CONFIG_SH__", config_sh).replace("__VERSION__", VERSION).replace("__APP_ID__", APP_ID)
                    .replace("__GAME_APP_ID__", GAME_APP_ID))

## standalone installer
installer = embed(read("install-silica-server.template.sh"))
with open(os.path.join(out, "install-silica-server.sh"), "w", encoding="utf-8", newline="\n") as f:
    f.write(installer)

## egg install script (runs in ghcr.io/parkervcp/installers:debian, server files in /mnt/server)
egg_install = embed(r'''#!/bin/bash
# Silica Dedicated Server (Linux) - install script
# Server files: /mnt/server
# A reinstall keeps the game files and settings; it refreshes silica-config.sh and the default templates.

## defaults + config script first, so a failed download still leaves a valid settings file
## HOME=/home/container at runtime -> ~/Silica
mkdir -p /mnt/server/Silica
cat > /mnt/server/Silica/ServerSettings.default.xml <<'SILICA_SS_EOF'
__SS_DEFAULT__SILICA_SS_EOF
cat > /mnt/server/Silica/MatchSettings.default.xml <<'SILICA_MS_EOF'
__MS_DEFAULT__SILICA_MS_EOF
cat > /mnt/server/Silica/GameSettings.default.xml <<'SILICA_GS_EOF'
__GS_DEFAULT__SILICA_GS_EOF
if ! grep -qs '<NetworkServerSettings' /mnt/server/Silica/ServerSettings.xml; then
    cp -v /mnt/server/Silica/ServerSettings.default.xml /mnt/server/Silica/ServerSettings.xml
fi
cat > /mnt/server/silica-config.sh <<'SILICA_CONFIG_EOF'
__CONFIG_SH__SILICA_CONFIG_EOF
chmod +x /mnt/server/silica-config.sh

## the game needs ~9.1 GB installed plus download staging
avail_kb=$(df -Pk /mnt/server | awk 'NR==2 {print $4}')
echo "Free space on the server volume: $((avail_kb / 1024 / 1024)) GB"
if [ "${avail_kb}" -lt 14000000 ]; then
    echo "WARNING: less than ~14 GB free on the node's volume storage - SteamCMD will fail with 'Not enough disk quota'"
fi

## steamcmd (kept in /mnt/server/steamcmd, the runtime image uses it for AUTO_UPDATE)
mkdir -p /mnt/server/steamcmd /mnt/server/steamapps
cd /tmp
curl -sSL -o steamcmd.tar.gz https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xzf steamcmd.tar.gz -C /mnt/server/steamcmd
cd /mnt/server/steamcmd
chown -R root:root /mnt
export HOME=/mnt/server

## game files - the test branch is private and needs the branch password
if [ "${SRCDS_BETAID}" = "test" ] && [ -z "${SRCDS_BETAPASS}" ]; then
    echo "ERROR: branch 'test' is private - set the Branch Password variable and reinstall"
    exit 1
fi
for try in 1 2 3; do
    ./steamcmd.sh +force_install_dir /mnt/server +login anonymous +app_update ${SRCDS_APPID} $( [[ -z ${SRCDS_BETAID} ]] || printf %s "-beta ${SRCDS_BETAID}" ) $( [[ -z ${SRCDS_BETAPASS} ]] || printf %s "-betapassword ${SRCDS_BETAPASS}" ) validate +quit
    [ -f /mnt/server/Silica.x86_64 ] && break
    echo "steamcmd attempt ${try} did not produce Silica.x86_64, retrying"
done
if [ ! -f /mnt/server/Silica.x86_64 ]; then
    echo "Silica.x86_64 not found - check disk space and SRCDS_BETAID / SRCDS_BETAPASS"
    exit 1
fi
chmod +x /mnt/server/Silica.x86_64
grep -h '"buildid"' /mnt/server/steamapps/appmanifest_${SRCDS_APPID}.acf || true

## Steamworks client for SteamGameServer_Init
mkdir -p /mnt/server/.steam/sdk32 /mnt/server/.steam/sdk64
cp -v linux32/steamclient.so /mnt/server/.steam/sdk32/steamclient.so
cp -v linux64/steamclient.so /mnt/server/.steam/sdk64/steamclient.so

echo "-----------------------------------------"
echo "Silica install finished"
echo "-----------------------------------------"
''')

MODES = "MP_Strategy,MP_StrategyCoop,MP_Sandbox,MP_Deathmatch,MP_Prospector,MP_TowerDefense"
OPT = " Leave empty to keep the value in the settings file."

def var(name, desc, env, default, view, edit, rules):
    return {"name": name, "description": desc, "env_variable": env, "default_value": default,
            "user_viewable": view, "user_editable": edit, "rules": rules, "field_type": "text"}

variables = [
    var("Server Name", "ServerName shown in the server browser." + OPT, "SERVER_NAME", "", True, True,
        "nullable|string|max:100"),
    var("Query Port", "Steam query port (QueryPort). Must be a second allocation of this server, usually game port + 1. "
        "The game port is the primary allocation.", "QUERY_PORT", "27016", True, False,
        "required|integer|between:1024,65535"),
    var("Game Mode", "CurrentGameMode: " + MODES.replace(",", ", ") + "." + OPT, "GAME_MODE", "", True, True,
        "nullable|string|in:" + MODES),
    var("Map", "CurrentMap of the active game mode, e.g. GreatErg or IndustrialQuarter." + OPT, "MAP", "", True, True,
        "nullable|string|max:64|regex:/^[A-Za-z0-9_]+$/"),
    var("Map Rotation", "MapList of the active game mode, map names separated by spaces." + OPT, "MAP_LIST", "",
        True, True, "nullable|string|max:1000|regex:/^[A-Za-z0-9_ ]+$/"),
    var("Max Players", "MaxPlayers of the active game mode." + OPT, "MAX_PLAYERS", "", True, True,
        "nullable|integer|between:1,100"),
    var("Server Password", "Join password. Empty = no password (sets PasswordProtected false).", "SERVER_PASSWORD", "",
        True, True, "nullable|string|max:64"),
    var("Admins", "AdminPlayers with root access as SteamID64:Name, comma separated, e.g. "
        "76561190000000001:PlayerOne,76561190000000002:PlayerTwo. Replaces the admins in the file." + OPT,
        "ADMINS", "", True, True, "nullable|string|max:2000"),
    var("Match Settings", "MatchSettings.xml parameters of the active game mode as param=value, comma separated, e.g. "
        "coopdifficulty=2,techmax=8 (Strategy: diststart, resstart, resloc, capmult, techmin, techmax, maxplayerdif, "
        "allowteamswitch; Coop adds coopdifficulty; Deathmatch: bots). Only the listed parameters change." + OPT,
        "MATCH_SETTINGS", "", True, True, "nullable|string|max:500|regex:/^[A-Za-z0-9_]+=[^,=]*(,[A-Za-z0-9_]+=[^,=]*)*$/"),
    var("Max FPS", "MaxFPS in GameSettings.xml, caps the server loop. Idle CPU scales with it: 60 uses ~4x less than "
        "the game default 240, 30 about half of 60." + OPT, "MAX_FPS", "60", True, True, "nullable|integer|between:10,240"),
    var("Game Branch", "Steam branch to install and update: public (official build), beta (public playtest) or test "
        "(private, needs the Branch Password). Takes effect on the next start (Auto Update) or reinstall.",
        "SRCDS_BETAID", "public", True, True, "required|string|in:public,beta,test"),
    var("Branch Password", "Password for the private test branch. Required for test, ignored for public and beta.",
        "SRCDS_BETAPASS", "", False, False, "nullable|required_if:environment.SRCDS_BETAID,test|string|max:128"),
    var("Auto Update", "Update the server through SteamCMD on every start (1 = yes, 0 = no).", "AUTO_UPDATE",
        "1", True, True, "required|boolean"),
    var("SteamCMD App ID", "Silica Dedicated Server app.", "SRCDS_APPID", APP_ID, False, False,
        "required|string|in:" + APP_ID),
    var("Steam App ID", "Game app ID that Steamworks needs at runtime.", "SteamAppId", GAME_APP_ID, False, False,
        "required|string|in:" + GAME_APP_ID),
    var("Steam Game ID", "Game ID that Steamworks needs at runtime.", "SteamGameId", GAME_APP_ID, False, False,
        "required|string|in:" + GAME_APP_ID),
]

egg = {
    "_comment": "DO NOT EDIT: FILE GENERATED AUTOMATICALLY BY PTERODACTYL PANEL - PTERODACTYL.IO",
    "meta": {"version": "PTDL_v2", "update_url": None},
    "exported_at": RELEASED + "T00:00:00+00:00",
    "uuid": EGG_UUID,
    "name": "Silica (Linux)",
    "author": "Jaqquca@users.noreply.github.com",
    "description": "Silica Dedicated Server (Steam app 2738040), native Linux build. Join works over the Steam relay "
                   "network (no port forwarding needed); only the query port is bound. Needs 12-16 GB RAM and ~20 GB "
                   "disk. All game settings are optional variables: empty keeps the value in ~/Silica/*.xml. "
                   f"silica-linux-server v{VERSION} - https://github.com/Jaqquca/silica-linux-server",
    "features": None,
    "docker_images": {
        "SteamCMD Debian": "ghcr.io/parkervcp/steamcmd:debian",
        "SteamCMD Ubuntu": "ghcr.io/parkervcp/steamcmd:ubuntu",
    },
    "file_denylist": [],
    # silica-config.sh (written by the installer) applies the optional variables to the XML files
    "startup": "bash silica-config.sh && ./Silica.x86_64 -logFile -",
    "config": {
        "files": "{}",
        "startup": json.dumps({"done": "Game server connected to Steam successfully"}),
        "logs": "{}",
        "stop": "^C",
    },
    "scripts": {"installation": {"script": egg_install, "container": "ghcr.io/parkervcp/installers:debian",
                                 "entrypoint": "bash"}},
    "variables": variables,
}
with open(os.path.join(out, "egg-silica-linux.json"), "w", encoding="utf-8", newline="\n") as f:
    json.dump(egg, f, indent=4, ensure_ascii=False)
    f.write("\n")
print("wrote", os.path.join(out, "egg-silica-linux.json"))
print("wrote", os.path.join(out, "install-silica-server.sh"))
