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
RIGHT_PREFIX = f"{ZONEINFO_PREFIX}right/"


def strip_prefix(value, prefix):
	"""Return value without prefix when it starts with that prefix."""
	return value[len(prefix) :] if value.startswith(prefix) else value


def normalized_member_name(name):
	"""Normalize an archive member name without treating it as a host path."""
	return posixpath.normpath(strip_prefix(name, "./"))


def validate_member(member):
	"""Reject archive members and links that can escape the archive root."""
	name = normalized_member_name(member.name)
	if member.name.startswith("/") or name == ".." or name.startswith("../"):
		raise SystemExit(f"Unsafe archive member path: {member.name}")
	if not (member.issym() or member.islnk()):
		return
	link_name = normalized_member_name(member.linkname)
	if member.linkname.startswith("/"):
		raise SystemExit(f"Unsafe archive link: {member.name} -> {member.linkname}")
	if member.issym():
		link_name = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname))
	if link_name == ".." or link_name.startswith("../"):
		raise SystemExit(f"Unsafe archive link: {member.name} -> {member.linkname}")


def is_timezone_file(package, member):
	"""Return whether a regular archive member starts with the TZif magic."""
	if not member.isfile():
		return False
	stream = package.extractfile(member)
	if stream is None:
		return False
	try:
		return stream.read(4) == b"TZif"
	finally:
		stream.close()


def link_target(member):
	"""Return the normalized in-archive target of a link member."""
	name = normalized_member_name(member.name)
	target = normalized_member_name(member.linkname)
	if member.issym():
		target = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname))
	return target


def linked_file(member, members_by_name):
	"""Resolve an in-archive link chain to its regular member."""
	visited = set()
	while member.issym() or member.islnk():
		name = normalized_member_name(member.name)
		if name in visited:
			raise SystemExit(f"Cyclic archive link: {name}")
		visited.add(name)
		target = link_target(member)
		if target not in members_by_name:
			raise SystemExit(f"Missing archive link target: {name} -> {target}")
		member = members_by_name[target]
	return member


def timezone_names(package, members):
	"""Collect usable timezone files and aliases, excluding special trees."""
	names = {
		normalized_member_name(member.name)
		for member in members
		if normalized_member_name(member.name).startswith(ZONEINFO_PREFIX)
		and not normalized_member_name(member.name).startswith(RIGHT_PREFIX)
		and not normalized_member_name(member.name).startswith(POSIX_PREFIX)
		and is_timezone_file(package, member)
	}
	while True:
		linked_names = {
			normalized_member_name(member.name)
			for member in members
			if (member.issym() or member.islnk()) and link_target(member) in names
		}
		new_names = linked_names - names
		if not new_names:
			return names
		names.update(new_names)


def copy_member(package, output, member, output_member=None):
	"""Copy one member and guarantee closure of its extracted data stream."""
	stream = package.extractfile(member) if member.isfile() else None
	try:
		# Member paths were validated before this archive-to-archive copy. No host
		# filesystem extraction occurs here.
		output.addfile(output_member or member, stream)  # NOSONAR
	finally:
		if stream is not None:
			stream.close()


def is_timezone_directory(member, name, names):
	"""Return whether a directory is needed by a selected timezone member."""
	return member.isdir() and (
		name == ZONEINFO_PREFIX.rstrip("/") or name.startswith(ZONEINFO_PREFIX)
	) and any(timezone_name.startswith(f"{name}/") for timezone_name in names)


def add_posix_members(package, output, members, names):
	"""Append installer-compatible POSIX members to an output archive."""
	members_by_name = {normalized_member_name(member.name): member for member in members}
	for member in members:
		name = normalized_member_name(member.name)
		if name not in names and not is_timezone_directory(member, name, names):
			continue
		posix_member = copy.copy(member)
		relative_name = "" if name == ZONEINFO_PREFIX.rstrip("/") else strip_prefix(name, ZONEINFO_PREFIX)
		posix_member.name = f"./{POSIX_PREFIX}{relative_name}"
		source_member = member
		if member.issym() or member.islnk():
			source_member = linked_file(member, members_by_name)
			posix_member.type = tarfile.REGTYPE
			posix_member.linkname = ""
			posix_member.size = source_member.size
		copy_member(package, output, source_member, posix_member)


def validated_archive_path(archive):
	"""Resolve and validate the caller-selected package before rewriting it."""
	resolved = os.path.abspath(archive)
	if not resolved.endswith(".tar.bz2"):
		raise SystemExit(f"Package must use the .tar.bz2 suffix: {archive}")
	if os.path.islink(resolved) or not os.path.isfile(resolved):
		raise SystemExit(f"Package is not a regular file: {archive}")
	return resolved


def rewrite_archive(archive, members, names):
	"""Rewrite a validated package atomically with its POSIX payload."""
	directory = os.path.dirname(archive)
	with tempfile.NamedTemporaryFile(dir=directory, delete=False) as temporary:  # NOSONAR
		temporary_name = temporary.name
	try:
		# The CLI path is canonicalized and validated as a regular .tar.bz2 file.
		with tarfile.open(archive, "r:bz2") as package, tarfile.open(temporary_name, "w:bz2") as output:  # NOSONAR
			for member in members:
				copy_member(package, output, member)
			add_posix_members(package, output, members, names)
		os.replace(temporary_name, archive)  # NOSONAR
	finally:
		if os.path.exists(temporary_name):
			os.unlink(temporary_name)


def main(archive):
	"""Validate and normalize one bzip2-compressed tzdata package."""
	archive = validated_archive_path(archive)
	with tarfile.open(archive, "r:bz2") as package:  # NOSONAR
		members = package.getmembers()
		for member in members:
			validate_member(member)
		if any(normalized_member_name(member.name).startswith(POSIX_PREFIX) and member.isfile() for member in members):
			return
		names = timezone_names(package, members)
	if not names:
		raise SystemExit(f"Package has no usable {ZONEINFO_PREFIX} timezone payload: {archive}")
	rewrite_archive(archive, members, names)


if __name__ == "__main__":
	if len(sys.argv) != 2:
		raise SystemExit(f"Usage: {sys.argv[0]} PACKAGE")
	main(sys.argv[1])
