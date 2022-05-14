#!/bin/sh

SCRIPT_LOC="$(readlink -f "$0")"
CONF_FILE="/opt/etc/AdGuardHome/.config"
MID_SCRIPT="/jffs/addons/AdGuardHome.d/AdGuardHome.sh"
UPPER_SCRIPT="/opt/etc/init.d/S99AdGuardHome"
LOWER_SCRIPT="/opt/etc/init.d/rc.func.AdGuardHome"
if [ -f "$UPPER_SCRIPT" ]; then UPPER_SCRIPT_LOC=". $UPPER_SCRIPT"; fi
if [ -f "$LOWER_SCRIPT" ]; then LOWER_SCRIPT_LOC=". $LOWER_SCRIPT"; fi
if [ "$1" = "init-start" ] && [ ! -f "$UPPER_SCRIPT" ]; then timezone; while [ ! -f "$UPPER_SCRIPT" ]; do sleep 1; done; fi
if [ -f "$UPPER_SCRIPT" ]; then { if { [ "$(readlink -f "$UPPER_SCRIPT")" != "$SCRIPT_LOC" ] || [ "$0" != "$UPPER_SCRIPT" ]; }; then { exec $UPPER_SCRIPT "$@"; } && exit; fi; }; else { if [ -z "$PROCS" ]; then exit; fi; }; fi
{ for PID in $(pidof "S99${PROCS}"); do if { awk '{ print }' "/proc/${PID}/cmdline" | grep -q monitor-start; } && [ "$PID" != "$$" ]; then { MON_PID="$PID"; }; fi; done; };

NAME="$(basename "$0")[$$]"

AdGuardHome_Run () {
  local lock_dir
  local pid_file
  lock_dir="/tmp/AdGuardHome"
  pid_file="${lock_dir}/pid"
  if ( mkdir ${lock_dir} ) 2> /dev/null; then
    printf "%s\n" "$$" > $pid_file
    trap 'rm -rf "$lock_dir"; exit $?' EXIT
    start="$(date +%s)"
    $1
    end="$(date +%s)"
    runtime="$((end-start))"
    logger -st "$NAME" "$@ took $runtime second(s) to complete."
    rm -rf "$lock_dir"
    trap - EXIT
  else
    logger -st "$NAME" "Lock owned by $(cat $pid_file) exists; preventing duplicate runs!"
  fi
}

check_dns_environment () {
  local NVCHECK
  NVCHECK="0"
  if [ "$(nvram get dnspriv_enable)" != "0" ]; then { nvram set dnspriv_enable="0"; }; NVCHECK="$((NVCHECK+1))"; fi
  if [ "$(pidof stubby)" ]; then { killall -q -9 stubby 2>/dev/null; }; NVCHECK="$((NVCHECK+1))"; fi
  if [ "$(nvram get dhcp_dns1_x)" ] && [ "$NVCHECK" != "0" ]; then { nvram set dhcp_dns1_x=""; }; NVCHECK="$((NVCHECK+1))"; fi
  if [ "$(nvram get dhcp_dns2_x)" ] && [ "$NVCHECK" != "0" ]; then { nvram set dhcp_dns2_x=""; }; NVCHECK="$((NVCHECK+1))"; fi
  if [ "$(nvram get dhcpd_dns_router)" != "1" ] && [ "$NVCHECK" != "0" ]; then { nvram set dhcpd_dns_router="1"; }; NVCHECK="$((NVCHECK+1))"; fi
  if [ "$NVCHECK" != "0" ]; then { nvram commit; }; { service restart_dnsmasq >/dev/null 2>&1; }; while { [ "$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")" = "0" ] && [ "$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")" != "0" ]; }; do sleep 1; done; fi
}

