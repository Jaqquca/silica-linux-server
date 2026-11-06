#!/usr/bin/env bash
# Silica Dedicated Server - standalone installer for Linux (Debian / Ubuntu, x86_64)
# silica-linux-server v__VERSION__ - https://github.com/Jaqquca/silica-linux-server
#
# Installs SteamCMD and the Silica dedicated server into one folder, writes the settings files and the
# same config script the Pterodactyl/Pelican egg uses, and (as root) sets up a systemd service.
# Re-run it any time to update or repair the install - your settings in silica.env and Silica/*.xml are kept.
#
#   sudo bash install-silica-server.sh                    # /opt/silica, user "silica", service "silica", started
#   sudo bash install-silica-server.sh --name silica2 --game-port 27017 --query-port 27018   # a second server
#   bash install-silica-server.sh --dir ~/silica          # without root: own folder, no service
#
# Options:
#   --name NAME            service / instance name (default: silica)
#   --dir DIR              install folder (default: /opt/NAME as root, ~/NAME otherwise)
#   --user USER            system user that runs the server (root only, default: NAME)
#   --game-port PORT       game port for a new install (default 27015)
#   --query-port PORT      query port for a new install (default 27016)
#   --branch BRANCH        public | beta | test (default: public)
#   --branch-password PW   password for a private branch (test)
#   --no-service           don't create a systemd service
#   --no-start             create the service but don't start it
#   --melonloader          install MelonLoader for server-side mods (needs glibc 2.38+: Ubuntu 24.04+, Debian 13+)
#   --no-melonloader       start without MelonLoader again (files stay)
#   --melonloader-version V   MelonLoader release to install (default: __MELONLOADER_VERSION__)
#   --version              print the version and exit
#
# Requirements: x86_64 Debian 11+ / Ubuntu 20.04+, ~14 GB free disk, 12-16 GB RAM, outbound internet.
# Players join over the Steam relay network, so no port forwarding is needed.
set -euo pipefail

VERSION=__VERSION__
APP_ID=2738040          # Silica Dedicated Server (SteamCMD)
GAME_APP_ID=1494420     # Silica, needed by Steamworks at runtime
NEED_DISK_KB=14000000   # ~9.1 GB installed + download staging
NEED_RAM_KB=12000000

NAME=silica; DIR=""; RUN_USER=""; GAME_PORT=27015; QUERY_PORT=27016
BRANCH=""; BRANCH_PASSWORD=""; SERVICE=1; START=1
MELONLOADER=""; ML_VERSION=""   # empty = keep what silica.env says

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --name) NAME=$2; shift 2 ;;
        --dir) DIR=$2; shift 2 ;;
        --user) RUN_USER=$2; shift 2 ;;
        --game-port) GAME_PORT=$2; shift 2 ;;
        --query-port) QUERY_PORT=$2; shift 2 ;;
        --branch) BRANCH=$2; shift 2 ;;
        --branch-password) BRANCH_PASSWORD=$2; shift 2 ;;
        --no-service) SERVICE=0; shift ;;
        --no-start) START=0; shift ;;
        --melonloader) MELONLOADER=1; shift ;;
        --no-melonloader) MELONLOADER=0; shift ;;
        --melonloader-version) ML_VERSION=${2#v}; MELONLOADER=${MELONLOADER:-1}; shift 2 ;;
        -h|--help) sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d'; exit 0 ;;
        --version) echo "silica-linux-server v$VERSION"; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

