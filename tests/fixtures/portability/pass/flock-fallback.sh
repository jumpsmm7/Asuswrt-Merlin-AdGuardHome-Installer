#!/bin/sh
flock_supports_fd() { return 1; }
# Keep the mkdir/PID fallback when descriptor-lock flock is unavailable.
if which flock >/dev/null 2>&1 && flock_supports_fd; then
  flock 8
else
  mkdir "${LOCK_DIR}/mkdir" || exit 1
  printf '%s %s\n' "$$" "${START_TIME}" >"${LOCK_DIR}/mkdir/pid"
fi
