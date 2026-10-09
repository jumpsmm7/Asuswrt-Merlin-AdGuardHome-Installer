#!/bin/sh
# Boot isolated ARM kernels and collect acceptance evidence for selected features.
set -eu

REPOSITORY="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
FEATURES=all
ARCHITECTURES=armv5,armv7,armv8
OUTPUT="${REPOSITORY}/../work/virtual-arm-results"
CACHE_DIR="${AGH_VIRTUAL_ARM_CACHE:-${REPOSITORY}/../work/virtual-arm-cache}"
DEFER_ACCEPTANCE=0

# usage prints the explicit feature scope and diagnostic-only subset option;
# callers choose whether the output goes to stdout or stderr.
usage() {
	printf '%s\n' 'Usage: tools/test-virtual-arm.sh [--features ID,ID] [--architectures armv5,armv7,armv8] [--output DIR] [--cache DIR] [--defer-acceptance]' \
		'armv5 selects the older RT-AC68U-class ARMv7 Cortex-A9 software-float guest; it is not an ARMv5 CPU guest.' \
		'All three architectures are required to unblock the selected features.' \
		'--defer-acceptance collects diagnostic evidence for later matrix aggregation.'
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--features | --architectures | --output | --cache)
			[ "$#" -ge 2 ] || {
				usage >&2
				exit 2
			}
			case "$1" in
				--features) FEATURES="$2" ;;
				--architectures) ARCHITECTURES="$2" ;;
				--output) OUTPUT="$2" ;;
				--cache) CACHE_DIR="$2" ;;
				*)
					usage >&2
					exit 2
					;;
			esac
			shift 2
			;;
		--defer-acceptance)
			DEFER_ACCEPTANCE=1
			shift
			;;
		--help | -h)
			usage
			exit 0
			;;
		*)
			printf '%s\n' "Unknown option: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

exec python3 "${REPOSITORY}/tools/virtual-arm/run-matrix.py" \
	--repository "${REPOSITORY}" --features "${FEATURES}" --architectures "${ARCHITECTURES}" \
	--output "${OUTPUT}" --cache "${CACHE_DIR}" --defer-acceptance "${DEFER_ACCEPTANCE}"
