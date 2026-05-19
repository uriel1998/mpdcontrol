# mpdcontrol

`mpdcontrol.sh` builds an `fzf` picker from several music and radio sources, then sends the selected result to MPD or `mpdq`.

It can combine:

- MPD playlists
- `mpdq` station configs
- `.pls` radio entries from `simple_listen_to_di`
- `radiotray-ng` bookmarks
- MPD genres
- MPD artists
- MPD albums

The chooser shows `icon - title`, but the script keeps the full source record internally so it can dispatch the correct action for each selection.

## Dependencies

System packages installable with `apt`:

```bash
sudo apt update
sudo apt install -y bash mpd mpc fzf jq grep sed coreutils mawk
```

Notes:

- `mpc` is the MPD client the script uses for querying and queue actions.
- `fzf` provides the interactive selector.
- `jq` is used for `radiotray-ng` bookmark parsing.
- `grep`, `sed`, `coreutils`, and `mawk` cover the shell text-processing used by the script.

External tools referenced by this project:

- `mpdq`: <https://github.com/uriel1998/mpdq>
- `simple_listen_to_di`: <https://github.com/uriel1998/simple_listen_to_di>

`mpdq` is required for `--stations`.

`simple_listen_to_di` is optional, but needed if you want `--listentodi`.

## Installation

Clone this repository and make the script executable:

```bash
chmod +x mpdcontrol.sh
```

If you want station support, install `mpdq` from:

- <https://github.com/uriel1998/mpdq>

If you want `.pls` radio support, install or clone:

- <https://github.com/uriel1998/simple_listen_to_di>

## Configuration

The script looks for configuration in this order:

1. Existing environment variables
2. `./mpdc.ini`
3. `$XDG_CONFIG_HOME/mpdc`
4. `$HOME/.config/mpdc`
5. Built-in defaults

An example config is provided in [mpdc.ini.example](/home/steven/Documents/programming/#music/mpdcontrol/mpdc.ini.example).

Common keys:

```ini
musicdir=/media/_Music
mpdserver=localhost
mpdport=6600
mpdpass=secret
DI_PLS_DIR=/path/to/pls/files
ADDMODE=2
```

`ADDMODE` values:

- `0`: add without clearing
- `1`: clear before adding
- `2`: crop before adding, with bumper logic

## Usage

Show help:

```bash
./mpdcontrol.sh --help
```

Choose from everything:

```bash
./mpdcontrol.sh --all
```

Choose genres and albums, clearing the queue first:

```bash
./mpdcontrol.sh --genre --album --clear
```

Choose from `mpdq` stations:

```bash
./mpdcontrol.sh --stations
```

Choose from mixed sources with multiselect:

```bash
./mpdcontrol.sh --all
```

If multiple `station` entries are selected in the same run, the script keeps only one of them and chooses it at random.

Choose from ListenToDI `.pls` files in a custom directory:

```bash
./mpdcontrol.sh --listentodi --playlist-dir /path/to/pls
```

Enable verbose logging:

```bash
./mpdcontrol.sh --all --loud
```

## Supported Options

```text
--playlist, --playlists
--stations
--listentodi
--radiotray
--genre
--artist
--album
--all
--clear
--crop
--playlist-dir PATH
--loud
-h, --help
```

## Behavior

Each selectable row is stored internally as:

```text
icon,source,title,payload
```

The script dispatches by `source`:

- `playlist` -> `mpc load`
- `genre` -> `mpc findadd genre`
- `artist` -> `mpc findadd albumartist`
- `album` -> `mpc findadd album`
- `radio` -> `mpc add <url>`
- `station` -> `mpdq --config <path>`

Multi-select behavior:

- `clearmode` runs once before selection processing starts
- non-`station` selections are processed first
- `station` selections are deferred until the end
- if more than one `station` is selected, one station is chosen at random and passed to `mpdq`
