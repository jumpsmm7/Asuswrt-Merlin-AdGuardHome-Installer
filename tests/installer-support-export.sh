#!/bin/sh
# Execute extracted real helpers. Only fixed router input paths are rewritten;
# procfs clock/PID ownership, staging, signals, limits and publication stay real.
set -u

INSTALLER_PATH="${1:-installer}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/installer-support-export.XXXXXX")" || exit 1
TEST_SHELL="${SUPPORT_EXPORT_TEST_SHELL:-sh}"
# Remove this test fixture and terminate workers recorded by its probe models.
cleanup() {
	# Test probe PIDs are recorded only by our fixture, never read from reports.
	if [ -f "${TEST_ROOT}/workers" ]; then
		while read -r pid; do kill -KILL "${pid}" 2>/dev/null || true; done <"${TEST_ROOT}/workers"
	fi
	rm -rf "${TEST_ROOT}"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM
# Stop the regression with a concrete support-export failure.
fail() {
	printf '%s\n' "FAIL: support export: $*" >&2
	exit 1
}
awk '
	/^support_export[a-z_]*\(\) \{$/ { copying=1 }
	copying { print }
	copying && /^}$/ { copying=0 }
' "${INSTALLER_PATH}" >"${TEST_ROOT}/extracted" || fail 'could not extract helpers'
grep -q '^support_export() {$' "${TEST_ROOT}/extracted" || fail 'installer has no support-export helper'

# These are input-path substitutions, not replacement collector implementations.
# External fixture commands below model read-only firmware outputs; all filesystem
# operations, probe execution, procfs identity checks and output publication run.
sed -e "s|/opt|${TEST_ROOT}/fs/opt|g" \
	-e "s|/jffs|${TEST_ROOT}/fs/jffs|g" \
	-e "s|/tmp/AdGuardHome|${TEST_ROOT}/fs/tmp/AdGuardHome|g" \
	-e "s|/proc/meminfo|${TEST_ROOT}/fs/meminfo|g" \
	"${TEST_ROOT}/extracted" >"${TEST_ROOT}/functions" || fail 'could not isolate inputs'
mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/fs/opt/etc/AdGuardHome" \
	"${TEST_ROOT}/fs/opt/bin" "${TEST_ROOT}/fs/jffs/scripts" "${TEST_ROOT}/fs/tmp" "${TEST_ROOT}/out" || exit 1
REAL_DD="$(which dd)"
export REAL_DD
export TEST_ROOT
PATH="${TEST_ROOT}/bin:${PATH}"
export PATH

cat >"${TEST_ROOT}/bin/probe-model" <<'MODEL'
#!/bin/sh
name="${0##*/}"
printf '%s\n' "${name} $*" >>"${TEST_ROOT}/calls"
case "${SX_FIXTURE:-normal}:${name}" in
	hang-all:nvram | hang-all:uname | hang-all:df | hang-all:pidof | hang-all:ps | hang-all:netstat | pidof-hang:pidof | signal:nvram)
		printf '%s\n' "$$" >>"${TEST_ROOT}/workers"
		sleep 60 &
		printf '%s\n' "$!" >>"${TEST_ROOT}/workers"
		wait
		exit 0 ;;
	overflow:nvram)
		# Exceeds the real per-probe RLIMIT_FSIZE; never accepted as data.
		exec dd if=/dev/zero bs=1024 count=128 ;;
	missing:*) exit 127 ;;
	pidof-absent:pidof | legacy-ps:ps) exit 1 ;;
	pidof-invalid:pidof) printf '%s\n' '501 private-token'; exit 0 ;;
esac
case "${name}" in
	nvram)
		[ "$#" -eq 2 ] && [ "$1" = get ] || exit 93
		if [ "${SX_FIXTURE:-normal}" = malicious ]; then
			printf '%s\n' 'RT-AC68U' 'injected=SECRET_PASSWORD'; exit 0
		fi
		case "$2" in
			productid) printf '%s\n' "${SX_ROUTER_MODEL:-RT-AC68U}" ;;
			firmver) printf '%s\n' 3004 ;;
			buildno) printf '%s\n' 388 ;;
			extendno) printf '%s\n' 8_4 ;;
			*) exit 93 ;;
		esac ;;
	uname)
		[ "$*" = -m ] || exit 93
		if [ "${SX_FIXTURE:-normal}" = malicious ]; then printf '%s\n' armv7lSECRET_TOKEN; else printf '%s\n' armv7l; fi ;;
	df)
		[ "$1" = -Pk ] && [ "$#" -eq 2 ] || exit 93
		printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on' '192.168.50.21:/SECRET_DOMAIN 99999 123 99876 1% /PRIVATE_PATH' ;;
	pidof) [ "$*" = AdGuardHome ] || exit 93; printf '%s\n' '501 502' ;;
	ps)
		[ "$*" = -ww ] || exit 93
		if [ "${SX_FIXTURE:-normal}" = sized ]; then exec "${REAL_DD}" "if=${TEST_ROOT}/sized-ps" bs=1024 2>/dev/null; fi
		printf '%s\n' '301 root /opt/sbin/AdGuardHome.sh monitor-start SECRET_TOKEN 192.168.50.22' '302 root /opt/AdGuardHome --password SECRET_PASSWORD' ;;
	netstat)
		[ "$*" = -nltup ] || exit 93
		if [ "${SX_FIXTURE:-normal}" = sized ]; then exec "${REAL_DD}" "if=${TEST_ROOT}/sized-netstat" bs=1024 2>/dev/null; fi
		printf '%s\n' 'tcp 0 0 192.168.50.23:53 0.0.0.0:* LISTEN 501/AdGuardHome' 'udp 0 0 10.20.30.40:553 0.0.0.0:* 601/dnsmasq' 'tcp6 0 0 fd00::10:553 :::* LISTEN 777/private-program' 'udp 0 0 172.16.4.2:5300 0.0.0.0:* 777/SECRET_DOMAIN' ;;
	*) printf '%s\n' "MUTATION ${name}" >>"${TEST_ROOT}/calls"; exit 93 ;;
