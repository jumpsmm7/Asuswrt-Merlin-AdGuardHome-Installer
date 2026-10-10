#!/bin/sh
# Exercise native binaries and product lifecycle helpers inside isolated ARM VMs.

export LC_ALL=C
export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/opt/sbin:/opt/bin
MODEL_ROOT=/tmp/virtual-arm-native
REPO_ROOT=/repo
FOREIGN_PID=''

# fail prints the failure plus native process/socket and firmware-model logs,
# then exits so registered traps can stop the isolated fixture resources.
fail() {
	printf '%s\n' "FAIL: virtual ARM native: $*" >&2
	netstat -nlp >&2 2>/dev/null || true
	for log in "${MODEL_ROOT}"/*.log "${MODEL_ROOT}/firmware.calls"; do
		[ ! -f "${log}" ] || {
			printf '%s\n' "Evidence: ${log}" >&2
			tail -40 "${log}" >&2
		}
	done
	exit 1
}

# pass writes an assertion result to stdout; it does not claim firmware
# equivalence for modeled operations.
pass() {
	printf '%s\n' "PASS: virtual ARM native: $*"
}

# cleanup terminates this fixture's foreign owner and modeled DNS processes,
# then removes only its resolver mount.
cleanup() {
	[ -z "${FOREIGN_PID}" ] || kill -TERM "${FOREIGN_PID}" 2>/dev/null || true
	if [ -x /sbin/service ]; then /sbin/service stop_dnsmasq >/dev/null 2>&1 || true; fi
	if [ -n "${PROCS:-}" ]; then
		for pid in $(pidof "${PROCS}" 2>/dev/null); do kill -TERM "${pid}" 2>/dev/null || true; done
	fi
	if df -P 2>/dev/null | grep -q '/tmp/resolv.conf'; then umount /tmp/resolv.conf 2>/dev/null || true; fi
}

# query invokes the native UDP/TCP DNS checker and turns any mismatch into a
# fixture failure.
query() {
	/usr/bin/agh-dns-query "$@" || fail "native DNS query failed: $*"
}

# assert_dnsmasq sets the instance config scope, verifies process/socket
# ownership, performs DNS queries, and records the assertion result.
assert_dnsmasq() {
	local port
	port="$1"
	ADGUARDHOME_DNSMASQ_CONFIGS='/etc/dnsmasq.conf /etc/dnsmasq-1.conf'
	dnsmasq_instances_ready "${port}" || fail "main/SDN native dnsmasq not ready on ${port}"
	query 192.168.77.1 "${port}" udp A client.test 192.168.77.42
	query 192.168.77.1 "${port}" tcp PTR 42.77.168.192.in-addr.arpa client.test
	query 192.168.88.1 "${port}" udp A guest.sdn.test 192.168.88.42
	query 192.168.88.1 "${port}" tcp A guest.sdn.test 192.168.88.42
	pass "main and modeled SDN native dnsmasq own TCP/UDP port ${port} and answer DNS"
}

# write_preferences overwrites the isolated product preference file with the
# requested DNS mode/local-cache inputs and explicit modeled settings.
write_preferences() {
	cat >/opt/etc/AdGuardHome/.config <<EOF
ADGUARD_INSTALL_MODE="lan"
ADGUARD_DNSMASQ_MODE="$1"
ADGUARD_LOCAL="$2"
ADGUARD_IPSET="NO"
ADGUARD_WEBUI_PORT="3000"
ADGUARD_NETCHECK_MODE="lan"
ADGUARD_NETCHECK_TIMEOUT="10"
ADGUARD_PROC_OPTIMIZE="NO"
ADGUARDHOME_READY_TIMEOUT="90"
ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"
EOF
}

[ -r /run/virtual-arm-guest ] && [ "$(id -u)" = 0 ] && [ -d "${REPO_ROOT}/tools/virtual-arm/native" ] ||
	{
		printf '%s\n' 'FAIL: native scenario requires the isolated virtual ARM guest marker, root and /repo' >&2
		exit 1
	}
ARCH="${1:-${VIRTUAL_ARM_ARCH:-$(cat /run/virtual-arm-guest)}}"
case "${ARCH}:$(uname -m)" in
	armv5:armv7l | armv7:armv7* | armv8:aarch64) ;;
	*) fail "selected architecture does not match guest kernel: ${ARCH}:$(uname -m)" ;;
esac
if [ "${ARCH}" = armv5 ]; then
	features="$(awk -F: '$1 ~ /^Features[[:space:]]*$/ { print $2 }' /proc/cpuinfo)"
	[ -n "${features}" ] || fail 'software-float package guest did not report native CPU features'
	if printf '%s\n' "${features}" | grep -Eq '(^|[[:space:]])(vfp[^[:space:]]*|neon)([[:space:]]|$)'; then
		fail 'armv5 package guest exposes VFP or NEON instead of software-float execution'
	fi
	pass 'armv5 compatibility package runs on older ARMv7 Cortex-A9 guest with software float and VFP/NEON disabled'
elif [ "${ARCH}" = armv7 ]; then
	features="$(awk -F: '$1 ~ /^Features[[:space:]]*$/ { print $2 }' /proc/cpuinfo)"
	case " ${features} " in
		*' vfp'*' neon '* | *' neon '*' vfp'*) ;;
		*) fail 'armv7 hard-float guest did not expose both VFP and NEON' ;;
	esac
	pass 'armv7 package runs on newer Cortex-A15 guest with hard float and VFP/NEON enabled'
fi
CHANNELS='beta edge stable'

case "${ARCH}" in
	armv5) package_description='archive armv5 / Debian armel; CPU ARMv7 Cortex-A9; software float' ;;
	armv7) package_description='archive armv7 / Debian armhf; CPU ARMv7 Cortex-A15; hard float' ;;
	armv8) package_description='archive arm64 / Debian arm64; CPU ARMv8-A Cortex-A53; AAPCS64' ;;
	*) fail "unknown package target: ${ARCH}" ;;
esac
printf '%s\n' "Native package=${ARCH} (${package_description}) kernel_machine=$(uname -m) kernel=$(uname -r) channels=${CHANNELS}" \
	'Firmware model: nvram, service DNS regeneration, cru scheduling and one SDN topology; process identities, sockets, DNS messages, signals and resolver mounts execute in the guest kernel.'
[ ! -e "${MODEL_ROOT}" ] || fail 'native fixture already exists'
(umask 077 && mkdir -p "${MODEL_ROOT}/nvram" /jffs/addons/AdGuardHome.d /jffs/scripts \
	/opt/etc/AdGuardHome /opt/etc/init.d /opt/sbin /opt/var/run /rom/etc) || fail 'could not create guest fixture'
trap cleanup 0
trap 'fail "native scenario interrupted by HUP/INT/TERM"' HUP INT TERM

for model in nvram service cru get_mtlan; do
	case "${model}" in
		nvram) destination=/bin/nvram ;;
		service) destination=/sbin/service ;;
		*) destination="/usr/sbin/${model}" ;;
	esac
	cp "${REPO_ROOT}/tools/virtual-arm/native/${model}" "${destination}" && chmod 755 "${destination}" || fail "could not install ${model} model"
done
for entry in http_username=root lan_ifname=br0 lan_ipaddr=192.168.77.1 rc_support=mtlancfg \
	success_start_service=1 ntp_ready=1 time_zone_x=UTC ipv6_rtr_addr=; do
	/bin/nvram set "${entry}" || fail "could not seed modeled NVRAM: ${entry}"
done
ip link set lo up || fail 'could not bring guest loopback up'
for interface in br0 br1; do
	ip link add "${interface}" type dummy && ip link set "${interface}" up || fail "could not create native ${interface} interface"
done
ip addr add 192.168.77.1/24 dev br0 && ip addr add 192.168.88.1/24 dev br1 || fail 'could not assign guest main/SDN addresses'
printf '%s\n' '127.0.0.1 localhost' >/etc/hosts || fail 'could not set native localhost hosts entry'
printf '%s\n' 'nameserver 192.168.77.1' >/tmp/resolv.conf || fail 'could not initialize native resolver'
printf '%s\n' 'nameserver 127.0.0.1' >/rom/etc/resolv.conf || fail 'could not initialize ROM resolver model'
rm -f /etc/resolv.conf && ln -s /tmp/resolv.conf /etc/resolv.conf || fail 'could not route guest resolver to native file'
printf '%s\n' UTC >/etc/TZ || fail 'could not set guest timezone'

for script in AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome; do
	case "${script}" in
		AdGuardHome.sh) destination=/jffs/addons/AdGuardHome.d/AdGuardHome.sh ;;
		*) destination="/opt/etc/init.d/${script}" ;;
	esac
	cp "${REPO_ROOT}/${script}" "${destination}" && chmod 755 "${destination}" || fail "could not install actual product script ${script}"
done
cat >/jffs/scripts/dnsmasq.postconf <<'EOF'
#!/bin/sh
[ -x /jffs/addons/AdGuardHome.d/AdGuardHome.sh ] && /jffs/addons/AdGuardHome.d/AdGuardHome.sh dnsmasq pre_start "$@"
EOF
cat >/jffs/scripts/dnsmasq-sdn.postconf <<'EOF'
#!/bin/sh
[ -x /jffs/addons/AdGuardHome.d/AdGuardHome.sh ] && /jffs/addons/AdGuardHome.d/AdGuardHome.sh dnsmasq-sdn 1 "$@"
EOF
chmod 755 /jffs/scripts/dnsmasq.postconf /jffs/scripts/dnsmasq-sdn.postconf || fail 'could not make modeled firmware hooks executable'

cat >/opt/etc/AdGuardHome/AdGuardHome.yaml <<'EOF'
http:
  address: 192.168.77.1:3000
users: []
dns:
  bind_hosts:
    - 127.0.0.1
    - 192.168.77.1
  port: 53
  upstream_dns:
    - 127.0.0.1:553
    - '[/sdn.test/]192.168.88.1:553'
  bootstrap_dns: []
  fallback_dns: []
  local_ptr_upstreams:
    - 127.0.0.1:553
  use_private_ptr_resolvers: true
  resolve_clients: false
  cache_size: 0
filters: []
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
querylog:
  enabled: false
statistics:
  enabled: false
schema_version: 27
EOF
write_preferences enabled NO || fail 'could not write lifecycle preferences'
for channel in ${CHANNELS}; do
	case "${channel}" in stable | beta | edge) ;; *) fail "unknown native channel: ${channel}" ;; esac
	case "${ARCH}" in armv8) archive_target=arm64 ;; *) archive_target="${ARCH}" ;; esac
	archive="${REPO_ROOT}/${ARCH}/AdGuardHome_${channel}_linux_${archive_target}.tar.gz"
	[ -f "${archive}" ] && [ -f "${archive}.sha256sum" ] || fail "missing committed archive or digest: ${archive}"
	expected="$(cat "${archive}.sha256sum")"
	actual="$(sha256sum "${archive}" | awk '{print $1}')"
	[ "${expected}" = "${actual}" ] || fail "committed ${channel} archive digest mismatch"
	# Keep extraction beside the installed binary so the stable move is atomic
	# and does not duplicate its pages across the guest's ephemeral mounts.
	extract="/opt/var/virtual-arm-native-extract-${channel}"
	mkdir "${extract}" && tar -xzf "${archive}" -C "${extract}" ./AdGuardHome/AdGuardHome || fail "could not extract native ${channel} payload"
	version="$("${extract}/AdGuardHome/AdGuardHome" --version 2>&1)" || fail "${channel} binary did not execute in the native ${ARCH} package guest"
	case "${version}" in *'AdGuard Home'*'version'*) ;; *) fail "unexpected ${channel} version response: ${version}" ;; esac
	printf '%s\n' "PASS: native binary channel=${channel} ${version}"
	"${extract}/AdGuardHome/AdGuardHome" --check-config -c /opt/etc/AdGuardHome/AdGuardHome.yaml \
		--no-check-update -l /dev/null >"${MODEL_ROOT}/check-config-${channel}.log" 2>&1 || fail "native ${channel} configuration validation failed"
	if [ "${channel}" = stable ]; then
		mv "${extract}/AdGuardHome/AdGuardHome" /opt/etc/AdGuardHome/AdGuardHome || fail 'could not install native stable payload'
	fi
	rm -rf "${extract}" || fail "could not release ${channel} extraction memory"
	pass "committed ${channel} native CPU execution and configuration validation"
done
ln -s /opt/etc/AdGuardHome/AdGuardHome /opt/sbin/AdGuardHome || fail 'could not install executable link'

cat >"${MODEL_ROOT}/dnsmasq-main.base" <<EOF
user=root
no-resolv
no-hosts
bind-interfaces
listen-address=127.0.0.1,192.168.77.1
port=53
pid-file=${MODEL_ROOT}/dnsmasq-main.pid
host-record=localhost,127.0.0.1
host-record=client.test,192.168.77.42,fd00:77::42
EOF
cat >"${MODEL_ROOT}/dnsmasq-sdn.base" <<EOF
user=root
no-resolv
no-hosts
bind-interfaces
listen-address=192.168.88.1
port=53
pid-file=${MODEL_ROOT}/dnsmasq-sdn.pid
host-record=localhost,127.0.0.1
host-record=guest.sdn.test,192.168.88.42
EOF

# Keep every product function unchanged, stopping only before CLI dispatch.
awk '$0 == "case \"${1:-}\" in" { found=1; exit } { print } END { if (!found) exit 1 }' \
	"${REPO_ROOT}/AdGuardHome.sh" >"${MODEL_ROOT}/manager.helpers" || fail 'could not read actual manager functions'
awk '$0 == "PRECMD=\"pre_start_adguardhome\"" { found=1; exit } { print } END { if (!found) exit 1 }' \
	"${REPO_ROOT}/S99AdGuardHome" >"${MODEL_ROOT}/s99.helpers" || fail 'could not read actual startup functions'
# shellcheck disable=SC1090
. "${MODEL_ROOT}/manager.helpers"
# shellcheck disable=SC1090
. "${MODEL_ROOT}/s99.helpers"
LOG_FILE="${MODEL_ROOT}/AdGuardHome.log"
PRECMD=pre_start_adguardhome
POSTCMD=post_start_adguardhome
POSTFAILCMD=post_start_failure_adguardhome
DESC=AdGuardHome
LOWER_SCRIPT_LOC='. /opt/etc/init.d/rc.func.AdGuardHome'
ADGUARDHOME_STARTUP_CHECK_RETRIES=90
ADGUARDHOME_DNS_READY_RETRIES=90
ADGUARDHOME_DNSMASQ_READY_RETRIES=30
ADGUARDHOME_DNSMASQ_READY_TIMEOUT=15
export ADGUARDHOME_STARTUP_CHECK_RETRIES ADGUARDHOME_DNS_READY_RETRIES ADGUARDHOME_DNSMASQ_READY_RETRIES ADGUARDHOME_DNSMASQ_READY_TIMEOUT
load_operation_config action || fail 'could not load actual product preferences'
/sbin/service restart_dnsmasq || fail 'could not start initial main/SDN native DNS'
assert_dnsmasq 53

adguardhome_run start_adguardhome || fail 'actual manager/startup/lower-helper native startup failed'
adguardhome_single_process_running || fail 'native startup did not produce one AdGuardHome process'
adguardhome_owns_dns "$(adguardhome_dns_bind_scope)" || fail 'native AdGuardHome does not own configured TCP/UDP port53'
assert_dnsmasq 553
for server in 127.0.0.1 192.168.77.1; do
	for transport in udp tcp; do
		query "${server}" 53 "${transport}" A client.test 192.168.77.42
		query "${server}" 53 "${transport}" PTR 42.77.168.192.in-addr.arpa client.test
		query "${server}" 53 "${transport}" AAAA client.test fd00:77::42
	done
done
query 127.0.0.1 53 udp A guest.sdn.test 192.168.88.42
query 127.0.0.1 53 tcp A guest.sdn.test 192.168.88.42
curl --fail --silent --max-time 10 http://192.168.77.1:3000/control/status >"${MODEL_ROOT}/http-status.log" || fail 'native AdGuardHome HTTP API not available'
jq -e '.dns_port == 53 and .protection_enabled == true' "${MODEL_ROOT}/http-status.log" >/dev/null || fail 'native API returned unexpected DNS state'
pass 'actual manager/S99/lower startup, real A/PTR/AAAA UDP/TCP forwarding, SDN forwarding and HTTP API'

write_preferences enabled YES || fail 'could not enable optional Local Cache'
adguard_local_cache_sync verify || fail 'actual optional Local Cache could not activate with native listeners ready'
resolv_conf_is_tmp_mount || fail 'native resolver bind mount was not established'
grep -q '^nameserver 127.0.0.1$' /etc/resolv.conf || fail 'native resolver mount did not switch to loopback'
pass 'actual optional Local Cache created a kernel bind mount after native DNS readiness'

before_pid="$(pidof AdGuardHome)"
adguardhome_run restart_adguardhome || fail 'actual manager native restart failed'
after_pid="$(pidof AdGuardHome)"
[ -n "${after_pid}" ] && [ "${before_pid}" != "${after_pid}" ] || fail 'native restart did not replace the real daemon PID'
assert_dnsmasq 553
query 127.0.0.1 53 tcp A client.test 192.168.77.42
pass 'actual manager restart replaced the daemon and restored native DNS forwarding'
adguard_local_cache_sync verify || fail 'native Local Cache did not reactivate after restart'
resolv_conf_is_tmp_mount || fail 'native resolver mount was not active before stop'

adguardhome_run stop_adguardhome || fail 'actual manager native stop/recovery failed'
post_stop_process_ready && post_stop_handoff_cleared && post_stop_native_resolver_ready || fail 'actual shutdown postconditions incomplete'
! resolv_conf_is_tmp_mount || fail 'optional resolver mount survived native shutdown'
grep -q '^nameserver 192.168.77.1$' /etc/resolv.conf || fail 'native resolver file was not restored after shutdown'
assert_dnsmasq 53
pass 'actual stop removed daemon and handoff, restored resolver mount and main/SDN native TCP/UDP DNS'
adguardhome_run stop_adguardhome || fail 'repeated native stop was not idempotent'
assert_dnsmasq 53
pass 'native repeated stop retains healthy main/SDN DNS'

/sbin/service stop_dnsmasq || fail 'could not prepare native foreign-owner fixture'
write_preferences disabled NO || fail 'could not disable modeled firmware handoff for conflict fixture'
load_operation_config action || fail 'could not load conflict preferences'
/usr/bin/agh-dns-query 192.168.77.1 53 hold >"${MODEL_ROOT}/foreign-owner.log" 2>&1 &
FOREIGN_PID="$!"
attempt=0
until grep -q '^READY:' "${MODEL_ROOT}/foreign-owner.log"; do
	kill -0 "${FOREIGN_PID}" 2>/dev/null || fail 'native foreign owner exited'
	[ "${attempt}" -lt 10 ] || fail 'native foreign owner did not bind in time'
	sleep 1
	attempt="$((attempt + 1))"
done
if adguardhome_run start_adguardhome; then fail 'actual startup accepted a foreign TCP/UDP port53 owner'; fi
kill -0 "${FOREIGN_PID}" 2>/dev/null || fail 'actual startup killed the foreign native port53 owner'
post_stop_process_ready && post_stop_handoff_cleared && post_stop_native_resolver_ready || fail 'refused native startup left daemon, handoff or resolver switch'
pass 'actual startup rejected a foreign native TCP/UDP port53 owner and preserved its PID'
kill -TERM "${FOREIGN_PID}" && wait "${FOREIGN_PID}" 2>/dev/null || true
FOREIGN_PID=''
write_preferences enabled NO || fail 'could not restore native recovery preferences'
load_operation_config action || fail 'could not load final recovery preferences'
/sbin/service restart_dnsmasq || fail 'could not recover main/SDN native DNS after conflict test'
assert_dnsmasq 53
pass "${ARCH} native feature scenario complete; channels=${CHANNELS}; firmware dispatch, client DHCP, physical interfaces and soak remain outside this scenario"
