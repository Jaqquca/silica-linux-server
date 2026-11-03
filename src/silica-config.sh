#!/bin/bash
# Silica config: applies the egg variables to ~/Silica/*.xml before the game starts.
# Every variable is optional - an empty one leaves the value in the file alone.
# Always set: GamePort/QueryPort from the allocations, IP="0" (a real address makes SteamGameServer_Init fail),
# PasswordProtected/ServerPassword from SERVER_PASSWORD (empty = no password).
# The files are edited line by line, which matches how the game writes them (one element per line).

# SILICA_DIR is set by the standalone start.sh; in Pterodactyl/Pelican the server lives in /home/container
cd "${SILICA_DIR:-/home/container}" 2>/dev/null || cd "$(dirname "$0")" || exit 1
DIR=Silica
SS=$DIR/ServerSettings.xml
MS=$DIR/MatchSettings.xml
GS=$DIR/GameSettings.xml
mkdir -p "$DIR"

log() { echo "[silica-config] $*"; }

if ! grep -qs '<NetworkServerSettings' "$SS"; then
    log "$SS missing or invalid, restoring $DIR/ServerSettings.default.xml"
    cp "$DIR/ServerSettings.default.xml" "$SS" || exit 1
fi
if [ -n "${MATCH_SETTINGS}" ] && ! grep -qs '<MatchSettings' "$MS"; then
    log "$MS missing, restoring $DIR/MatchSettings.default.xml"
    cp "$DIR/MatchSettings.default.xml" "$MS" || exit 1
fi

# Active mode: GAME_MODE if set, else whatever the file has
MODE=${GAME_MODE:-$(sed -n 's/.*<NetworkServerSettings[^>]* CurrentGameMode="\([^"]*\)".*/\1/p' "$SS" | head -n 1)}
export MODE

# Shared awk helpers: XML-escape a value, set or add an attribute on a single-line element
AWK_LIB='
function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); return s }
function setattr(line, name, val) {
    val = esc(val)
    if (match(line, " " name "=\"[^\"]*\""))
        return substr(line, 1, RSTART - 1) " " name "=\"" val "\"" substr(line, RSTART + RLENGTH)
    if (match(line, / *\/?> *$/))
        return substr(line, 1, RSTART - 1) " " name "=\"" val "\"" substr(line, RSTART)
    return line
}
function trim(s) { gsub(/^ +| +$/, "", s); return s }
'