esac
MODEL
chmod 700 "${TEST_ROOT}/bin/probe-model"
for command in nvram uname df pidof ps netstat service opkg iptables ip6tables curl wget reboot; do
	ln -s probe-model "${TEST_ROOT}/bin/${command}" || exit 1
done
# Host-only polling acceleration. Router stock usleep is available; this fixture
# does not change deadlines, which still use live monotonic seconds.
cat >"${TEST_ROOT}/bin/usleep" <<'MODEL'
#!/bin/sh
if [ -x /bin/busybox ]; then exec /bin/busybox usleep 20000; fi
exec sleep 0.02
MODEL
chmod 700 "${TEST_ROOT}/bin/usleep"
cat >"${TEST_ROOT}/bin/dd" <<'MODEL'
#!/bin/sh
printf '%s\n' "dd $*" >>"${TEST_ROOT}/calls"
if [ "${SX_FIXTURE:-normal}" = hang-all ]; then
	printf '%s\n' "$$" >>"${TEST_ROOT}/workers"
	exec sleep 60
fi
exec "${REAL_DD}" "$@"
MODEL
chmod 700 "${TEST_ROOT}/bin/dd"
cat >"${TEST_ROOT}/fs/opt/etc/AdGuardHome/AdGuardHome" <<'MODEL'
#!/bin/sh
[ "$*" = --version ] || exit 93
if [ "${SX_FIXTURE:-normal}" = hang-all ]; then printf '%s\n' "$$" >>"${TEST_ROOT}/workers"; exec sleep 60; fi
if [ "${SX_FIXTURE:-normal}" = malicious ]; then
	printf '%s\n' 'AdGuard Home, version v0.107.59SECRET_TOKEN'
else
	printf '%s\n' 'AdGuard Home, version v0.107.59'
fi
MODEL
chmod 700 "${TEST_ROOT}/fs/opt/etc/AdGuardHome/AdGuardHome"
cat >"${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config" <<'MODEL'
INSTALLER_BRANCH="v2.7.0"
ADGUARD_BRANCH="beta"
PASSWORD="SECRET_PASSWORD"
TOKEN="SECRET_TOKEN"
DOMAIN="SECRET_DOMAIN"
EXECUTE="$(touch SHOULD_NOT_EXIST)"
MODEL
printf '%s\n' 'password: SECRET_PASSWORD' 'query: SECRET_DOMAIN' 'client: 192.168.50.24' >"${TEST_ROOT}/fs/opt/etc/AdGuardHome/AdGuardHome.yaml"
printf '%s\n' 'SECRET_DOMAIN 10.20.30.41 SECRET_TOKEN' >"${TEST_ROOT}/fs/opt/etc/AdGuardHome/querylog.json"
printf '%s\n' 'MemTotal: 256000 kB' 'MemAvailable: 128000 kB' 'MemFree: 64000 kB' 'SwapTotal: 1024000 kB' 'SwapFree: 1023999 kB' >"${TEST_ROOT}/fs/meminfo"
for hook in dnsmasq.postconf dnsmasq-sdn.postconf init-start services-stop service-event-end firewall-start; do
	printf '%s\n' '#!/bin/sh' '# SECRET_PASSWORD SECRET_DOMAIN 192.168.50.25' >"${TEST_ROOT}/fs/jffs/scripts/${hook}"
	chmod 700 "${TEST_ROOT}/fs/jffs/scripts/${hook}"
