#!/bin/sh
# Verify missing policies are safe and saved choices survive install/upgrade.
set -eu
ROOT="$(mktemp -d)"
trap 'rm -rf "${ROOT}"' EXIT HUP INT TERM
sed -n '/^configure_runtime_defaults() {$/,/^}$/p; /^cli_dns_port_policy() {$/,/^}$/p' installer >"${ROOT}/functions"
. "${ROOT}/functions"
CONF_FILE="${ROOT}/config"
INFO=info
ERROR=error
PTXT() { :; }
ptxt_ok() { :; }
nvram() { :; }
adguard_install_feature_defaults() { :; }
write_conf() {
 awk -F= -v key="$1" '$1 != key' "${CONF_FILE}" >"${CONF_FILE}.new"
 printf '%s=%s\n' "$1" "$2" >>"${CONF_FILE}.new"
 mv "${CONF_FILE}.new" "${CONF_FILE}"
}
write_conf_if_absent() {
 grep -q "^$1=" "${CONF_FILE}" || write_conf "$@"
}
cli_write_quoted_conf() { write_conf "$1" "\"$2\""; }
for mode in new-install upgrade; do
 for saved in missing 0 1; do
  : >"${CONF_FILE}"
  expected=1
  if [ "${saved}" != missing ]; then
   printf 'ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="%s"\n' "${saved}" >"${CONF_FILE}"
   expected="${saved}"
  fi
  configure_runtime_defaults "${mode}" wan
  grep -qx "ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL=\"${expected}\"" "${CONF_FILE}"
 done
done
cli_dns_port_policy --policy legacy
grep -qx 'ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="0"' "${CONF_FILE}"
cli_dns_port_policy --policy refuse-unknown
grep -qx 'ADGUARDHOME_REFUSE_UNKNOWN_DNS_PORT_KILL="1"' "${CONF_FILE}"
printf '%s\n' 'PASS: safe missing DNS policy and preserved explicit choices'
