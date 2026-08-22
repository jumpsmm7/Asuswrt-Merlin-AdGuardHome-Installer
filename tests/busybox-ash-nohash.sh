#!/bin/sh
# Run one regression script under BusyBox ash with command hashing disabled so
# PATH-prepended command stubs replace commands resolved earlier in the script.

[ "$#" -gt 0 ] || exit 2
script="$1"
shift
exec /usr/bin/busybox ash -c 'set +h; . "$0"' "${script}" "$@"