done
printf '%s\n' 'context=DNS NVRAM transaction' 'result=rollback complete' 'detail=SECRET_TOKEN 172.16.4.3' >"${TEST_ROOT}/fs/opt/etc/.AdGuardHome.rollback_result"
: >"${TEST_ROOT}/fs/opt/etc/.AdGuardHome.nvram"
cat >"${TEST_ROOT}/run" <<'RUN'
#!/bin/sh
. "${TEST_ROOT}/functions"
AI_VERSION="${SX_INSTALLER_VERSION:-2.7.0}"
SUPPORT_EXPORT_RECOVERY_STATUS=checked
# A modeled failed write followed by successful writes must remain fatal.
printf() {
	if [ "${SX_FAULT:-}" = emit-write ] && [ "${2:-}" = router.model ]; then return 1; fi
	command printf "$@"
}
support_export "$@"
RUN
chmod 700 "${TEST_ROOT}/run"

# Exact schema and key-specific types. No successful report may invent a field.
cat >"${TEST_ROOT}/schema" <<'SCHEMA'
support.schema|1
support.privacy|allowlist
support.upload|none
installer.version|version
installer.source|reference
adguardhome.channel|unknown|release|stable|beta|edge
adguardhome.version|version
router.model|model
router.firmver|firmware
router.buildno|firmware
router.extendno|firmware
router.architecture|unknown|armv5l|armv5tel|armv6l|armv7l|armv8l|aarch64|mips|mipsel
entware.state|missing|available
installation.state|absent|present|unsafe
storage.opt.available_kib|integer
storage.jffs.available_kib|integer
memory.MemTotal.kib|integer
memory.MemAvailable.kib|integer
memory.MemFree.kib|integer
memory.SwapTotal.kib|integer
memory.SwapFree.kib|integer
process.daemon.count|integer
process.monitor.count|integer
listener.tcp.53.owner|unknown|none|adguardhome|dnsmasq|foreign|mixed|unowned
listener.udp.53.owner|unknown|none|adguardhome|dnsmasq|foreign|mixed|unowned
listener.tcp.553.owner|unknown|none|adguardhome|dnsmasq|foreign|mixed|unowned
listener.udp.553.owner|unknown|none|adguardhome|dnsmasq|foreign|mixed|unowned
recovery.nvram|absent|present|unsafe
recovery.event_hooks|absent|present|unsafe
recovery.binary_cleanup|absent|present|unsafe
recovery.dns_handoff|absent|present|unsafe
recovery.prior_startup|not-reported|unknown|checked|completed|failed|pending
recovery.rollback.result|none|unsafe|unknown|complete|incomplete|not-attempted
recovery.rollback.stage|none|unknown|binary-replace|directory-restore|restore|setup|nvram|event-hooks|package|yaml|blocklist|operation|service|install
collection.failed_probes|integer
collection.timed_out_probes|integer
SCHEMA
for hook in dnsmasq.postconf dnsmasq-sdn.postconf init-start services-stop service-event-end firewall-start; do
	printf '%s\n' "hook.${hook}.state|missing|present|unsafe" "hook.${hook}.header|unknown|valid|invalid" "hook.${hook}.executable|yes|no" >>"${TEST_ROOT}/schema"
