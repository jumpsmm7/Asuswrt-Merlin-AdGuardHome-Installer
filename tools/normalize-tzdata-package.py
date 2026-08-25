#!/usr/bin/python3
"""Add the POSIX timezone tree expected by the router installer when absent."""

import copy
import os
import posixpath
import sys
import tarfile
import tempfile


ZONEINFO_PREFIX = "usr/share/zoneinfo/"
POSIX_PREFIX = f"{ZONEINFO_PREFIX}posix/"


def strip_prefix(value, prefix):
	return value[len(prefix):] if value.startswith(prefix) else value


def normalized_member_name(name):
	return posixpath.normpath(strip_prefix(name, "./"))


def validate_member(member):
	name = normalized_member_name(member.name)
	if member.name.startswith("/") or name == ".." or name.startswith("../"):
		raise SystemExit(f"Unsafe archive member path: {member.name}")
	if member.issym() or member.islnk():
		link_name = normalized_member_name(member.linkname)
		if member.linkname.startswith("/"):
			raise SystemExit(f"Unsafe archive link: {member.name} -> {member.linkname}")
		if member.issym():
			link_name = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname))
		if link_name == ".." or link_name.startswith("../"):
			raise SystemExit(f"Unsafe archive link: {member.name} -> {member.linkname}")


def is_timezone_file(package, member):
	if not member.isfile():
		return False
	stream = package.extractfile(member)
	return stream is not None and stream.read(4) == b"TZif"


def link_target(member):
	name = normalized_member_name(member.name)
	target = normalized_member_name(member.linkname)
	if member.issym():
		target = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname))
	return target


def main(archive):
	directory = os.path.dirname(os.path.abspath(archive))
	with tarfile.open(archive, "r:bz2") as package:
		members = package.getmembers()
		for member in members:
			validate_member(member)
		if any(normalized_member_name(member.name).startswith(POSIX_PREFIX) and member.isfile() for member in members):
			return

		timezone_names = {
			normalized_member_name(member.name)
			for member in members
			if normalized_member_name(member.name).startswith(ZONEINFO_PREFIX)
			and is_timezone_file(package, member)
		}
		while True:
			linked_names = {
				normalized_member_name(member.name)
				for member in members
				if (member.issym() or member.islnk()) and link_target(member) in timezone_names
			}
			new_names = linked_names - timezone_names
			if not new_names:
				break
			timezone_names.update(new_names)
		if not timezone_names:
			raise SystemExit(f"Package has no usable {ZONEINFO_PREFIX} timezone payload: {archive}")

		with tempfile.NamedTemporaryFile(dir=directory, delete=False) as temporary:
			temporary_name = temporary.name
	try:
		with tarfile.open(archive, "r:bz2") as package, tarfile.open(temporary_name, "w:bz2") as output:
			members = package.getmembers()
			for member in members:
				stream = package.extractfile(member) if member.isfile() else None
				output.addfile(member, stream)
			for member in members:
				name = normalized_member_name(member.name)
				is_timezone_directory = member.isdir() and (
					name == ZONEINFO_PREFIX.rstrip("/") or name.startswith(ZONEINFO_PREFIX)
				) and any(
					timezone_name.startswith(f"{name}/") for timezone_name in timezone_names
				)
				if name not in timezone_names and not is_timezone_directory:
					continue
				posix_member = copy.copy(member)
				relative_name = "" if name == ZONEINFO_PREFIX.rstrip("/") else strip_prefix(name, ZONEINFO_PREFIX)
				posix_member.name = f"./{POSIX_PREFIX}{relative_name}"
				if member.islnk():
					posix_member.linkname = f"./{POSIX_PREFIX}{strip_prefix(link_target(member), ZONEINFO_PREFIX)}"
				stream = package.extractfile(member) if member.isfile() else None
				output.addfile(posix_member, stream)
		os.replace(temporary_name, archive)
	finally:
		if os.path.exists(temporary_name):
			os.unlink(temporary_name)


if __name__ == "__main__":
	if len(sys.argv) != 2:
		raise SystemExit(f"Usage: {sys.argv[0]} PACKAGE")
	main(sys.argv[1])