[[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || die "--name may only contain letters, digits, - and _"
[[ -z "$BRANCH" || "$BRANCH" =~ ^(public|beta|test)$ ]] || die "--branch must be public, beta or test"
[ "$(uname -m)" = "x86_64" ] || die "Silica's Linux server is x86_64 only (this machine: $(uname -m))"

if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT=1; DIR=${DIR:-/opt/$NAME}; RUN_USER=${RUN_USER:-$NAME}
else
    IS_ROOT=0; DIR=${DIR:-$HOME/$NAME}; RUN_USER=$(id -un); SERVICE=0
fi
DIR=$(realpath -m "$DIR")

## system checks ---------------------------------------------------------------------------------------
ram_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
[ "$ram_kb" -ge "$NEED_RAM_KB" ] || warn "only $((ram_kb / 1024 / 1024)) GB RAM - Silica needs 12-16 GB (City of Naraka uses ~11 GB)"
mkdir -p "$DIR" 2>/dev/null || die "cannot create $DIR (run with sudo, or pick another --dir)"
free_kb=$(df -Pk "$DIR" | awk 'NR==2 {print $4}')
info "silica-linux-server v$VERSION - installing to $DIR ($((free_kb / 1024 / 1024)) GB free)"
[ -f "$DIR/Silica.x86_64" ] || [ "$free_kb" -ge "$NEED_DISK_KB" ] || \
    warn "less than 14 GB free on $DIR - SteamCMD will probably fail with 'Not enough disk quota'"

## packages --------------------------------------------------------------------------------------------
if [ "$IS_ROOT" -eq 1 ] && command -v apt-get >/dev/null; then
    info "Installing packages (curl, ca-certificates, tar, unzip, 32-bit libgcc for SteamCMD)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    lib32=lib32gcc-s1; apt-cache show lib32gcc-s1 >/dev/null 2>&1 || lib32=lib32gcc1
    apt-get install -y -qq curl ca-certificates tar unzip "$lib32" >/dev/null
elif [ "$IS_ROOT" -eq 1 ]; then
    warn "no apt-get: install curl, ca-certificates, tar and 32-bit libgcc yourself if SteamCMD fails"
else
    for c in curl tar; do command -v "$c" >/dev/null || die "'$c' is missing - install it or run with sudo"; done
fi

## user ------------------------------------------------------------------------------------------------
if [ "$IS_ROOT" -eq 1 ] && ! id "$RUN_USER" >/dev/null 2>&1; then
    info "Creating system user $RUN_USER (home $DIR)"
    useradd --system --home-dir "$DIR" --shell /usr/sbin/nologin "$RUN_USER"
fi
as_user() {
    if [ "$IS_ROOT" -eq 1 ]; then runuser -u "$RUN_USER" -- env HOME="$DIR" "$@"; else env HOME="$DIR" "$@"; fi
}
[ "$IS_ROOT" -eq 1 ] && chown "$RUN_USER": "$DIR"

## settings (silica.env is created once and never overwritten) ------------------------------------------
cd "$DIR"
if [ ! -f silica.env ]; then
    info "Writing $DIR/silica.env"
    cat > silica.env <<EOF
# Silica server settings. Empty = keep the value in Silica/ServerSettings.xml (or the game default).
# Restart the server after changing anything here.

SERVER_NAME="Silica Server"
GAME_PORT=$GAME_PORT
QUERY_PORT=$QUERY_PORT

# MP_Strategy, MP_StrategyCoop, MP_Sandbox, MP_Deathmatch, MP_Prospector, MP_TowerDefense
GAME_MODE=
# map of the active mode, e.g. GreatErg, NarakaCity, IndustrialQuarter, CrystalChasm
MAP=
# map rotation of the active mode, space separated, e.g. "GreatErg NarakaCity"
MAP_LIST=
MAX_PLAYERS=
# join password, empty = no password
SERVER_PASSWORD=
# admins with root access: SteamID64:Name, comma separated, e.g. 76561190000000001:PlayerOne
ADMINS=
# MatchSettings.xml parameters of the active mode, e.g. coopdifficulty=2,techmax=8
MATCH_SETTINGS=
# server frame cap; 60 uses ~4x less CPU than the game's default 240
MAX_FPS=60

# Steam branch: public (official build), beta (public playtest) or test (private, needs BRANCH_PASSWORD)
BRANCH=public
BRANCH_PASSWORD=
# update through SteamCMD on every start (1 = yes, 0 = no)
AUTO_UPDATE=1
EOF
fi
# settings added in later versions - appended once to an older silica.env
if ! grep -q '^MELONLOADER=' silica.env; then
    cat >> silica.env <<'EOF'

# MelonLoader for server-side mods (1 = load it, 0 = plain server). Mods go into Mods/, their settings into UserData/.
# Needs glibc 2.38+ (Ubuntu 24.04+, Debian 13+). Change it with: install-silica-server.sh --melonloader / --no-melonloader
MELONLOADER=0
MELONLOADER_VERSION=__MELONLOADER_VERSION__
EOF
fi
# command line overrides values in an existing silica.env
[ -n "$BRANCH" ] && sed -i "s|^BRANCH=.*|BRANCH=$BRANCH|" silica.env
[ -n "$BRANCH_PASSWORD" ] && sed -i "s|^BRANCH_PASSWORD=.*|BRANCH_PASSWORD=$BRANCH_PASSWORD|" silica.env
[ -n "$MELONLOADER" ] && sed -i "s|^MELONLOADER=.*|MELONLOADER=$MELONLOADER|" silica.env
[ -n "$ML_VERSION" ] && sed -i "s|^MELONLOADER_VERSION=.*|MELONLOADER_VERSION=$ML_VERSION|" silica.env
chmod 600 silica.env
MELONLOADER=$(sed -n 's/^MELONLOADER=//p' silica.env); ML_VERSION=$(sed -n 's/^MELONLOADER_VERSION=//p' silica.env)

## templates + config script (always refreshed) --------------------------------------------------------
mkdir -p Silica
cat > Silica/ServerSettings.default.xml <<'SILICA_SS_EOF'
__SS_DEFAULT__SILICA_SS_EOF
cat > Silica/MatchSettings.default.xml <<'SILICA_MS_EOF'
__MS_DEFAULT__SILICA_MS_EOF
cat > Silica/GameSettings.default.xml <<'SILICA_GS_EOF'
__GS_DEFAULT__SILICA_GS_EOF
grep -qs '<NetworkServerSettings' Silica/ServerSettings.xml || cp Silica/ServerSettings.default.xml Silica/ServerSettings.xml
cat > silica-config.sh <<'SILICA_CONFIG_EOF'
__CONFIG_SH__SILICA_CONFIG_EOF
cat > silica-launch.sh <<'SILICA_LAUNCH_EOF'
__LAUNCH_SH__SILICA_LAUNCH_EOF

cat > update.sh <<'SILICA_UPDATE_EOF'
#!/usr/bin/env bash
# Installs / updates the game through SteamCMD with the branch from silica.env.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
set -a; . ./silica.env; set +a
export HOME="$PWD"
if [ "${BRANCH:-public}" = "test" ] && [ -z "${BRANCH_PASSWORD:-}" ]; then
    echo "ERROR: branch 'test' is private - set BRANCH_PASSWORD in silica.env"; exit 1
fi
args=(+force_install_dir "$PWD" +login anonymous +app_update __APP_ID__ -beta "${BRANCH:-public}")
[ -n "${BRANCH_PASSWORD:-}" ] && args+=(-betapassword "$BRANCH_PASSWORD")
[ "${1:-}" = "--validate" ] && args+=(validate)
for try in 1 2 3; do
    ./steamcmd/steamcmd.sh "${args[@]}" +quit && [ -f Silica.x86_64 ] && break
    echo "steamcmd attempt $try failed, retrying"; sleep 5
done
[ -f Silica.x86_64 ] || { echo "ERROR: Silica.x86_64 not installed - check disk space and the branch settings"; exit 1; }
chmod +x Silica.x86_64
mkdir -p .steam/sdk32 .steam/sdk64
cp -f steamcmd/linux32/steamclient.so .steam/sdk32/steamclient.so
cp -f steamcmd/linux64/steamclient.so .steam/sdk64/steamclient.so
grep -h '"buildid"' steamapps/appmanifest___APP_ID__.acf 2>/dev/null | head -n 1 || true
SILICA_UPDATE_EOF

cat > start.sh <<'SILICA_START_EOF'
#!/usr/bin/env bash
# Starts the Silica server: optional update, apply silica.env to the XML files, run the game.
cd "$(dirname "$(readlink -f "$0")")"
set -a; . ./silica.env; set +a
export HOME="$PWD" SILICA_DIR="$PWD" SERVER_PORT="${GAME_PORT:-27015}" SteamAppId=__GAME_APP_ID__ SteamGameId=__GAME_APP_ID__
if [ "${AUTO_UPDATE:-1}" = "1" ]; then ./update.sh || echo "[start] update failed - starting the installed version"; fi
bash silica-config.sh || exit 1
exec bash silica-launch.sh
SILICA_START_EOF

cat > joinid.sh <<'SILICA_JOINID_EOF'
#!/usr/bin/env bash
# Prints the server's Steam ID (the join ID). It changes on every restart.
cd "$(dirname "$(readlink -f "$0")")"
log=$(ls -1t Silica/Server_*.log 2>/dev/null | head -n 1)
[ -n "$log" ] || { echo "no server log yet - is the server running?"; exit 1; }
grep -h 'Game server SteamID' "$log" | tail -n 1 | sed 's/.*SteamID://'
SILICA_JOINID_EOF
chmod +x update.sh start.sh joinid.sh silica-config.sh silica-launch.sh

## SteamCMD + game -------------------------------------------------------------------------------------
if [ ! -x steamcmd/steamcmd.sh ]; then
    info "Downloading SteamCMD"
    mkdir -p steamcmd steamapps
    curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz -C steamcmd
fi
[ "$IS_ROOT" -eq 1 ] && chown -R "$RUN_USER": "$DIR"
info "Installing / updating the game (about 9 GB on the first run, this takes a while)"
as_user ./update.sh --validate

## MelonLoader (optional) -------------------------------------------------------------------------------
if [ "$MELONLOADER" = "1" ]; then
    glibc=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')
    if [ "$(printf '%s\n' 2.38 "${glibc:-0}" | sort -V | head -n 1)" != "2.38" ]; then
        warn "MelonLoader needs glibc 2.38+, this system has ${glibc:-unknown} (use Ubuntu 24.04+ / Debian 13+) - setting MELONLOADER=0"
        sed -i "s|^MELONLOADER=.*|MELONLOADER=0|" silica.env; MELONLOADER=0
    elif [ "$(cat MelonLoader/.silica-installed-version 2>/dev/null)" = "$ML_VERSION" ]; then
        info "MelonLoader $ML_VERSION already installed"
    else
        command -v unzip >/dev/null || die "'unzip' is missing - install it or run with sudo"
        info "Installing MelonLoader $ML_VERSION (glibc $glibc)"
        tmp=$(mktemp -d)
        curl -fsSL -o "$tmp/ml.zip" "https://github.com/LavaGang/MelonLoader/releases/download/v$ML_VERSION/MelonLoader.Linux.x64.zip" \
            || die "could not download MelonLoader v$ML_VERSION"
        unzip -oq "$tmp/ml.zip" -d "$DIR" && rm -rf "$tmp"
        mkdir -p Mods Plugins UserData UserLibs
        echo "$ML_VERSION" > MelonLoader/.silica-installed-version
        [ "$IS_ROOT" -eq 1 ] && chown -R "$RUN_USER": "$DIR"
    fi
fi

## systemd service -------------------------------------------------------------------------------------
if [ "$SERVICE" -eq 1 ] && command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then
    info "Creating systemd service $NAME.service"
    cat > "/etc/systemd/system/$NAME.service" <<EOF
[Unit]
Description=Silica Dedicated Server ($NAME)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$DIR
ExecStart=$DIR/start.sh
Restart=on-failure
RestartSec=20
KillSignal=SIGINT
TimeoutStopSec=60
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "$NAME.service" >/dev/null
    if [ "$START" -eq 1 ]; then systemctl restart "$NAME.service"; info "Service $NAME started"; fi
elif [ "$SERVICE" -eq 1 ]; then
    warn "systemd not available - no service created"; SERVICE=0
fi
START_CMD="$DIR/start.sh"
[ "$IS_ROOT" -eq 1 ] && START_CMD="runuser -u $RUN_USER -- $DIR/start.sh"   # never as root, files must stay owned by $RUN_USER

## done ------------------------------------------------------------------------------------------------
cat <<EOF

Silica server "$NAME" is installed in $DIR
  Settings:   $DIR/silica.env   (restart after changes)
  Game files: $DIR/Silica/ServerSettings.xml, MatchSettings.xml, GameSettings.xml
EOF
if [ "$SERVICE" -eq 1 ]; then cat <<EOF
  Start/stop: sudo systemctl start|stop|restart $NAME
  Console:    sudo journalctl -u $NAME -f
EOF
else cat <<EOF
  Start:      $START_CMD   (keep it running, e.g. inside tmux or screen; stop with Ctrl+C)
EOF
fi
cat <<EOF
  Join ID:    $DIR/joinid.sh   (after the log shows "Game server connected to Steam successfully")
  Update:     restart the server (AUTO_UPDATE=1) or run $DIR/update.sh
EOF
if [ "$MELONLOADER" = "1" ]; then cat <<EOF
  MelonLoader: v$ML_VERSION - put mods into $DIR/Mods, their settings live in $DIR/UserData,
              log: $DIR/MelonLoader/Latest.log
EOF
fi