dnsmasq_params () {
  local CONFIG
  local COUNT
  local iCOUNT
  local dCOUNT
  local iVARS
  local IVARS
  local dVARS
  local DVARS
  local NIVARS
  local NDVARS
  local i
  CONFIG="/etc/dnsmasq.conf"
  if { [ "$(nvram get dns_local_cache)" != "1" ] && [ "$(readlink -f /tmp/resolv.conf)" = "/rom/etc/resolv.conf" ]; }; then { umount /tmp/resolv.conf 2>/dev/null; }; fi
  if [ -n "$(pidof "$PROCS")" ]; then
    if [ -z "$(nvram get ipv6_rtr_addr)" ]; then { printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "dhcp-option=lan,6,0.0.0.0" >> $CONFIG; }; else { printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "local=/$(nvram get ipv6_prefix | awk -F: '{for(i=1;i<=NF;i++)x=x""sprintf (":%4s", $i);gsub(/ /,"0",x);print x}' | cut -c 2- | cut -c 1-20 | sed 's/://g;s/^.*$/\n&\n/;tx;:x;s/\(\n.\)\(.*\)\(.\n\)/\3\2\1/;tx;s/\n//g;s/\(.\)/\1./g;s/$/ip6.arpa/')/" "dhcp-option=lan,6,0.0.0.0" >> $CONFIG; }; fi
    if [ -n "$(route | grep "br" | grep -v "br0" | grep -oE '\b^(((10|127)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3})|(((172\.(1[6-9]|2[0-9]|3[0-1]))|(192\.168))(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){2}))\b' | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g')" ]; then
      iCOUNT="1"
      for iVARS in $(route | grep "br" | grep -v "br0" | grep -E '\b^(((10|127)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3})|(((172\.(1[6-9]|2[0-9]|3[0-1]))|(192\.168))(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){2}))\b' | awk '{print $8}' | sed -e ':a; N; $!ba;s/\n/ /g'); do
        [ "$iCOUNT" = "1" ] && COUNT="$iCOUNT" && IVARS="$iVARS"
        [ "$iCOUNT" != "1" ] && COUNT="$COUNT $iCOUNT" && IVARS="$IVARS $iVARS"
        iCOUNT="$((iCOUNT+1))"
      done
      dCOUNT="1"
      for dVARS in $(route | grep "br" | grep -v "br0" | grep -oE '\b^(((10|127)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3})|(((172\.(1[6-9]|2[0-9]|3[0-1]))|(192\.168))(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){2}))\b' | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g'); do
        [ "$dCOUNT" = "1" ] && DVARS="$dVARS"
        [ "$dCOUNT" != "1" ] && DVARS="$DVARS $dVARS"
        dCOUNT="$((dCOUNT+1))"
      done
      for i in $COUNT; do
        NIVARS="$(printf "%s\n" "$IVARS" | cut -d' ' -f"$i")"
        NDVARS="$(printf "%s\n" "$DVARS" | cut -d' ' -f"$i")"
        printf "%s\n" "dhcp-option=${NIVARS},6,${NDVARS}" >> $CONFIG
      done
    fi
    if { [ "$(nvram get dns_local_cache)" != "1" ] && [ "$(awk -F'=' '/ADGUARD_LOCAL/ {print $2}' "$CONF_FILE" | sed -e 's/^"//' -e 's/"$//')" = "YES" ]; }; then { mount -o bind /rom/etc/resolv.conf /tmp/resolv.conf; }; fi
  fi
}

lower_script () {
  case $1 in
    *)
      $LOWER_SCRIPT_LOC "$1" "$NAME"
      ;;
  esac
}

proc_optimizations () {
  { printf "2" > /proc/sys/vm/overcommit_memory; }; # Ensure ratio algorithm checks properly work including swap.
  { printf "2500000" > /proc/sys/net/core/rmem_max; }; # Ensure UDP receive buffer set to 2.5M.
  { printf "0" > /proc/sys/net/ipv4/icmp_ratelimit; }; # Ensure Control over MTRS
  { printf "256" > /proc/sys/net/ipv4/neigh/default/gc_thresh1; }; # Increase ARP cache sizes and GC thresholds
  { printf "1024" > /proc/sys/net/ipv4/neigh/default/gc_thresh2; }; # Increase ARP cache sizes and GC thresholds
  { printf "2048" > /proc/sys/net/ipv4/neigh/default/gc_thresh3; }; # Increase ARP cache sizes and GC thresholds
  { printf "240" > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_max_retrans; }; # Lower conntrack tcp_timeout_max_retrans from 300 to 240
  if [ -n "$(nvram get ipv6_service)" ]; then #IPV6 proc variants
    { printf "0" > /proc/sys/net/ipv6/icmp/ratelimit; };
    { printf "256" > /proc/sys/net/ipv6/neigh/default/gc_thresh1; };
    { printf "1024" > /proc/sys/net/ipv6/neigh/default/gc_thresh2; };
    { printf "2048" > /proc/sys/net/ipv6/neigh/default/gc_thresh3; };
  fi
}

start_AdGuardHome () {
  local STATE
  local NW_STATE
  local RES_STATE
  if [ -z "$(pidof "$PROCS")" ]; then { lower_script start; }; else { lower_script restart; }; fi
  for db in stats.db sessions.db; do { if [ ! "$(readlink -f "/tmp/${db}")" = "$(readlink -f "${WORK_DIR}/data/${db}")" ]; then { ln -s "${WORK_DIR}/data/${db}" "/tmp/${db}" >/dev/null 2>&1; }; fi; }; done
  STATE="0"
  [ -z "$1" ] && NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")"
  [ -z "$1" ] && RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")"
  [ -z "$1" ] && while { [ "$NW_STATE" = "0" ] && [ "$RES_STATE" != "0" ] && [ "$STATE" -lt "10" ]; }; do sleep 1; NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")"; RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")"; STATE="$((STATE + 1))"; done
  [ "$STATE" -eq "10" ] && start_AdGuardHome x
}

start_monitor () {
  trap '' HUP INT QUIT ABRT TERM
  trap 'EXIT="1"' USR1
  trap 'EXIT="2"' USR2
  while [ "$(nvram get ntp_ready)" -eq "0" ]; do sleep 1; done
  local NW_STATE
  local RES_STATE
  local COUNT
  local EXIT
  EXIT="0"
  logger -st "$NAME" "Starting Monitor!"
  while true; do
    if [ "$EXIT" = "1" ]; then logger -st "$NAME" "Stopping Monitor!"; trap - HUP INT QUIT ABRT USR1 USR2 TERM; { AdGuardHome_Run stop_AdGuardHome; }; break; fi
    if [ "$EXIT" = "2" ]; then { AdGuardHome_Run start_AdGuardHome; }; EXIT="0"; fi
    if [ -z "$COUNT" ]; then COUNT="0"; timezone; fi
    if [ "$COUNT" = "90" ]; then COUNT="0"; else COUNT="$((COUNT + 1))"; fi
    if [ -f "/opt/sbin/AdGuardHome" ]; then
      case $COUNT in
        "30"|"60"|"90")
          timezone
          NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")"
          RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")"
          ;;
      esac
      if [ -z "$(pidof "$PROCS")" ]; then
        logger -st "$NAME" "Warning: $PROCS is dead; Monitor will start it!"
        AdGuardHome_Run start_AdGuardHome
      elif { [ "$COUNT" -eq "30" ] || [ "$COUNT" -eq "60" ] || [ "$COUNT" -eq "90" ]; } && { [ "$NW_STATE" = "0" ] && [ "$RES_STATE" != "0" ]; }; then
        logger -st "$NAME" "Warning: $PROCS is not responding; Monitor will re-start it!"
        AdGuardHome_Run start_AdGuardHome
      fi
    fi
    sleep 10
  done
}

stop_monitor () {
  local SIGNAL
  case "$1" in
    "$MON_PID")
      SIGNAL="USR2"
      ;;
    "$$")
      if [ -n "$MON_PID" ]; then SIGNAL="USR1"; else { AdGuardHome_Run stop_AdGuardHome; }; fi
      ;;
  esac
  [ -n "$SIGNAL" ] && { kill -s "$SIGNAL" "$MON_PID" 2>/dev/null; };
}

