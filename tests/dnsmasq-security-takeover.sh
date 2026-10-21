#!/bin/sh
# Verify safe include expansion and exact DNSSEC filtering without router state.
set -eu
export LC_ALL=C

SCRIPT_PATH="${1:-AdGuardHome.sh}"
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dnsmasq-security-takeover.XXXXXX")"
trap 'rm -rf "${ROOT}"' 0
trap 'exit 1' HUP INT TERM

# fail reports a failed contract and terminates this isolated fixture.
fail() {
	printf '%s\n' "FAIL: $*" >&2
	exit 1
}

sed -n '/^dnsmasq_takeover_filter() ($/,/^)/p' "${SCRIPT_PATH}" >"${ROOT}/functions"
[ -s "${ROOT}/functions" ] || fail 'takeover helper was not found'
# shellcheck disable=SC1090
. "${ROOT}/functions"

DNSMASQ_REAL="$(which dnsmasq 2>/dev/null || true)"
DNSMASQ_TEST_VERSION='2.91'
VERSION_CALLS="${ROOT}/version-calls"
: >"${VERSION_CALLS}"
# dnsmasq provides deterministic version cases while retaining real syntax tests.
dnsmasq() {
	if [ "${1:-}" = --version ]; then
		printf '%s\n' version >>"${VERSION_CALLS}"
		printf 'Dnsmasq version %s  Copyright (c) Simon Kelley\n' "${DNSMASQ_TEST_VERSION}"
		return 0
	fi
	[ -n "${DNSMASQ_REAL}" ] || return 1
	"${DNSMASQ_REAL}" "$@"
}

mkdir "${ROOT}/sources" "${ROOT}/expected"
MAIN="${ROOT}/dnsmasq.conf"
STAGE="${MAIN}.adguard"
MIXED="${ROOT}/sources/mixed settings.conf"
NESTED="${ROOT}/sources/nested.conf"
KEYS="${ROOT}/sources/keys.conf"
SERVERS="${ROOT}/sources/servers.conf"
printf '%s\n' 'server=/upstream.example/192.0.2.53' >"${SERVERS}"
printf '%s\n' 'trust-anchor=.,20326,8,2,root' 'trust-anchor=.,38696,8,2,rollover' \
	'trust-anchor=private.example,12345,8,2,custom' >"${KEYS}"
printf '%s\n' 'trust-anchor=deep.example,54321,8,2,nested' \
	'dns-rr="key,example",48,0102' 'dns-rr="ordinary,example",16,0102' \
	'address=/nested.example/192.0.2.3' >"${NESTED}"
printf '%s\n' 'dhcp-range=192.0.2.100,192.0.2.150,12h' 'dnssec' \
	"conf-file=${NESTED}" "servers-file=${SERVERS}" >"${MIXED}"
ln "${MIXED}" "${ROOT}/sources/hardlink.conf"
printf '%s\n' '# parent before includes' "conf-file = \"${MIXED}\" # mixed include" \
	"conf-file=${KEYS}" "conf-file=${ROOT}/sources/hardlink.conf" \
	'address=/parent.example/192.0.2.1' >"${MAIN}"
cp -p "${ROOT}/sources/"* "${ROOT}/expected/"
cp -p "${MAIN}" "${STAGE}"
chmod 640 "${STAGE}"
dnsmasq_takeover_filter "${STAGE}" "${MAIN}" || fail 'mixed/nested includes failed'
cat >"${ROOT}/expected-runtime" <<EOF
# parent before includes
dhcp-range=192.0.2.100,192.0.2.150,12h
dns-rr="ordinary,example",16,0102
address=/nested.example/192.0.2.3
servers-file=${SERVERS}
address=/parent.example/192.0.2.1
EOF
cmp -s "${STAGE}" "${ROOT}/expected-runtime" || fail 'mixed/nested ordering, unrelated settings or inode dedup changed'
[ "$(ls -ln "${STAGE}" | awk '{ print $1 }')" = '-rw-r-----' ] || fail 'filter changed staged configuration permissions'
[ ! -s "${VERSION_CALLS}" ] || fail 'conf-file expansion unnecessarily queried dnsmasq version'
for source_file in "${ROOT}/sources/"*; do
	cmp -s "${source_file}" "${ROOT}/expected/${source_file##*/}" || fail 'persistent include source changed'