done
# Check every report key, type, permission and privacy bound against the schema.
validate() {
	report="$1"
	[ -f "${report}" ] && [ ! -L "${report}" ] || fail 'report is not a regular file'
	[ "$(wc -c <"${report}")" -le 16384 ] || fail 'report exceeded 16KiB'
	[ "$(ls -l "${report}" | awk '{print $1}')" = -rw------- ] || fail 'report mode is not 0600'
	awk -F '|' 'NR==FNR { key=$1; schema[key]=substr($0,length(key)+2); next }
		{
			line=$0; split(line, pair, "="); key=pair[1]; value=substr(line,length(key)+2)
			if (!(key in schema) || seen[key]++ || length(value)>96 || value ~ /[[:cntrl:]]/) exit 1
			type=schema[key]
			if (type=="integer") valid=(value=="unknown" || value ~ /^[0-9]+$/ && length(value)<=12)
			else if (type=="version") valid=(value=="unknown" || value ~ /^v?[0-9]+[.][0-9]+[.][0-9]+(-([abr][.][0-9]+|rc[.][1-9][0-9]?))?([+][0-9a-f]+)?$/ && length(value)<=64)
			else if (type=="model") valid=(value=="unknown" || value ~ /^(RT|GT|TUF|RP)-[A-Z]+[0-9][0-9A-Z_+-]*$|^(ET|XT|XD)[0-9][0-9A-Z_+-]*$/ && length(value)<=32)
			else if (type=="firmware") valid=(value=="unknown" || value ~ /^[0-9][0-9._-]*[0-9]$/ && length(value)<=32 || value ~ /^[0-9]$/)
			else if (type=="reference") valid=(value ~ /^(master|dev[0-9]?|unknown|custom)$/ || value ~ /^v[0-9]+[.][0-9]+[.][0-9]+(-rc[.][1-9][0-9]?)?$/ && length(value)<=32 || length(value)==40 && value ~ /^[0-9a-fA-F]+$/)
			else { valid=0; n=split(type, allowed, "|"); for(i=1;i<=n;i++) if (value==allowed[i]) valid=1 }
			if (!valid) exit 1
		}
		END { for(key in schema) if (seen[key]!=1) exit 1 }
	' "${TEST_ROOT}/schema" "${report}" || fail "invalid schema in ${report##*/}"
	if grep -E 'SECRET_|192[.]168[.]|10[.]20[.]|172[.]16[.]|fd00:|PRIVATE_PATH|SHOULD_NOT_EXIST|private-program|injected=' "${report}" >/dev/null; then fail 'private data escaped allowlist'; fi
}
# Require an exact report field or fixture sentinel.
expect() {
	grep -Fx "$2" "$1" >/dev/null || fail "missing expected field $2 in ${1##*/}"
}
# Aggregate probe audit output outside the collector child file-size limit.
audit_calls() {
	if [ -f "${TEST_ROOT}/calls" ]; then
		cat "${TEST_ROOT}/calls" >>"${TEST_ROOT}/all-calls"
	fi
}
# Execute the actual extracted collector and validate its completed report.
run() {
	: >"${TEST_ROOT}/calls"
	SX_FIXTURE="$1" export SX_FIXTURE
	"${TEST_SHELL}" "${TEST_ROOT}/run" --output "${TEST_ROOT}/out/$2" >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr" || fail "$1 collection failed: $(cat "${TEST_ROOT}/stderr")"
	audit_calls
	validate "${TEST_ROOT}/out/$2"
}
# Require successful owned cleanup after ordinary completion or refusal.
no_stage() {
	[ -z "$(find "${TEST_ROOT}/out" -name '.AdGuardHome.support-export.*' -print)" ] || fail 'owned staging leaked'
}
# Require an invocation to reject its arguments or output path safely.
refuse() {
	: >"${TEST_ROOT}/calls"
	if "${TEST_SHELL}" "${TEST_ROOT}/run" "$@" >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"; then fail 'unsafe destination accepted'; fi
	audit_calls
	no_stage
}

# A missing implementation is a real red baseline, independent of report checks.
printf '%s\n' '#!/bin/sh' >"${TEST_ROOT}/baseline"
if sh "$0" "${TEST_ROOT}/baseline" >"${TEST_ROOT}/baseline-log" 2>&1; then fail 'missing-helper baseline passed'; fi
grep -q 'has no support-export helper' "${TEST_ROOT}/baseline-log" || fail 'baseline did not fail at the missing implementation'

find "${TEST_ROOT}/fs" -type f -exec sha256sum '{}' \; | sort >"${TEST_ROOT}/before"
run normal normal.txt
expect "${TEST_ROOT}/out/normal.txt" installer.version=2.7.0
expect "${TEST_ROOT}/out/normal.txt" installer.source=v2.7.0
expect "${TEST_ROOT}/out/normal.txt" adguardhome.version=v0.107.59
expect "${TEST_ROOT}/out/normal.txt" adguardhome.channel=beta
expect "${TEST_ROOT}/out/normal.txt" process.daemon.count=2
expect "${TEST_ROOT}/out/normal.txt" process.monitor.count=1
expect "${TEST_ROOT}/out/normal.txt" listener.tcp.53.owner=adguardhome
expect "${TEST_ROOT}/out/normal.txt" listener.udp.553.owner=dnsmasq
expect "${TEST_ROOT}/out/normal.txt" listener.tcp.553.owner=foreign
expect "${TEST_ROOT}/out/normal.txt" recovery.rollback.result=complete
expect "${TEST_ROOT}/out/normal.txt" recovery.rollback.stage=nvram
expect "${TEST_ROOT}/out/normal.txt" entware.state=missing
expect "${TEST_ROOT}/out/normal.txt" recovery.prior_startup=checked
find "${TEST_ROOT}/fs" -type f -exec sha256sum '{}' \; | sort >"${TEST_ROOT}/after"
cmp "${TEST_ROOT}/before" "${TEST_ROOT}/after" >/dev/null || fail 'collection changed router inputs'
[ ! -e "${TEST_ROOT}/out/SHOULD_NOT_EXIST" ] || fail 'configuration was sourced'
no_stage
# Preserve legitimate firmware product IDs without relaxing prefixes or bounds.
for model in RT-AX86U_PRO RT-AX88U_PRO GT-AX11000_PRO GT-BE98_PRO; do
	SX_ROUTER_MODEL="${model}" export SX_ROUTER_MODEL
	run normal "model-${model}.txt"
	expect "${TEST_ROOT}/out/model-${model}.txt" "router.model=${model}"
