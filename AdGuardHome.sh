#!/bin/sh

SCRIPT_LOC="$(readlink -f "$0")"
MID_SCRIPT="/jffs/addons/AdGuardHome.d/AdGuardHome.sh"
UPPER_SCRIPT="/opt/etc/init.d/S99AdGuardHome"
LOWER_SCRIPT="/opt/etc/init.d/rc.func.AdGuardHome"
if [ -f "$UPPER_SCRIPT" ]; then UPPER_SCRIPT_LOC=". $UPPER_SCRIPT"; fi
if [ -f "$LOWER_SCRIPT" ]; then LOWER_SCRIPT_LOC=". $LOWER_SCRIPT"; fi
if [ "$1" = "init-start" ] && [ ! -f "$UPPER_SCRIPT" ]; then timezone; while [ ! -f "$UPPER_SCRIPT" ]; do sleep 1; done; fi
if [ -f "$UPPER_SCRIPT" ] && [ "$(readlink -f "$UPPER_SCRIPT")" != "$SCRIPT_LOC" ]; then { exec $UPPER_SCRIPT "$@"; } && exit; elif [ -z "$PROCS" ]; then exit; fi

NAME="$(basename "$0")[$$]"

check_dns_environment () {
  local NVCHECK
  NVCHECK="0"
  if [ "$(nvram get dnspriv_enable)" != "0" ]; then { nvram set dnspriv_enable="0"; }; NVCHECK="$((NVCHECK+1))"; fi
  if [ "$(pidof stubby)" ]; then { killall -q -9 stubby; }; NVCHECK="$((NVCHECK+1))"; fi
  if [ "$(nvram get dhcp_dns1_x)" ]; then { nvram set dhcp_dns1_x=""; }; NVCHECK="$((NVCHECK+1))"; fi
  if [ "$(nvram get dhcp_dns2_x)" ]; then { nvram set dhcp_dns2_x=""; }; NVCHECK="$((NVCHECK+1))"; fi
  if [ "$(nvram get dhcpd_dns_router)" != "1" ]; then { nvram set dhcpd_dns_router="1"; }; NVCHECK="$((NVCHECK+1))"; fi
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
  [ -z "$(pidof "$PROCS")" ] && exit
  if [ -z "$(nvram get ipv6_rtr_addr)" ]; then { printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "dhcp-option=lan,6,0.0.0.0" >> $CONFIG; }; else { printf "%s\n" "port=553" "local=/$(nvram get lan_ipaddr | awk 'BEGIN{FS="."}{print $2"."$1".in-addr.arpa"}')/" "local=/10.in-addr.arpa/" "local=/$(nvram get ipv6_prefix | awk -F: '{for(i=1;i<=NF;i++)x=x""sprintf (":%4s", $i);gsub(/ /,"0",x);print x}' | cut -c 2- | cut -c 1-20 | sed 's/://g;s/^.*$/\n&\n/;tx;:x;s/\(\n.\)\(.*\)\(.\n\)/\3\2\1/;tx;s/\n//g;s/\(.\)/\1./g;s/$/ip6.arpa/')/" "dhcp-option=lan,6,0.0.0.0" >> $CONFIG; }; fi
  if [ -n "$(route | grep "br" | grep -v "br0" | grep -E "^(192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.)" | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g')" ]; then
    iCOUNT="1"
    for iVARS in $(route | grep "br" | grep -v "br0" | grep -E "(192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.)" | awk '{print $8}' | sed -e ':a; N; $!ba;s/\n/ /g'); do
      [ "$iCOUNT" = "1" ] && COUNT="$iCOUNT" && IVARS="$iVARS"
      [ "$iCOUNT" != "1" ] && COUNT="$COUNT $iCOUNT" && IVARS="$IVARS $iVARS"
      iCOUNT="$((iCOUNT+1))"
    done
    dCOUNT="1"
    for dVARS in $(route | grep "br" | grep -v "br0" | grep -E "192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.)" | awk '{print $1}' | sed -e 's/[0-9]$/1/' | sed -e ':a; N; $!ba;s/\n/ /g'); do
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
  if [ "$(nvram get dns_local_cache)" != "1" ]; then { umount /tmp/resolv.conf 2>/dev/null; }; { mount -o bind /rom/etc/resolv.conf /tmp/resolv.conf; }; fi
}

lower_script () {
  case $1 in
    *)
      $LOWER_SCRIPT_LOC "$1" "$NAME"
      ;;
  esac
}

