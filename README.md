# mpdcontrol

Sometimes I want to listen to an album, or two or three, or a genre *and* an album artist, or a stream and then let `mpdq` take over, or, or... and I just want to have one simple interface that can be as flexible as my music taste might be.

Hence, this program.

![mpdc in action](https://raw.githubusercontent.com/uriel1998/mpdcontrol/master/mpdc.gif "mpdc in action")

(The very pretty interface on the left is [rmpc, the Rusty Music Player Client.](https://rmpc.mierak.dev/))

`mpdcontrol.sh` (or `mpdc`) builds an `fzf` picker from several music and radio sources, then sends the selected result to MPD or `mpdq`.

It can combine:

- MPD playlists
- `mpdq` station configs
- `.pls` radio entries from `simple_listen_to_di` (or any other similarly formatted)
- `radiotray-ng` bookmarks
- MPD genres
- MPD album artists
- MPD albums

There's icons in the picker to indicate what sort of thing you're selecting, and then it'll queue up the appropriate things.  Or you can have it instantly change clear whatever's playing.  Or have it change after the currently-playing track (unless that's a stream, since streams often don't end).  

Also, if you have anything in the "Bumper" genre, like "radio changing static" sounds, it'll play that to signify the new change.  It amuses me.

## Use Cases

- Listen to an album normally, and then have `mpdq` autopopulate the queue afterward
- Can't remember an album or album artist's full name? Easily find and play it.
- With the JSON direct input, you can script it so that you have a playlist or semi-random "station" come on at a certain time of day.  You can have a bot, webhook, or home assistant likewise do the same.
- Use the `--emit` option to get options to pass to a web interface, bot, or home assistant

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

Emit the list of choices that would be shown in `fzf`, without opening `fzf` or changing playback:

```bash
./mpdcontrol.sh --emit --stations
```

Emit the raw internal records, using the unit separator character (`0x1f`) between fields:

```bash
./mpdcontrol.sh --emit-raw --stations
```

Emit JSON lines for external tooling:

```bash
./mpdcontrol.sh --emit-json --stations
```

Skip source collection and `fzf` entirely by providing one JSON input record:

```bash
./mpdcontrol.sh --input '{"source":"station","payload":"/home/steven/.config/mpdq/General_mix.cfg"}'
```

The script also accepts the shell-expanded unquoted form:

```bash
./mpdcontrol.sh --input {"source":"station","payload":"/home/steven/.config/mpdq/General_mix.cfg"}
```

Choose from everything:

```bash
./mpdcontrol.sh --all
```

Choose genres and albums, clearing the queue first:

```bash
./mpdcontrol.sh --genre --album --clear
```

Choose items and append them without clearing or cropping first:

```bash
./mpdcontrol.sh --genre --artist --append
```

Choose from `mpdq` stations:

```bash
./mpdcontrol.sh --stations
```

`--station` and `--stations` are equivalent.

If multiple `station` entries are selected in the same run, the script keeps only one of them and chooses it at random.

Choose from ListenToDI `.pls` files in a custom directory:

```bash
./mpdcontrol.sh --listentodi --playlist-dir /path/to/pls
```

Enable verbose logging:

```bash
./mpdcontrol.sh --all --loud
```

`--input` accepts only one JSON object per run. To directly process multiple items, call `mpdcontrol.sh` once per item.

## Supported Options

```text
--playlist, --playlists
--station, --stations
--listentodi
--radiotray
--genre
--artist
--album
--all
--append
--clear
--crop
--emit
--input JSON
--emit-raw
--emit-json
--playlist-dir PATH
--loud
-e, --emit
-i, --input
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

Internal record format:

- `icon`
- `source`
- `title`
- `payload`

`--emit-raw` returns those fields separated by the ASCII unit separator character (`0x1f`).

`--emit-json` returns one JSON object per line, for example:

```json
{"icon":"🎛️","source":"station","title":"Pop","payload":"/home/steven/apps/mpdq/config/Pop.cfg"}
```

`--input` accepts JSON with:

- `source`
- `payload`

Accepted `--input` forms:

- quoted JSON:
  `--input '{"source":"station","payload":"/path/to/file.cfg"}'`
- shell-expanded key/value form:
  `--input {"source":"station","payload":"/path/to/file.cfg"}`

`--input` skips source collection and `fzf`, then immediately processes the provided item as if it had been selected by the user.

If you choose more than one thing, then:

- `clearmode` runs once before selection processing starts
- non-`station` selections are processed first
- `station` selections are deferred until the end
- if more than one `station` is selected, one station is chosen at random and passed to `mpdq`
