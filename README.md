# Silica Dedicated Server on Linux

Run your own [Silica](https://store.steampowered.com/app/1494420/Silica/) dedicated server on Linux, either:

- **with a game panel:** import the egg into **Pterodactyl** or **Pelican**, or
- **on a plain Linux machine:** run one installer script, which sets everything up, including a systemd service.

Both use the same settings script, so a server behaves the same either way. Since v1.1.0 both can also load **server-side mods** with MelonLoader (optional, off by default; see [Server-side mods](#server-side-mods-melonloader)).

## Status

**Provided as is, not maintained.** This repository is a finished snapshot, not a service. Issues and pull requests aren't monitored.

- To build on it, click **Use this template**. You get your own independent repository and become the maintainer of your copy. Forking works too.
- The MIT license asks you to keep the copyright notice, which keeps the original credit with every copy.
- The game itself updates through SteamCMD on every server start, so you don't need a new release of this project for game updates.
- The download links below always point to the **latest release**. A specific version is at `https://github.com/Jaqquca/silica-linux-server/releases/download/v1.0.0/<file>`.

## Requirements

| | |
|---|---|
| OS | 64-bit Linux (x86_64). The script supports Debian 11+ and Ubuntu 20.04+. |
| RAM | 12 GB minimum, **16 GB recommended** (the City of Naraka map uses ~11 GB) |
| Disk | ~20 GB (9.1 GB game, plus room for downloads during updates) |
| CPU | ~1–2 cores idle at 30–60 FPS (see *Max FPS* below), more with players |
| Network | Outbound internet. **No port forwarding needed:** players connect through the Steam relay network. |
| Ports | Game port (default 27015) and query port (default 27016) on the machine itself |

**Tested** (Silica Steam build 26334620, Release 1.0.15, November 2026):

- **v1.0.0, standalone installer:** Ubuntu 24.04 VM with the systemd service (install, start, restart, join ID), and an `ubuntu:24.04` Docker container (no systemd)
- **v1.0.0, egg:** Pterodactyl panel with Wings, image `ghcr.io/parkervcp/steamcmd:debian`
- **v1.1.0, MelonLoader 0.7.3:** a fresh Ubuntu 24.04 VM (standalone, systemd) and Pterodactyl with the Ubuntu image, each with the data-bomb server mod pack (see the [known limitations](#known-limitations)), joined from a normal 1.0.15 game client with nothing installed

## Option A: standalone installer (any Linux machine)

```bash
curl -fsSLO https://github.com/Jaqquca/silica-linux-server/releases/latest/download/install-silica-server.sh
sudo bash install-silica-server.sh
```

This does the following:

1. installs the packages it needs (`curl`, `ca-certificates`, `tar`, `unzip`, 32-bit `libgcc`)
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

**With MelonLoader for server-side mods** (Ubuntu 24.04+ / Debian 13+; also works on an existing install):

```bash
sudo bash install-silica-server.sh --melonloader
```

Run `bash install-silica-server.sh --help` for all options.

## Option B: Pterodactyl / Pelican egg

1. Download [`egg-silica-linux.json`](https://github.com/Jaqquca/silica-linux-server/releases/latest/download/egg-silica-linux.json). In **Admin → Nests** (Pelican: **Eggs**) **→ Import Egg**, upload it and choose a nest.
   Pelican can also import it straight from that URL.
2. Create a server from the egg:
    - **two allocations:** the game port (primary) and the query port, usually game port + 1. Set **Query Port** to the second one.
    - **16 GB RAM, 0 swap, ~20 GB disk**
    - **Docker image:** the default *SteamCMD Ubuntu 24.04* works for everything. *Debian 12* runs the server, but not MelonLoader.
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
| MelonLoader | `MELONLOADER` | `0` | `1` loads MelonLoader for server-side mods (see below) |
| MelonLoader version | `MELONLOADER_VERSION` | `0.7.3` | MelonLoader release that gets installed |
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

## Server-side mods (MelonLoader)

Since v1.1.0, both install methods can load [MelonLoader](https://github.com/LavaGang/MelonLoader) (native Linux build) and with it **server-side mods**, such as the [data-bomb mod collection](https://github.com/data-bomb/Silica). **Players don't need anything:** they join with the normal game.

**Requirement:** glibc 2.38 or newer, which the Linux build of MelonLoader needs. That means Ubuntu 24.04+ or Debian 13+; in the panel, the *SteamCMD Ubuntu 24.04* image (the default). On an older system the server still starts, just without mods, and says so in the log.

**Switch it on:**

- **Standalone:** `sudo bash install-silica-server.sh --melonloader`. It works on an existing install, and your settings are kept. Switch it off again with `--no-melonloader`.
- **Panel:** set the **MelonLoader** variable to `1` and restart. MelonLoader is already installed by the egg's installer. A server created from the v1.0.0 egg needs the [upgrade steps](#upgrading-from-v100) first.

**Add mods:**

- **Folders:** mod DLLs go into `Mods/`, plugins into `Plugins/`, and their settings into `UserData/` in the server folder (`/opt/silica` or the panel's file manager). Then restart.
- **Log:** `MelonLoader/Latest.log`. MelonLoader's output also appears in the console (`journalctl -u silica -f` or the panel console).
- **Example, the data-bomb dedicated-server pack** on a standalone install (it leaves out the Windows-only files):
  ```bash
  curl -fsSLO https://github.com/data-bomb/Silica/releases/download/v1423/DedicatedServer-v1423-29c72fa.zip
  sudo -u silica unzip -oq DedicatedServer-v1423-29c72fa.zip -d /opt/silica -x launch.bat rungame.bat Plugins/Si_DiscordStatus.dll
  sudo systemctl restart silica
  ```
  In the panel, upload the zip in the file manager, unpack it, and delete `launch.bat` and `rungame.bat`. For the Discord Status plugin, see [Known limitations](#known-limitations).

### Known limitations

- **Discord Status plugin:** Windows-only (it loads a Windows library). Leave it out on Linux.
- **Mod Updater plugin:** creates a temp folder with a Windows-style name (`Mods/~temp\`). It's harmless.

### How it works (for manual setups)

MelonLoader's Linux build is a library that's preloaded into the game process:

```bash
LD_LIBRARY_PATH=/path/to/server:/path/to/server/Silica_Data/Plugins LD_PRELOAD=MelonLoader.Bootstrap.so ./Silica.x86_64 -logFile -
```

`Silica_Data/Plugins` has to be in `LD_LIBRARY_PATH`. Without it, the game no longer finds `libsteam_api64.so` once MelonLoader is loaded, and it never connects to Steam (`DllNotFoundException: steam_api64`). Both install methods do this in `silica-launch.sh`.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Not enough disk quota` / state `0x202` from SteamCMD | Not enough free disk (~14 GB needed during install/update) |
| `Steamworks is not initialized` / `Aborting server startup` | Keep `IP="0"` in ServerSettings.xml; the scripts force it. Check that `.steam/sdk64/steamclient.so` exists (re-run the installer / reinstall). |
| Killed, exit code 137 / "out of memory" | Give the server more RAM (16 GB) |
| High CPU with nobody online | Lower `MAX_FPS` (60 or 30) |
| `GLIBC_2.38' not found` (MelonLoader) | The system is too old for MelonLoader: use Ubuntu 24.04+ / Debian 13+, or in the panel the Ubuntu image |
| `DllNotFoundException: steam_api64` with MelonLoader | `Silica_Data/Plugins` is missing from `LD_LIBRARY_PATH` (manual setups; the scripts set it) |
| Players don't see the server | Wait for `Steam relay network and server certificate available` in the log; join by the ID from `joinid.sh` (or `Game server SteamID` in the log) |

## Repository layout

| Path | What it is |
|---|---|
| `egg-silica-linux.json` | The egg (PTDL_v2; imports into Pterodactyl and Pelican). **Generated.** |
| `install-silica-server.sh` | The standalone installer. **Generated.** It writes `silica.env`, `start.sh`, `update.sh`, `joinid.sh`, `silica-config.sh`, `silica-launch.sh` and the default XML templates into the install folder. |
| `src/silica-config.sh` | Applies the settings to the game's XML files before every start; shared by both. |
| `src/silica-launch.sh` | Starts the game, with MelonLoader when `MELONLOADER=1`; shared by both. |
| `src/*.default.xml` | Default ServerSettings / MatchSettings / GameSettings templates. |
| `src/install-silica-server.template.sh` | Source of the standalone installer. |
| `src/build_release.py` | Builds both generated files from `src/`. |

**Changing something:** edit the files in `src/`, then run `python src/build_release.py` and commit the regenerated files. Never edit the two generated files by hand.

## Releasing a new version

1. If the repository is archived, unarchive it (Settings → General → Danger Zone → Unarchive).
2. Make the changes in `src/`. In `src/build_release.py`, set `VERSION` and `RELEASED`:
    - `x.y.Z` for fixes
    - `x.Y.0` for new features
    - `X.0.0` when existing setups would break, for example renamed variables
3. Build and commit:
   ```bash
   python src/build_release.py
   git commit -am "v1.1.0: <what changed>"
   git push
   ```
4. Publish the release with both generated files attached:
   ```bash
   gh release create v1.1.0 egg-silica-linux.json install-silica-server.sh --title "v1.1.0" --notes "<what changed>"
   ```
   The *latest release* links switch to it immediately.
5. Archive the repository again if you want it read-only.

How existing servers update:

- **Standalone:** run the new installer once. It refreshes the scripts and keeps `silica.env` and the XML settings.
- **Panel:** import the new egg (Pterodactyl: *Update Egg*; Pelican: re-import, where the fixed `uuid` makes it an update), then reinstall the server. Game files and settings stay.

### Upgrading from v1.0.0

- **Standalone:** download the new installer and run it once (`sudo bash install-silica-server.sh`, add `--melonloader` for mods). Settings are kept.
- **Panel:**
    1. Import the new egg as an update of the existing one (Pterodactyl: *Update Egg*; Pelican: re-import).
    2. On every existing server, change the startup command to `bash silica-config.sh && exec bash silica-launch.sh` (servers keep their own copy of it) and switch the Docker image to *Ubuntu 24.04* if you want mods.
    3. Reinstall the server. It keeps the game files and settings, and adds `silica-launch.sh` and MelonLoader.

## License

[MIT](LICENSE). Silica is a game by Bohemia Interactive; this project isn't affiliated with Bohemia Interactive or Valve.
