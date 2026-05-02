#!/bin/sh
# POSIX/BusyBox ash-compatible service helpers for future installer refactoring.
# These helpers are intentionally standalone so they can be reviewed and tested
# before replacing repeated service blocks in the main installer.

agh_pid_count() {
	pidof AdGuardHome S99AdGuardHome 2>/dev/null | wc -w
}

agh_is_running() {
	[ -n "$(pidof AdGuardHome 2>/dev/null)" ]
}

agh_wait_for_pid_count() {
	_expected="$1"
	_timeout="${2:-30}"
	_elapsed=0
	while [ "${_elapsed}" -lt "${_timeout}" ]; do
		[ "$(agh_pid_count)" -eq "${_expected}" ] && return 0
		sleep 1
		_elapsed="$((_elapsed + 1))"
	done
	return 1
}

agh_service_start() {
	if service start_AdGuardHome >/dev/null 2>&1; then
		agh_wait_for_pid_count 2 30
		return $?
	fi
	if /opt/etc/init.d/S99AdGuardHome start >/dev/null 2>&1; then
		agh_wait_for_pid_count 2 30
		return $?
	fi
	return 1
}

agh_service_stop() {
	if service stop_AdGuardHome >/dev/null 2>&1; then
		agh_wait_for_pid_count 0 30
		return $?
	fi
	if /opt/etc/init.d/S99AdGuardHome stop >/dev/null 2>&1; then
		agh_wait_for_pid_count 0 30
		return $?
	fi
	if /opt/etc/init.d/S99AdGuardHome kill >/dev/null 2>&1; then
		agh_wait_for_pid_count 0 30
		return $?
	fi
	killall -q -9 AdGuardHome 2>/dev/null || true
	rm -f /opt/var/run/AdGuardHome.pid 2>/dev/null || true
	agh_wait_for_pid_count 0 30
}

agh_service_restart() {
	if service restart_AdGuardHome >/dev/null 2>&1; then
		agh_wait_for_pid_count 2 30
		return $?
	fi
	if /opt/etc/init.d/S99AdGuardHome restart >/dev/null 2>&1; then
		agh_wait_for_pid_count 2 30
		return $?
	fi
	agh_service_stop && agh_service_start
}

agh_service_check() {
	/opt/etc/init.d/S99AdGuardHome check
}