done
model_case=0
for model in CUSTOM-AX86U_PRO RT-_AX86U_PRO 'RT-AX86U_PRO;SECRET_TOKEN' RT-AX86U_PROXXXXXXXXXXXXXXXXXXXXX; do
	model_case="$((model_case + 1))"
	SX_ROUTER_MODEL="${model}" export SX_ROUTER_MODEL
	run normal "model-invalid-${model_case}.txt"
	expect "${TEST_ROOT}/out/model-invalid-${model_case}.txt" router.model=unknown
done
unset SX_ROUTER_MODEL
cp "${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config" "${TEST_ROOT}/config-saved"
printf '%s\n' 'INSTALLER_BRANCH="v2.7.0SECRET_TOKEN"' 'ADGUARD_BRANCH="beta;SECRET_PASSWORD"' 'TOKEN=SECRET_TOKEN' >"${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config"
run malicious malicious.txt
expect "${TEST_ROOT}/out/malicious.txt" installer.source=custom
expect "${TEST_ROOT}/out/malicious.txt" adguardhome.channel=unknown
mv "${TEST_ROOT}/config-saved" "${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config"
for field in router.model router.firmver router.buildno router.extendno router.architecture adguardhome.version; do expect "${TEST_ROOT}/out/malicious.txt" "${field}=unknown"; done
# Actual release-candidate installer/source identities stay useful, while
# zero, leading-zero and oversized RC numbers cannot become report values.
cp "${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config" "${TEST_ROOT}/source-saved"
for suffix in 1 99 0 01 100; do
	SX_INSTALLER_VERSION="v2.7.0-rc.${suffix}" export SX_INSTALLER_VERSION
	printf 'INSTALLER_BRANCH="%s"\nADGUARD_BRANCH="beta"\n' "${SX_INSTALLER_VERSION}" >"${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config"
	run normal "rc-${suffix}.txt"
	case "${suffix}" in
		1 | 99)
			expect "${TEST_ROOT}/out/rc-${suffix}.txt" "installer.version=${SX_INSTALLER_VERSION}"
			expect "${TEST_ROOT}/out/rc-${suffix}.txt" "installer.source=${SX_INSTALLER_VERSION}"
			;;
		*)
			expect "${TEST_ROOT}/out/rc-${suffix}.txt" installer.version=unknown
			expect "${TEST_ROOT}/out/rc-${suffix}.txt" installer.source=custom
			;;
	esac
done
unset SX_INSTALLER_VERSION
mv "${TEST_ROOT}/source-saved" "${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config"
: >"${TEST_ROOT}/fs/opt/bin/opkg"
chmod 700 "${TEST_ROOT}/fs/opt/bin/opkg"
run normal entware.txt
expect "${TEST_ROOT}/out/entware.txt" entware.state=available
rm "${TEST_ROOT}/fs/opt/bin/opkg"
run pidof-absent absent.txt
expect "${TEST_ROOT}/out/absent.txt" process.daemon.count=0
run legacy-ps legacy-ps.txt
expect "${TEST_ROOT}/out/legacy-ps.txt" process.monitor.count=unknown
run pidof-invalid invalid.txt
expect "${TEST_ROOT}/out/invalid.txt" process.daemon.count=unknown
run pidof-hang hung.txt
expect "${TEST_ROOT}/out/hung.txt" process.daemon.count=unknown
expect "${TEST_ROOT}/out/hung.txt" collection.timed_out_probes=1
run overflow overflow.txt
expect "${TEST_ROOT}/out/overflow.txt" router.model=unknown
expect "${TEST_ROOT}/out/overflow.txt" collection.failed_probes=4
no_stage

