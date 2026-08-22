#!/bin/sh
ensure_opkg_package python3
/opt/bin/python3 "${BLOCKLIST_ANALYZER_FILE}" blocklist_analyzer
