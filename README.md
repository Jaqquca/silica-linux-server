# Silica Dedicated Server on Linux

Run your own [Silica](https://store.steampowered.com/app/1494420/Silica/) dedicated server on Linux, either:

- **with a game panel:** import the egg into **Pterodactyl** or **Pelican**, or
- **on a plain Linux machine:** run one installer script, which sets everything up, including a systemd service.

Both use the same settings script, so a server behaves the same either way.

## Requirements

| | |
|---|---|
| OS | 64-bit Linux (x86_64). The script supports Debian 11+ and Ubuntu 20.04+. |
| RAM | 12 GB minimum, **16 GB recommended** (the City of Naraka map uses ~11 GB) |
| Disk | ~20 GB (9.1 GB game, plus room for downloads during updates) |
| CPU | ~1–2 cores idle at 30–60 FPS (see *Max FPS* below), more with players |
| Network | Outbound internet. **No port forwarding needed:** players connect through the Steam relay network. |
| Ports | Game port (default 27015) and query port (default 27016) on the machine itself |

## Option A: standalone installer (any Linux machine)

```bash
curl -fsSLO https://raw.githubusercontent.com/Jaqquca/silica-linux-server/main/install-silica-server.sh
sudo bash install-silica-server.sh
```

This does the following:

1. installs the packages SteamCMD needs (`curl`, `ca-certificates`, `tar`, 32-bit `libgcc`)
2. creates a system user `silica` and installs everything into `/opt/silica`
3. downloads SteamCMD and the game (about 9 GB, which takes a while the first time)
4. writes the settings file `/opt/silica/silica.env` and the game's default XML files
5. creates and starts the service `silica.service`

Afterwards:

| Task | Command |
|---|---|
| Change settings | `sudo nano /opt/silica/silica.env`, then `sudo systemctl restart silica` |
| Console / log | `sudo journalctl -u silica -f` |
| Start / stop | `sudo systemctl start silica` / `sudo systemctl stop silica` |
| Join ID | `sudo /opt/silica/joinid.sh` (changes on every restart) |
| Update | just restart (it updates on every start), or `sudo -u silica /opt/silica/update.sh` |
| Repair / reinstall | run the installer again; your settings are kept |

**A second server on the same machine:**

```bash
sudo bash install-silica-server.sh --name silica2 --game-port 27017 --query-port 27018
```

**Without root** (no service; you need `curl` and `tar`, plus 32-bit `libgcc`, already installed):

```bash
bash install-silica-server.sh --dir ~/silica
~/silica/start.sh        # keep it running, e.g. inside tmux or screen
```

Run `bash install-silica-server.sh --help` for all options.

## Option B: Pterodactyl / Pelican egg

1. Download [`egg-silica-linux.json`](https://raw.githubusercontent.com/Jaqquca/silica-linux-server/main/egg-silica-linux.json). In **Admin → Nests** (Pelican: **Eggs**) **→ Import Egg**, upload it and choose a nest.
   Pelican can also import it straight from that URL.
2. Create a server from the egg:
    - **two allocations:** the game port (primary) and the query port, usually game port + 1. Set **Query Port** to the second one.
    - **16 GB RAM, 0 swap, ~20 GB disk**
3. Start it. The first start installs SteamCMD and the game, and takes a few minutes. The panel shows the server as running once the console prints `Game server connected to Steam successfully`.

The node needs at least ~14 GB **free** disk during the install, otherwise SteamCMD fails with `Not enough disk quota`.

## Settings

Every setting is **optional**: leave it empty and the value already in the game's settings files is kept. So you can copy the `ServerSettings.xml`, `MatchSettings.xml` and `GameSettings.xml` from an existing Windows server (`Documents\Silica\`) into the server's `Silica/` folder, and it runs with exactly those settings.

In the egg these are the panel variables. In the standalone install they are the lines in `silica.env`.

| Setting | Egg variable / `silica.env` | Example | Effect |
|---|---|---|---|
| Server name | `SERVER_NAME` | `My Silica Server` | Name in the server browser |
| Game mode | `GAME_MODE` | `MP_Strategy` | `MP_Strategy`, `MP_StrategyCoop`, `MP_Sandbox`, `MP_Deathmatch`, `MP_Prospector`, `MP_TowerDefense` |
| Map | `MAP` | `GreatErg` | Starting map of the active mode |
| Map rotation | `MAP_LIST` | `GreatErg NarakaCity` | Map list of the active mode |
| Max players | `MAX_PLAYERS` | `24` | Player limit of the active mode |
| Password | `SERVER_PASSWORD` | `secret` | Join password; **empty = no password** |
| Admins | `ADMINS` | `76561190000000001:PlayerOne` | Admins with root access (SteamID64:Name, comma separated) |
| Match settings | `MATCH_SETTINGS` | `coopdifficulty=2,techmax=8` | Match parameters of the active mode |
| Max FPS | `MAX_FPS` | `60` | Server frame cap (see below) |
| Branch | `SRCDS_BETAID` / `BRANCH` | `public` | `public`, `beta`, or `test` (private, needs a password) |
| Auto update | `AUTO_UPDATE` | `1` | Update through SteamCMD on every start |
| Ports | allocations / `GAME_PORT`, `QUERY_PORT` | `27015` / `27016` | Always applied |

Map, map rotation and max players only change the settings block of the **active** game mode. The other modes keep theirs.

**Match parameters seen so far:**

- **Strategy:** `diststart`, `resstart`, `resloc`, `capmult`, `techmin`, `techmax`, `maxplayerdif`, `allowteamswitch`
- **Strategy Coop:** the same, plus `coopdifficulty`
- **Deathmatch:** `bots`

### Max FPS

Even with nobody connected, the server runs its game loop at the frame cap. The game's default is 240, which keeps 7–10 CPU cores busy on an empty server. Measured on an idle server (Xeon E5-2697A v4):

| Frame cap | Idle CPU |
|---|---|
| 240 (game default) | 6.7–10 cores |
| 120 | 3.5–6.9 cores |
| **60 (default here)** | 1.8–3.3 cores |
| 30 | 1.0–1.8 cores |

Bohemia Interactive describes 30 FPS as the lowest cap that doesn't affect player experience.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Not enough disk quota` / state `0x202` from SteamCMD | Not enough free disk (~14 GB needed during install/update) |
| `Steamworks is not initialized` / `Aborting server startup` | Keep `IP="0"` in ServerSettings.xml; the scripts force it. Check that `.steam/sdk64/steamclient.so` exists (re-run the installer / reinstall). |
| Killed, exit code 137 / "out of memory" | Give the server more RAM (16 GB) |
| High CPU with nobody online | Lower `MAX_FPS` (60 or 30) |
| Players don't see the server | Wait for `Steam relay network and server certificate available` in the log; join by the ID from `joinid.sh` (or `Game server SteamID` in the log) |

## Repository layout

| Path | What it is |
|---|---|
| `egg-silica-linux.json` | The egg (PTDL_v2; imports into Pterodactyl and Pelican). **Generated.** |
| `install-silica-server.sh` | The standalone installer. **Generated.** It writes `silica.env`, `start.sh`, `update.sh`, `joinid.sh`, `silica-config.sh` and the default XML templates into the install folder. |
| `src/silica-config.sh` | Applies the settings to the game's XML files before every start; shared by both. |
| `src/*.default.xml` | Default ServerSettings / MatchSettings / GameSettings templates. |
| `src/install-silica-server.template.sh` | Source of the standalone installer. |
| `src/build_release.py` | Builds both generated files from `src/`. |

**Changing something:** edit the files in `src/`, then run `python src/build_release.py` and commit the regenerated files. Never edit the two generated files by hand.

## License

[MIT](LICENSE). Silica is a game by Bohemia Interactive; this project isn't affiliated with Bohemia Interactive or Valve.
