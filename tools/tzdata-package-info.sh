#!/bin/sh

extract_package_info() {
	local package_file package_info_member
	package_file="$1"
	package_info_member="$(tar -tf "${package_file}" 2>/dev/null |
		awk '$0 == ".PKGINFO" || $0 == "./.PKGINFO" { print; exit }')"
	if [ -z "${package_info_member}" ]; then
		return 1
	fi

	tar -xOf "${package_file}" "${package_info_member}" 2>/dev/null
}