stop_AdGuardHome () {
  if [ -n "$(pidof "$PROCS")" ]; then { lower_script stop || lower_script kill; }; { until [ -z "$(pidof "$PROCS")" ]; do sleep 1; done; }; { service restart_dnsmasq >/dev/null 2>&1; }; fi
  for db in stats.db sessions.db; do { if [ "$(readlink -f "/tmp/${db}")" = "$(readlink -f "${WORK_DIR}/data/${db}")" ]; then { rm "/tmp/${db}" >/dev/null 2>&1; }; fi; }; done
}

timezone () {
  local TIMEZONE
  local TARGET
  TIMEZONE="/jffs/addons/AdGuardHome.d/localtime"
  TARGET="/etc/localtime"
  if { [ ! -f "$TARGET" ] && [ -f "$TIMEZONE" ]; }; then { ln -sf "$TIMEZONE" "$TARGET"; }; fi
  if [ -f "$TARGET" ] || [ "$(readlink "$TARGET")" ]; then { if [ "$(date -u '+%s')" -le "$(date -u -r "$MID_SCRIPT" '+%s')" ]; then { date -u -s "$(date -u -r "$MID_SCRIPT" '+%Y-%m-%d %H:%M:%S')"; }; else { touch "$MID_SCRIPT"; }; fi; }; fi
}

unset TZ
case "$1" in
  "monitor-start")
    if [ -n "$MON_PID" ]; then { stop_monitor "$MON_PID"; }; else { start_monitor & }; fi
    ;;
  "start"|"restart")
    { "$SCRIPT_LOC" init-start >/dev/null 2>&1; };
    ;;
  "stop"|"kill")
    { "$SCRIPT_LOC" services-stop >/dev/null 2>&1; };
    ;;
  "dnsmasq")
    dnsmasq_params
    ;;
  "init-start"|"services-stop")
    timezone
    case "$1" in
      "init-start")
        proc_optimizations
        { "$SCRIPT_LOC" monitor-start; };
        ;;
      "services-stop")
        { stop_monitor "$$"; };
        ;;
    esac
    ;;
  *)
    { $LOWER_SCRIPT_LOC "$1"; } && exit
    ;;
esac
check_dns_environment