done
cp -p "${STAGE}" "${ROOT}/once"
dnsmasq_takeover_filter "${STAGE}" "${MAIN}" || fail 'repeated takeover failed'
cmp -s "${STAGE}" "${ROOT}/once" || fail 'repeated takeover changed runtime view'

# A cycle back to the root config has the same inode semantics as dnsmasq.
printf '%s\n' 'address=/before.example/192.0.2.1' "conf-file=${MAIN}" \
	'address=/after.example/192.0.2.2' >"${MAIN}"
cp -p "${MAIN}" "${STAGE}"
dnsmasq_takeover_filter "${STAGE}" "${MAIN}" || fail 'self-include cycle did not terminate'
printf '%s\n' 'address=/before.example/192.0.2.1' 'address=/after.example/192.0.2.2' >"${ROOT}/cycle-expected"
cmp -s "${STAGE}" "${ROOT}/cycle-expected" || fail 'self-include duplicated root options'

# Directory suffix filters, defaults and include ordering follow dnsmasq 2.81+.
DIRECTORY="${ROOT}/sources/directory"
mkdir "${DIRECTORY}" "${DIRECTORY}/subdirectory"
printf '%s\n' 'address=/z.example/192.0.2.3' 'dnssec' >"${DIRECTORY}/z.conf"
printf '%s\n' 'address=/a.example/192.0.2.1' 'trust-anchor=.,1,8,2,key' >"${DIRECTORY}/a.conf"
printf '%s\n' 'address=/b.example/192.0.2.2' "conf-file=${NESTED}" >"${DIRECTORY}/b.conf"
for excluded in '.hidden.conf' 'backup.conf~' '#lock.conf#' 'skip.conf.disabled' 'skip.secret.conf' '.conf' 'plain'; do
	printf '%s\n' 'invalid-option=must-not-load' >"${DIRECTORY}/${excluded}"
done
printf '%s\n' "conf-dir = ${DIRECTORY} , *.conf , disabled , secret.conf " >"${MAIN}"
cp -p "${MAIN}" "${STAGE}"
dnsmasq_takeover_filter "${STAGE}" "${MAIN}" || fail 'conf-dir expansion failed'
printf '%s\n' 'address=/a.example/192.0.2.1' 'address=/b.example/192.0.2.2' \
	'dns-rr="ordinary,example",16,0102' 'address=/nested.example/192.0.2.3' \
	'address=/z.example/192.0.2.3' >"${ROOT}/directory-expected"
cmp -s "${STAGE}" "${ROOT}/directory-expected" || fail 'conf-dir order, suffix filtering or nested expansion changed'
[ "$(wc -l <"${VERSION_CALLS}")" -eq 1 ] || fail 'directory traversal repeated the version probe'

# Native 2.80 iteration must not be silently sorted by a newer implementation.
DNSMASQ_TEST_VERSION='2.80'
printf '%s\n' "conf-dir=${DIRECTORY},*.conf,disabled,secret.conf" >"${MAIN}"
cp -p "${MAIN}" "${STAGE}"
dnsmasq_takeover_filter "${STAGE}" "${MAIN}" || fail 'legacy directory ordering was rejected'
find "${DIRECTORY}" -mindepth 1 -maxdepth 1 >"${ROOT}/native-list"
: >"${ROOT}/legacy-expected"
while IFS= read -r source_file; do
	case "${source_file##*/}" in
		a.conf) printf '%s\n' 'address=/a.example/192.0.2.1' ;;
		b.conf) printf '%s\n' 'address=/b.example/192.0.2.2' 'dns-rr="ordinary,example",16,0102' 'address=/nested.example/192.0.2.3' ;;
		z.conf) printf '%s\n' 'address=/z.example/192.0.2.3' ;;
	esac >>"${ROOT}/legacy-expected"
done <"${ROOT}/native-list"
cmp -s "${STAGE}" "${ROOT}/legacy-expected" || fail 'legacy readdir order changed'
DNSMASQ_TEST_VERSION='2.91'