# rewrite FILE AWK_PROGRAM - runs the program over FILE (CRLF stripped) and replaces it in place
rewrite() {
    awk "${AWK_LIB}$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

rewrite "$SS" '
function modeattrs(line) {
    if (ENVIRON["MAP"] != "")         line = setattr(line, "CurrentMap", ENVIRON["MAP"])
    if (ENVIRON["MAP_LIST"] != "")    line = setattr(line, "MapList", ENVIRON["MAP_LIST"])
    if (ENVIRON["MAX_PLAYERS"] != "") line = setattr(line, "MaxPlayers", ENVIRON["MAX_PLAYERS"])
    return line
}
BEGIN { mode = ENVIRON["MODE"]; admins = ENVIRON["ADMINS"] }
{ sub(/\r$/, "") }
/<NetworkServerSettings[ >]/ {
    if (ENVIRON["SERVER_NAME"] != "") $0 = setattr($0, "ServerName", ENVIRON["SERVER_NAME"])
    if (ENVIRON["GAME_MODE"] != "")   $0 = setattr($0, "CurrentGameMode", ENVIRON["GAME_MODE"])
    pw = ENVIRON["SERVER_PASSWORD"]
    $0 = setattr($0, "PasswordProtected", pw != "" ? "true" : "false")
    $0 = setattr($0, "ServerPassword", pw)
    $0 = setattr($0, "IP", "0")
    if (ENVIRON["SERVER_PORT"] != "") $0 = setattr($0, "GamePort", ENVIRON["SERVER_PORT"])
    if (ENVIRON["QUERY_PORT"] != "")  $0 = setattr($0, "QueryPort", ENVIRON["QUERY_PORT"])
}
/<GameModeSettings / && mode != "" && index($0, " GameMode=\"" mode "\"") { found = 1; $0 = modeattrs($0) }
/<AdminPlayers / && admins != "" { next }
/<\/NetworkServerSettings>/ {
    if (!found && mode != "") print modeattrs("  <GameModeSettings GameMode=\"" esc(mode) "\" />")
    if (admins != "") {
        n = split(admins, list, ",")
        for (i = 1; i <= n; i++) {
            entry = trim(list[i]); if (entry == "") continue
            p = index(entry, ":")
            id = trim(p ? substr(entry, 1, p - 1) : entry); name = trim(p ? substr(entry, p + 1) : "")
            if (id !~ /^[0-9]+$/) { print "[silica-config] skipping admin with invalid SteamID64: " entry > "/dev/stderr"; continue }
            print "  <AdminPlayers ID=\"" id "\" Name=\"" esc(name) "\" RootAccess=\"true\" />"
        }
    }
}
{ print }
'

if [ -n "${MATCH_SETTINGS}" ]; then
    rewrite "$MS" '
    function emit_missing(   i) { for (i = 1; i <= nk; i++) if (!done[keys[i]]) print "    <Settings Param=\"" esc(keys[i]) "\" Value=\"" esc(vals[keys[i]]) "\" />" }
    BEGIN {
        mode = ENVIRON["MODE"]
        n = split(ENVIRON["MATCH_SETTINGS"], kv, ",")
        for (i = 1; i <= n; i++) {
            p = index(kv[i], "="); if (!p) continue
            k = trim(substr(kv[i], 1, p - 1)); if (k == "") continue
            keys[++nk] = k; vals[k] = trim(substr(kv[i], p + 1))
        }
    }
    { sub(/\r$/, "") }
    inblock && /<\/GameModes>/ { emit_missing(); inblock = 0 }
    inblock && /<Settings / {
        for (i = 1; i <= nk; i++) if (index($0, " Param=\"" keys[i] "\"")) { $0 = setattr($0, "Value", vals[keys[i]]); done[keys[i]] = 1 }
    }
    /<GameModes / && index($0, " GameMode=\"" mode "\"") {
        found = 1
        if ($0 ~ /\/> *$/) { sub(/ *\/> *$/, ">"); print; emit_missing(); print "  </GameModes>"; next }
        inblock = 1
    }
    /<\/MatchSettings>/ && !found { print "  <GameModes GameMode=\"" esc(mode) "\">"; emit_missing(); print "  </GameModes>" }
    { print }
    '
fi

if [ -n "${MAX_FPS}" ]; then
    # the game only writes GameSettings.xml on its first start - seed it so the cap holds from the very first start
    if ! grep -qs '<GameSettings' "$GS" && [ -f "$DIR/GameSettings.default.xml" ]; then
        log "$GS missing, restoring $DIR/GameSettings.default.xml"
        cp "$DIR/GameSettings.default.xml" "$GS"
    fi
    if [ -f "$GS" ]; then
        rewrite "$GS" '{ sub(/\r$/, "") } /<VideoSettings / { $0 = setattr($0, "MaxFPS", ENVIRON["MAX_FPS"]) } { print }'
    else
        log "$GS not created by the game yet, MAX_FPS applies from the next start"
    fi
fi

log "mode=${MODE:-?} name=${SERVER_NAME:-(file)} map=${MAP:-(file)} max_players=${MAX_PLAYERS:-(file)} ports=${SERVER_PORT}/${QUERY_PORT} password=$([ -n "${SERVER_PASSWORD}" ] && echo yes || echo no) admins=$([ -n "${ADMINS}" ] && echo set || echo '(file)') match=${MATCH_SETTINGS:-(file)} max_fps=${MAX_FPS:-(file)}"
