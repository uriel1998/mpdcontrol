# mpdcontrol

Sometimes I want to listen to an album, or two or three, or a genre *and* an artist, or a stream and then let `mpdq` take over, or, or... and I just want to have one simple interface that can be as flexible as my music taste might be.

Hence, this program.

VIDEO TO GO HERE

`mpdcontrol.sh` (or `mpdc`) builds an `fzf` picker from several music and radio sources, then sends the selected result to MPD or `mpdq`.

It can combine:

- MPD playlists
- `mpdq` station configs
- `.pls` radio entries from `simple_listen_to_di` (or any other similarly formatted)
- `radiotray-ng` bookmarks
- MPD genres
- MPD artists
- MPD albums

There's icons in the picker to indicate what sort of thing you're selecting, and then it'll queue up the appropriate things.  Or you can have it instantly change clear whatever's playing.  Or have it change after the currently-playing track (unless that's a stream, since streams often don't end).  

Also, if you have anything in the "Bumper" genre, like "radio changing static" sounds, it'll play that to signify the new change.  It amuses me.

## Dependencies

System packages installable with `apt` (I'm using Debian trixie):

```bash
sudo apt update
sudo apt install -y bash mpd mpc fzf jq grep sed coreutils mawk
```

Notes:

- `mpd` is what we're playing music through, though if you have it installed as a server elsewhere, this is unneeded.
- `mpc` is the MPD client the script uses for querying and queue actions.
- `fzf` provides the interactive selector.
- `jq` is used for `radiotray-ng` bookmark parsing.
- `grep`, `sed`, `coreutils`, and `mawk` cover the shell text-processing used by the script.

External tools referenced by this project:

- `mpdq`: <https://github.com/uriel1998/mpdq>
- `simple_listen_to_di`: <https://github.com/uriel1998/simple_listen_to_di>

`mpdq` is required for `--stations`.

`simple_listen_to_di` is optional, but has a script in it needed if you want the playlists for `--listentodi`.

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
- `2`: crop before adding, with a randomly selected track from the genre "Bumper" played first.

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

The script dispatches by `source`:

- `playlist` -> `mpc load`
- `genre` -> `mpc findadd genre`
- `artist` -> `mpc findadd albumartist`
- `album` -> `mpc findadd album`
- `radio` -> `mpc add <url>`
- `station` -> `mpdq --config <path>`

If you choose more than one thing, then:

- `clearmode` runs once before selection processing starts
- non-`station` selections are processed first
- `station` selections are deferred until the end
- if more than one `station` is selected, one station is chosen at random and passed to `mpdq`