# Exact active spellings include legal partial quotes; hash in data is retained.
printf '%s\n' 'dns"s"ec' '"stop"-dns-rebind' 'dnssec-check-unsigned = no # comment' \
	'dnssec#ordinary=preserved' 'address=/hash.example/192.0.2.1#literal' \
	'dns-rr=normal.example,16,beef' 'dns-rr=key.example,"0048",beef' \
	'dns-rr=anchor.example,32768,0102' >"${STAGE}"
dnsmasq_takeover_filter "${STAGE}" "${STAGE}" || fail 'quoted directive filtering failed'
printf '%s\n' 'dnssec#ordinary=preserved' 'address=/hash.example/192.0.2.1#literal' \
	'dns-rr=normal.example,16,beef' >"${ROOT}/quoted-expected"
cmp -s "${STAGE}" "${ROOT}/quoted-expected" || fail 'quoted option/key filtering or comment boundaries changed'

# dnsmasq treats CR, vertical tab and form feed as unquoted whitespace too.
printf 'stop-dns-rebind\r\ndnssec\r\n\013dnssec-check-unsigned\014=\013no\r\ntrust-anchor\014=.,1,8,2,key\r\naddress=/kept.example/192.0.2.1\r\n' >"${STAGE}"
dnsmasq_takeover_filter "${STAGE}" "${STAGE}" || fail 'firmware whitespace filtering failed'
printf 'address=/kept.example/192.0.2.1\r\n' >"${ROOT}/whitespace-expected"
cmp -s "${STAGE}" "${ROOT}/whitespace-expected" || fail 'CRLF or other dnsmasq whitespace retained active security options'

# Each unsafe source must fail before replacing even the supplied stage.
ln -s "${KEYS}" "${ROOT}/sources/symlink.conf"
printf '%s\n' 'conf-file=relative.conf' >"${ROOT}/unsafe-relative"
printf '%s\n' 'conf-file=-' >"${ROOT}/unsafe-stdin"
printf '%s\n' "conf-file=${ROOT}/sources/missing.conf" >"${ROOT}/unsafe-missing"
printf '%s\n' "conf-file=${ROOT}/sources/symlink.conf" >"${ROOT}/unsafe-symlink"
printf '%s\n' "conf-file=${DIRECTORY}" >"${ROOT}/unsafe-directory-as-file"
printf '%s\n' 'conf-script=/tmp/unsafe-command' >"${ROOT}/unsafe-dynamic"
printf 'stop-dns-rebind\000\n' >"${ROOT}/unsafe-nul"
printf '#comment\000address=/nul.example/192.0.2.1\n' >"${ROOT}/unsafe-nul-comment"
printf 'trust-anchor=.,1,8,2,key\000\n' >"${ROOT}/sources/nul.conf"
printf '%s\n' "conf-file=${ROOT}/sources/nul.conf" >"${ROOT}/unsafe-nested-nul"
printf '%s\n' "conf-file=\"${ROOT}/sources/quoted,comma.conf\"" >"${ROOT}/unsafe-comma"
printf '%s\n' 'address=/literal-backslash.example/192.0.2.1' >"${ROOT}/sources/with\q.conf"
printf '%s\n' 'address=/lossy-path.example/192.0.2.2' >"${ROOT}/sources/withq.conf"
printf '%s\n' "conf-file=\"${ROOT}/sources/with\\q.conf\"" >"${ROOT}/unsafe-escape"
printf '%s\n' "conf-dir=${DIRECTORY},*.conf" >"${ROOT}/unsafe-version"
CONTROL_PATH="${ROOT}/sources/control$(printf '\013').conf"
printf '%s\n' 'address=/control.example/192.0.2.1' >"${CONTROL_PATH}"
printf '%s\n' "conf-file=\"${CONTROL_PATH}\"" >"${ROOT}/unsafe-control"
for unsafe_source in "${ROOT}"/unsafe-*; do
	cp -p "${unsafe_source}" "${STAGE}"
	case "${unsafe_source}" in *unsafe-version) DNSMASQ_TEST_VERSION='unknown' ;; esac
	if dnsmasq_takeover_filter "${STAGE}" "${MAIN}"; then fail "unsafe include succeeded: ${unsafe_source##*/}"; fi
	DNSMASQ_TEST_VERSION='2.91'
	cmp -s "${STAGE}" "${unsafe_source}" || fail 'failed filtering partially changed staged configuration'
	[ -z "$(find "${ROOT}" -name '*.takeover.*' -print)" ] || fail 'failed filtering leaked temporary artifacts'