# Legitimate process/socket/configuration snapshots between 4 and 8 KiB must
# remain usable. Put selected values at the end so a prefix cannot look complete.
cp "${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config" "${TEST_ROOT}/sized-config-saved"
printf '%s\n' '301 root /opt/sbin/AdGuardHome.sh monitor-start SECRET_TOKEN 192.168.50.22' >"${TEST_ROOT}/tail-ps"
printf '%s\n' 'tcp 0 0 192.168.50.23:53 0.0.0.0:* LISTEN 501/AdGuardHome' 'udp 0 0 10.20.30.40:553 0.0.0.0:* 601/dnsmasq' >"${TEST_ROOT}/tail-netstat"
printf '%s\n' 'INSTALLER_BRANCH="v2.7.0"' 'ADGUARD_BRANCH="beta"' >"${TEST_ROOT}/tail-config"
for size in 4096 6144 8191 8192 8193; do
	for input in ps netstat config; do
		bytes="$(wc -c <"${TEST_ROOT}/tail-${input}")"
		awk -v padding="$((size - bytes))" 'BEGIN { while (padding-- > 0) printf "\n" }' >"${TEST_ROOT}/sized-${input}"
		cat "${TEST_ROOT}/tail-${input}" >>"${TEST_ROOT}/sized-${input}"
		[ "$(wc -c <"${TEST_ROOT}/sized-${input}")" -eq "${size}" ] || fail 'sized probe fixture has the wrong byte count'
	done
	cp "${TEST_ROOT}/sized-config" "${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config"
	run sized "sized-${size}.txt"
	if [ "${size}" -lt 8192 ]; then
		expect "${TEST_ROOT}/out/sized-${size}.txt" process.monitor.count=1
		expect "${TEST_ROOT}/out/sized-${size}.txt" listener.tcp.53.owner=adguardhome
		expect "${TEST_ROOT}/out/sized-${size}.txt" listener.udp.553.owner=dnsmasq
		expect "${TEST_ROOT}/out/sized-${size}.txt" installer.source=v2.7.0
		expect "${TEST_ROOT}/out/sized-${size}.txt" adguardhome.channel=beta
		expect "${TEST_ROOT}/out/sized-${size}.txt" collection.failed_probes=0
	else
		for field in process.monitor.count listener.tcp.53.owner listener.udp.553.owner installer.source adguardhome.channel; do
			expect "${TEST_ROOT}/out/sized-${size}.txt" "${field}=unknown"
		done
		expect "${TEST_ROOT}/out/sized-${size}.txt" collection.failed_probes=3
	fi
done
mv "${TEST_ROOT}/sized-config-saved" "${TEST_ROOT}/fs/opt/etc/AdGuardHome/.config"
no_stage

# A writer may ignore SIGXFSZ and return success after a partial write. Execute
# the real probe and require both its kernel file cap and whole-snapshot refusal.
cat >"${TEST_ROOT}/bin/probe-cap" <<'MODEL'
#!/bin/sh
trap '' XFSZ
"${REAL_DD}" if=/dev/zero bs=1024 count=128 2>/dev/null
exit 0
MODEL
chmod 700 "${TEST_ROOT}/bin/probe-cap"
cat >"${TEST_ROOT}/probe-cap-run" <<'RUN'
#!/bin/sh
. "${TEST_ROOT}/functions"
SX_STAGE="${TEST_ROOT}/probe-cap-stage"
mkdir -p "${SX_STAGE}/work" || exit 1
SX_CHILD_PID=''
SX_FAILURES=0
SX_TIMEOUTS=0
support_export_clock || exit 1
SX_DEADLINE="$((SX_NOW + 30))"
if support_export_probe "${TEST_ROOT}/bin/probe-cap"; then exit 1; fi
[ "${SX_PROBE_STATUS}" -eq 125 ] && [ "${SX_FAILURES}" -eq 1 ] || exit 1
# BusyBox ash uses 512-byte blocks; some validation-host shells use 1024.
case "$(wc -c <"${SX_STAGE}/work/probe")" in 8192 | 16384) ;; *) exit 1 ;; esac
RUN
"${TEST_SHELL}" "${TEST_ROOT}/probe-cap-run" || fail 'probe parsed a successful partial write or lost its kernel file cap'

# Model only the renderer to exercise the real publication path and report cap.
# The ordinary collector/schema assertions above still execute actual rendering.
cat >"${TEST_ROOT}/report-cap-run" <<'RUN'
#!/bin/sh
. "${TEST_ROOT}/functions"
# Produce exact report sizes without changing the fixed production schema.
support_export_collect() {
	"${REAL_DD}" "if=${TEST_ROOT}/sized-report" bs=1024 2>/dev/null
}
support_export "$@"
RUN
for size in 8193 16384 16385 32769; do
	awk -v bytes="${size}" 'BEGIN { while (bytes-- > 0) printf "x" }' >"${TEST_ROOT}/sized-report"
	if "${TEST_SHELL}" "${TEST_ROOT}/report-cap-run" --output "${TEST_ROOT}/out/report-${size}" >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"; then
		[ "${size}" -le 16384 ] || fail 'oversized report was published'
		[ "$(wc -c <"${TEST_ROOT}/out/report-${size}")" -eq "${size}" ] || fail 'report was published partially'
	else
		[ "${size}" -gt 16384 ] || fail 'report within 16KiB was refused'
		[ ! -e "${TEST_ROOT}/out/report-${size}" ] || fail 'failed report was published'
	fi
	no_stage
done

# Use actual production rollback contexts/results, grouped into fixed categories.
# Raw context/result/detail text must never become report data.
cp "${TEST_ROOT}/fs/opt/etc/.AdGuardHome.rollback_result" "${TEST_ROOT}/rollback-saved"
rollback_case_count=0
while IFS='|' read -r context raw_result expected_stage expected_result; do
	rollback_case_count="$((rollback_case_count + 1))"
	printf 'context=%s\nresult=%s\ndetail=SECRET_PASSWORD 192.168.50.26\n' "${context}" "${raw_result}" >"${TEST_ROOT}/fs/opt/etc/.AdGuardHome.rollback_result"
	run normal "rollback-${rollback_case_count}.txt"
	expect "${TEST_ROOT}/out/rollback-${rollback_case_count}.txt" "recovery.rollback.stage=${expected_stage}"
	expect "${TEST_ROOT}/out/rollback-${rollback_case_count}.txt" "recovery.rollback.result=${expected_result}"
