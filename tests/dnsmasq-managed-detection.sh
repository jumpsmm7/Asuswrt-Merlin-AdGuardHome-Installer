#!/bin/sh
# Real identity and socket mapper with isolated proc/config paths; no signals.
set -eu
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT HUP INT TERM
mkdir -p "${ROOT}/proc" "${ROOT}/etc"
sed -n '/^dnsmasq_process_config() {$/,/^}$/p; /^dnsmasq_process_start_time() {$/,/^}$/p; /^dnsmasq_managed_instances() {$/,/^}$/p; /^dns_port_owner_actions() {$/,/^}$/p' S99AdGuardHome |
	sed 's|"/proc/${pid}/|"${ROOT}/proc/${pid}/|g; s|\[ -f "${config}" \] \&\& \[ ! -L "${config}" \]|[ -f "${ROOT}${config}" ] \&\& [ ! -L "${ROOT}${config}" ]|' >"${ROOT}/functions"
. "${ROOT}/functions"
PROCS=AdGuardHome
# nvram prints CAPABILITY, defaulting to SDN support, for firmware detection.
nvram() { printf '%s\n' "${CAPABILITY:-mtlancfg}"; }
# pidof lists the synthetic PIDs, including a missing process, for identity checks.
pidof() { printf '%s\n' '11 12 13 14 15 16 17 18'; }
# kill fails the test if read-only process detection attempts to send a signal.
kill() {
	printf '%s\n' 'FAIL: detection sent a signal' >&2
	exit 1
}
# fixture creates synthetic procfs identity for PID $1 with the remaining arguments as its command line.
fixture() {
	pid="$1"
	shift
	mkdir -p "${ROOT}/proc/${pid}"
	ln -s /usr/sbin/dnsmasq "${ROOT}/proc/${pid}/exe"
	printf '%s\n' dnsmasq >"${ROOT}/proc/${pid}/comm"
	printf '%s\0' dnsmasq "$@" >"${ROOT}/proc/${pid}/cmdline"
	printf '%s\n' "${pid} (dnsmasq) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1234" >"${ROOT}/proc/${pid}/stat"
}
: >"${ROOT}/etc/dnsmasq.conf"
: >"${ROOT}/etc/dnsmasq-1.conf"
: >"${ROOT}/etc/dnsmasq-2.conf"
fixture 11 --log-async
fixture 12 -C /etc/dnsmasq-1.conf --log-async
fixture 13 --conf-file=/etc/dnsmasq-2.conf
fixture 14 -C /opt/etc/unrelated.conf
fixture 15 -C /etc/dnsmasq-1.conf --conf-dir=/opt/custom
fixture 16 -C
fixture 17 --log-async
rm "${ROOT}/proc/17/exe"
ln -s /opt/sbin/dnsmasq "${ROOT}/proc/17/exe"
[ "$(dnsmasq_managed_instances | wc -l)" -eq 3 ]
[ "$(dnsmasq_process_config 12)" = /etc/dnsmasq-1.conf ]
CAPABILITY=other
if dnsmasq_process_config 12; then exit 1; fi
CAPABILITY=mtlancfg
table="$(printf '%s\n' \
	'tcp 0 0 0.0.0.0:53 0.0.0.0:* LISTEN 11/dnsmasq' \
	'udp 0 0 0.0.0.0:53 0.0.0.0:* 11/dnsmasq' \
	'udp6 0 0 :::53 :::* 12/dnsmasq-sdn' \
	'udp 0 0 192.168.2.1:53 0.0.0.0:* 13/truncated' \
	'udp 0 0 192.168.3.1:53 0.0.0.0:* 14/dnsmasq' \
	'udp 0 0 192.168.4.1:53 0.0.0.0:* 18/dnsmasq' \
	'udp 0 0 192.168.5.1:53 0.0.0.0:* -')"
actions="$(dns_port_owner_actions global "${table}")"
[ "$(printf '%s\n' "${actions}" | wc -l)" -eq 6 ]
printf '%s\n' "${actions}" | grep -q '^12 dnsmasq dnsmasq-sdn 1234 /etc/dnsmasq-1.conf$'
printf '%s\n' "${actions}" | grep -q '^14 unknown dnsmasq - -$'
printf '%s\n' "${actions}" | grep -q '^18 unknown dnsmasq - -$'
printf '%s\n' "${actions}" | grep -q '^- unknown unknown - -$'
[ "$(dns_port_owner_actions 127.0.0.1 "${table}" | wc -l)" -eq 2 ]
rm "${ROOT}/etc/dnsmasq-1.conf"
ln -s dnsmasq.conf "${ROOT}/etc/dnsmasq-1.conf"
if dnsmasq_process_config 12; then exit 1; fi
printf '%s\n' 'PASS: managed main/SDN identity, unknown owners, and scoped deduplication'