done

# Control characters in directory entry names are rejected before list parsing.
CONTROL_DIRECTORY="${ROOT}/control-directory"
mkdir "${CONTROL_DIRECTORY}"
printf '%s\n' 'address=/ordinary.example/192.0.2.1' >"${CONTROL_DIRECTORY}/ordinary.conf"
printf '%s\n' 'dnssec' >"${CONTROL_DIRECTORY}/control$(printf '\013').conf"
printf '%s\n' "conf-dir=${CONTROL_DIRECTORY}" >"${STAGE}"
cp -p "${STAGE}" "${ROOT}/control-original"
if dnsmasq_takeover_filter "${STAGE}" "${MAIN}"; then fail 'control-character directory entry was accepted'; fi
cmp -s "${STAGE}" "${ROOT}/control-original" || fail 'unsafe directory entry changed staged configuration'

# An actual read failure after an earlier valid include cannot publish output.
printf '%s\n' "conf-file=${MIXED}" "conf-file=${KEYS}" >"${STAGE}"
cp -p "${STAGE}" "${ROOT}/read-failure-original"
(
	# awk injects a failed include read while retaining all other AWK behavior.
	awk() {
		for argument; do [ "${argument}" != "${KEYS}" ] || return 1; done
		command awk "$@"
	}
	if dnsmasq_takeover_filter "${STAGE}" "${MAIN}"; then fail 'unreadable nested source was accepted'; fi
)
cmp -s "${STAGE}" "${ROOT}/read-failure-original" || fail 'read failure published a partially expanded stage'

# Final filter-stage publication failure also leaves the original stage intact.
(
	# mv refuses the filtered-stage rename without affecting source preparation.
	mv() {
		[ "${2:-}" != "${STAGE}" ] || return 1
		command mv "$@"
	}
	if dnsmasq_takeover_filter "${STAGE}" "${MAIN}"; then fail 'failed filter-stage rename succeeded'; fi
)
cmp -s "${STAGE}" "${ROOT}/read-failure-original" || fail 'filter-stage rename failure changed the stage'

# Deep distinct includes are bounded even though ordinary inode cycles terminate.
deep_index=0
while [ "${deep_index}" -lt 34 ]; do
	next_index="$((deep_index + 1))"
	printf '%s\n' "conf-file=${ROOT}/deep-${next_index}" >"${ROOT}/deep-${deep_index}"
	deep_index="${next_index}"
done
printf '%s\n' 'address=/deep.example/192.0.2.1' >"${ROOT}/deep-34"
cp -p "${ROOT}/deep-0" "${STAGE}"
if dnsmasq_takeover_filter "${STAGE}" "${MAIN}"; then fail 'unbounded include depth was accepted'; fi
cmp -s "${STAGE}" "${ROOT}/deep-0" || fail 'include depth failure changed the stage'

# Real dnsmasq parses the resulting self-contained view when available on host.
if [ -n "${DNSMASQ_REAL}" ]; then
	printf '%s\n' "conf-file=${MIXED}" 'port=0' >"${MAIN}"
	cp -p "${MAIN}" "${STAGE}"
	dnsmasq_takeover_filter "${STAGE}" "${MAIN}" || fail 'real syntax fixture filtering failed'
	dnsmasq --test --conf-file="${STAGE}" >"${ROOT}/syntax.log" 2>&1 || {
		cat "${ROOT}/syntax.log" >&2
		fail 'real dnsmasq rejected the filtered runtime view'
	}
else
	printf '%s\n' 'dnsmasq binary unavailable: real syntax check skipped.'
fi

printf '%s\n' 'dnsmasq security takeover tests passed.'
