#!/bin/sh
value="${value:-default}"
parent="${value%pattern}"
child="${value#pattern}"
read -r line
valid_function() { printf '%s\n' "${line}"; }
awk '
  function words(value, parts) {
    prefix = substr(value, 1, 3)
    count = split(value, parts, "/")
    text = "function select source timeout"
  }
' input
pattern='function|select|source|timeout'
# [[ x ]]; source file; set -o pipefail; timeout command
cat <<'DOC'
[[ example ]]
source ./example
value=${value//old/new}
timeout 10 example
DOC
valid_function
