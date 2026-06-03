#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
export SCRIPT_DIR
LOUD=1

# Setting them here, will create if needed later
# Chooses ./config FIRST by default
if [ -w "${SCRIPT_DIR}" ]; then
	ConfigDir="${SCRIPT_DIR}"
elif [ -n "${XDG_CONFIG_HOME}" ]; then
	ConfigDir="${XDG_CONFIG_HOME}/mpdc"
else
	ConfigDir="$HOME/.config/mpdc"
fi

# check for existence is in read_variables
if [ -f "$ConfigDir/mpdc.ini" ];then
	ConfigFile="$ConfigDir/mpdc.ini"
fi

grep_bin=$(which grep)
mpc_bin=$(which mpc)

###############################################################functions
function loud() {
	# loud outputs on stderr
	if [[ "${LOUD}" -eq 1 ]];then
		printf '%s\n' "$*" 1>&2
	fi
}

function info() {
	loud "[info] $*"
}

function warn() {
	loud "[warn] $*"
}

function error() {
	loud "[error] $*"
}

function set_host_arg() {
    # in case the password is already set in environment
    if [ -n "$MPD_PASS" ] && [[ "$MPD_HOST" != *"@"* ]]; then
        host_arg="$MPD_PASS@$MPD_HOST"
    else
        host_arg="$MPD_HOST"
    fi
}

function read_variables() {
	config=""
    if [ -f "$ConfigFile" ];then
        config=$(cat "$ConfigFile")
    else
        warn "Configuration file not found; using defaults."
    fi
    
    # If there's no config file or a line is malformed or missing, sub in the default value
    MPDBASE="$(echo "$config" | ${grep_bin} -e "^musicdir=" | cut -d = -f 2- ||
        ${grep_bin} "^music" "$XDG_CONFIG_HOME/mpd/mpd.conf" | cut -d'"' -f2 ||
        echo "$HOME/Music")"
    if [ -z "$MPD_HOST" ]; then
        MPD_HOST="$(echo "$config" | ${grep_bin} -e "^mpdserver=" | cut -d = -f 2-)"
    fi
    if [ -z "$MPD_HOST" ]; then
        MPD_HOST="localhost"
    fi
    if [ -z "$MPD_PASS" ]; then
        MPD_PASS=$(echo "$config" | ${grep_bin} -e "^mpdpass=" | cut -d = -f 2-)
    fi
    if [ -z "$MPD_PORT" ]; then
        MPD_PORT=$(echo "$config" | ${grep_bin} -e "^mpdport=" | cut -d = -f 2-)
    fi
    if [ -z "$MPD_PORT" ]; then
        MPD_PORT="6600"
    fi
	set_host_arg
	info "Using MPD host ${MPD_HOST}:${MPD_PORT}"
	if [ -n "$MPD_PASS" ]; then
		info "MPD password is set"
	fi
	}
	
queue_has_sound_clip_genre() {
    local genre

    while IFS= read -r genre; do
        # Normalize common multi-genre separators to newlines, then test exact genre names.
        if printf '%s\n' "${genre}" \
            | tr ';,|' '\n\n\n' \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
            | grep -Fxiq -e 'Sound Clip' -e 'Sound Clips'
        then
            return 0
        fi
    done < <(mpc --host "${MPD_HOST}" --port "${MPD_PORT}" --format '%genre%' playlist)

    return 1
}	
	
function mpc_action() {
	if [ "$LOUD" -eq 1 ]; then
		${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" "$@"
	else
		${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" -q "$@"
	fi
}


read_variables


if queue_has_sound_clip_genre; then
    info "We've already got one, you see!" # Skip adding another sound clip
    :
else
    # Add one
	SongStem=$(${mpc_bin} --host "${host_arg}" --port "${MPD_PORT}" find genre "Sound Clip" | shuf -n1)
	if [ "$SongStem" != "" ];then
		SongFile="$MPDBASE/$SongStem"
		mpc_action insert "${SongStem}"
	fi
    :
fi

 