done <<'CASES'
package install|rollback unavailable|package|incomplete
backup restore|rollback complete|restore|complete
NVRAM transaction|incomplete prior rollback detected|nvram|incomplete
DNS NVRAM transaction|rollback complete|nvram|complete
DNSFilter NVRAM transaction|rollback partial|nvram|incomplete
yaml validation|yaml-quarantine-failed|yaml|incomplete
blocklist yaml replacement|restored|blocklist|complete
blocklist-yaml|failed: no change|blocklist|not-attempted
operation|interrupted: no rollback attempted|operation|not-attempted
AdGuardHome service restart|restart-failed|service|incomplete
installer abort|restart-failed|install|incomplete
AdGuardHome binary rollback|restored|binary-replace|complete
AdGuardHome directory rollback|cleanup-failed|directory-restore|incomplete
setup-yaml|rollback complete|setup|complete
SECRET_DOMAIN|SECRET_TOKEN|unknown|unknown
CASES
mv "${TEST_ROOT}/rollback-saved" "${TEST_ROOT}/fs/opt/etc/.AdGuardHome.rollback_result"
no_stage

# Refuse existing files, hardlinks, both symlink kinds, directories and FIFOs.
cp "${TEST_ROOT}/out/normal.txt" "${TEST_ROOT}/untouched"
ln "${TEST_ROOT}/untouched" "${TEST_ROOT}/out/hardlink"
ln -s "${TEST_ROOT}/untouched" "${TEST_ROOT}/out/symlink"
ln -s "${TEST_ROOT}/absent" "${TEST_ROOT}/out/dangling"
mkdir "${TEST_ROOT}/out/directory"
mkfifo "${TEST_ROOT}/out/fifo"
for path in normal.txt hardlink symlink dangling directory fifo; do refuse --output "${TEST_ROOT}/out/${path}"; done
cmp "${TEST_ROOT}/untouched" "${TEST_ROOT}/out/normal.txt" >/dev/null || fail 'existing destination changed'
refuse
refuse --output relative.txt
bad_name="$(printf 'bad\nname')"
refuse --output "${TEST_ROOT}/out/${bad_name}"
refuse --output "${TEST_ROOT}/out/../wrong"
refuse --output "${TEST_ROOT}/out/new" extra
ln -s "${TEST_ROOT}/out" "${TEST_ROOT}/out-link"
refuse --output "${TEST_ROOT}/out-link/new"
chmod 777 "${TEST_ROOT}/out"
refuse --output "${TEST_ROOT}/out/shared.txt"
chmod 700 "${TEST_ROOT}/out"

# Real atomic-publication race and write errors, modeled at the syscall wrapper.
REAL_LN="$(which ln)"
REAL_MKDIR="$(which mkdir)"
export REAL_LN REAL_MKDIR
cat >"${TEST_ROOT}/bin/ln" <<'MODEL'
#!/bin/sh
case "${SX_FAULT:-}" in
	publish) exit 1 ;;
	ownership)
		stage="${1%/publish/*}"
		printf '%s\n' foreign-sentinel >"${stage}/foreign"
		chmod 755 "${stage}"
		exit 1 ;;
	race) printf '%s\n' sentinel >"./${1##*/}" ;;
esac
exec "${REAL_LN}" "$@"
MODEL
cat >"${TEST_ROOT}/bin/mkdir" <<'MODEL'
#!/bin/sh
if [ "${SX_FAULT:-}" = early ]; then
	case "$*" in */publish*) exit 1 ;; esac
fi
if [ "${SX_FAULT:-}" = write ]; then
	case "$*" in */publish*)
		"${REAL_MKDIR}" "$@" || exit 1
		# Existing directory at the internal report path forces real redirection failure.
		for target do case "${target}" in */publish) "${REAL_MKDIR}" "${target}/write-fault" ;; esac; done
		exit 0 ;;
	esac