start_AdGuardHome () {
  local STATE
  local NW_STATE
  local RES_STATE
  if [ -z "$(pidof "$PROCS")" ]; then { lower_script start; }; else { lower_script restart; }; fi
  if [ ! -f "/tmp/stats.db" ]; then { ln -sf "${WORK_DIR}/data/stats.db" "/tmp/stats.db" >/dev/null 2>&1; }; fi
  if [ ! -f "/tmp/sessions.db" ]; then { ln -sf "${WORK_DIR}/data/sessions.db" "/tmp/sessions.db" >/dev/null 2>&1; }; fi
  STATE="0"
  [ -z "$1" ] && NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")"
  [ -z "$1" ] && RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")"
  [ -z "$1" ] && while { [ "$NW_STATE" = "0" ] && [ "$RES_STATE" != "0" ] && [ "$STATE" -lt "10" ]; }; do sleep 1; NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")"; RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")"; STATE="$((STATE + 1))"; done
  [ "$STATE" -eq "10" ] && start_AdGuardHome x
  lower_script check
}

start_monitor () {
  trap '' 1 2 3 15
  trap "EXIT="1"" 9
  while [ "$(nvram get ntp_ready)" -eq "0" ]; do sleep 1; done
  local NW_STATE
  local RES_STATE
  local COUNT
  COUNT="0"
  EXIT="0"
  while true; do
    if [ "$EXIT" = "1" ]; then logger -st "$NAME" "Stopping Monitor"; trap 1 2 3 15; stop_AdGuardHome; break; fi 
    if [ "$COUNT" -gt "90" ]; then COUNT="0"; timezone; fi
    COUNT="$((COUNT + 1))"
    if [ -f "/opt/sbin/AdGuardHome" ]; then
      case $COUNT in
        "30"|"60"|"90")
          timezone
          NW_STATE="$(ping 1.1.1.1 -c1 -W2 >/dev/null 2>&1; printf "%s" "$?")"
          RES_STATE="$(nslookup google.com 127.0.0.1 >/dev/null 2>&1; printf "%s" "$?")"
          ;;
      esac
      if [ -z "$(pidof "$PROCS")" ]; then
        start_AdGuardHome
      elif { [ "$COUNT" -eq "30" ] || [ "$COUNT" -eq "60" ] || [ "$COUNT" -eq "90" ]; } && { [ "$NW_STATE" = "0" ] && [ "$RES_STATE" != "0" ]; }; then
        start_AdGuardHome
      fi
    fi
    sleep 10
  done
}

stop_AdGuardHome () {
  if [ -n "$(pidof "$PROCS")" ]; then { lower_script stop || lower_script kill; } && { lower_script check; }; { service restart_dnsmasq >/dev/null 2>&1; }; else { lower_script check; }; fi
  if [ -f "/tmp/stats.db" ]; then { rm -rf "/tmp/stats.db" >/dev/null 2>&1; }; fi
  if [ -f "/tmp/sessions.db" ]; then { rm -rf "/tmp/sessions.db" >/dev/null 2>&1; }; fi
}

timezone () {
  local SANITY
  local NOW
  local TIMEZONE
  local TARGET
  local LINK
  SANITY="$(date -u -r "$MID_SCRIPT" '+%s')"
  NOW="$(date -u '+%s')"
  TIMEZONE="/jffs/addons/AdGuardHome.d/localtime"
  TARGET="/etc/localtime"
  LINK="$(readlink "$TARGET")"
  if [ -f "$TIMEZONE" ] && [ "$LINK" = "$TIMEZONE" ]; then
    [ "$NOW" -ge "$SANITY" ] && { touch "$MID_SCRIPT"; };
  elif [ -f "$TIMEZONE" ]; then
    ln -sf $TIMEZONE $TARGET
    [ "$NOW" -le "$SANITY" ] && { date -u -s "$(date -u -r "$MID_SCRIPT" '+%Y-%m-%d %H:%M:%S')"; };
  fi
}

unset TZ
case "$1" in
  "monitor-start")
    if [ "$(pidof "S99${PROCS}" | wc -w)" -le 1 ]; then start_monitor &; fi
    ;;
  "start"|"restart")
    if [ -z "$(pidof "$PROCS")" ]; then { "$SCRIPT_LOC" init-start; }; else start_AdGuardHome; fi
    ;;
  "stop"|"kill")
    if [ -n "$(pidof "$PROCS")" ]; then { "$SCRIPT_LOC" services-stop; }; else stop_AdGuardHome; fi
    ;;
  "dnsmasq")
    dnsmasq_params
    ;;
  "init-start"|"services-stop")
    timezone
    if [ "$1" = "init-start" ]; then { printf "1" > /proc/sys/vm/overcommit_memory; }; { "$SCRIPT_LOC" monitor-start >/dev/null 2>&1; }; fi
    if [ "$1" = "services-stop" ]; then trap '' 9; [ -n "$(pidof "S99${PROCS}")" ] && { kill -9 "$(pidof "S99${PROCS}")" 2>/dev/null || killall -q -9 "S99${PROCS}" 2>/dev/null; }; trap 9; fi
    ;;
  *)
    { $LOWER_SCRIPT_LOC "$1"; } && exit
    ;;
esac
check_dns_environment
