#!/bin/sh
# Run BusyBox ash regression scripts with command hashing disabled so PATH-based
# command stubs are re-resolved after tests prepend their private stub directory.

if [ "${1:-}" != ash ]; then
	exec /usr/bin/busybox "$@"
fi

shift
if [ "$#" -eq 0 ]; then
	exec /usr/bin/busybox ash
fi

script="$1"
shift
exec /usr/bin/busybox ash -c 'set +h; . "$0"' "${script}" "$@"