fi
exec "${REAL_MKDIR}" "$@"
MODEL
chmod 700 "${TEST_ROOT}/bin/ln" "${TEST_ROOT}/bin/mkdir"
SX_FIXTURE=normal export SX_FIXTURE
SX_FAULT=publish export SX_FAULT
refuse --output "${TEST_ROOT}/out/publish-fault"
SX_FAULT=race export SX_FAULT
refuse --output "${TEST_ROOT}/out/raced"
expect "${TEST_ROOT}/out/raced" sentinel
SX_FAULT='write' export SX_FAULT
refuse --output "${TEST_ROOT}/out/write-fault"
SX_FAULT=emit-write export SX_FAULT
refuse --output "${TEST_ROOT}/out/emit-write-fault"
# A failed startup stage and a changed ownership marker must not cause
# recursive removal when the invocation can no longer prove directory identity.
for fault in early ownership; do
	: >"${TEST_ROOT}/calls"
	SX_FAULT="${fault}" export SX_FAULT
	if "${TEST_SHELL}" "${TEST_ROOT}/run" --output "${TEST_ROOT}/out/${fault}-fault" >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"; then fail 'staging fault succeeded'; fi
	audit_calls
	grep -q 'staging ownership could not be verified' "${TEST_ROOT}/stderr" || fail 'unverified stage retention was unexplained'
	retained="$(find "${TEST_ROOT}/out" -name '.AdGuardHome.support-export.*' -type d -print)"
	[ -n "${retained}" ] || fail 'unverified stage was removed'
	if [ "${fault}" = ownership ]; then expect "${retained}/foreign" foreign-sentinel; fi
	# The fixture owns these intentionally retained test directories.
	rm -rf "${retained}"
done
unset SX_FAULT
no_stage

# All potentially slow reads hang, so live monotonic time must stop the entire
# collection at its global budget, rather than granting every field two seconds.
started="$(date +%s)"
run hang-all budget.txt
elapsed="$(($(date +%s) - started))"
[ "${elapsed}" -ge 27 ] && [ "${elapsed}" -le 34 ] || fail "global budget took ${elapsed}s"
expect "${TEST_ROOT}/out/budget.txt" router.model=unknown
expect "${TEST_ROOT}/out/budget.txt" process.daemon.count=unknown
no_stage

# Verify previously timed-out processes before starting a fresh signal fixture.
workers_stopped() {
	while read -r pid; do
		if [ -r "/proc/${pid}/stat" ]; then
			IFS= read -r record <"/proc/${pid}/stat" || continue
			record="${record##*) }"
			case "${record}" in Z\ *) ;; *) fail 'probe worker survived timeout/signal' ;; esac
		fi
	done <"${TEST_ROOT}/workers"
}
workers_stopped
: >"${TEST_ROOT}/workers"
# Interruption is sent to the actual collector subshell while its probe is live.
SX_FIXTURE=signal export SX_FIXTURE
: >"${TEST_ROOT}/calls"
"${TEST_SHELL}" "${TEST_ROOT}/run" --output "${TEST_ROOT}/out/interrupted" >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr" &
runner="$!"
tries=0
while [ "${tries}" -lt 150 ] && [ ! -s "${TEST_ROOT}/workers" ]; do
	"${TEST_ROOT}/bin/usleep" 20000
	tries="$((tries + 1))"
done
# Find the collector via live kernel parent identity, without trusting input data.
collector=''
for stat in /proc/[0-9]*/stat; do
	IFS= read -r record <"${stat}" 2>/dev/null || continue
	record="${record##*) }"
	set -f
	set -- ${record}
	if [ "${2:-}" = "${runner}" ]; then
		collector="${stat#/proc/}"
		collector="${collector%/stat}"
		break
	fi
done
set +f
[ -n "${collector}" ] || fail 'did not find live collector for signal test'
kill -TERM "${collector}" || fail 'could not interrupt collector'
if wait "${runner}"; then fail 'interrupted collector succeeded'; fi
audit_calls
[ ! -e "${TEST_ROOT}/out/interrupted" ] || fail 'interrupted report published'
no_stage
# Kernel zombies are exited; no fixture worker may remain running.
workers_stopped

# Missing Entware and unavailable inputs still produce the complete useful schema.
mv "${TEST_ROOT}/fs/opt" "${TEST_ROOT}/fs/opt-away"
mv "${TEST_ROOT}/fs/jffs/scripts" "${TEST_ROOT}/fs/jffs/scripts-away"
rm "${TEST_ROOT}/fs/meminfo"
run missing missing.txt
expect "${TEST_ROOT}/out/missing.txt" installer.version=2.7.0
expect "${TEST_ROOT}/out/missing.txt" entware.state=missing
expect "${TEST_ROOT}/out/missing.txt" installation.state=absent
expect "${TEST_ROOT}/out/missing.txt" process.daemon.count=unknown
expect "${TEST_ROOT}/out/missing.txt" memory.MemTotal.kib=unknown
no_stage
[ ! -e "${TEST_ROOT}/out/SHOULD_NOT_EXIST" ] || fail 'private configuration executed'
if grep -E 'MUTATION|nvram (set|commit|show)|querylog|AdGuardHome.yaml' "${TEST_ROOT}/all-calls" >/dev/null; then fail 'unexpected state-changing/private probe'; fi
printf '%s\n' 'PASS: actual support collector schema, privacy, missing inputs, probe limits, path faults, atomic publication and signal cleanup'
