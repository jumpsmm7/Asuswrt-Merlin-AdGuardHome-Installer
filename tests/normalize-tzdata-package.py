#!/usr/bin/python3
"""Regression tests for the host-side tzdata package normalizer."""

import importlib.util
import io
import os
import pathlib
import tarfile
import tempfile
import unittest


REPO_DIR = pathlib.Path(__file__).resolve().parent.parent
NORMALIZER_PATH = REPO_DIR / "tools" / "normalize-tzdata-package.py"
SPEC = importlib.util.spec_from_file_location("normalize_tzdata_package", NORMALIZER_PATH)
NORMALIZER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NORMALIZER)


def add_file(package, name, payload):
	"""Add one regular in-memory file to a tar package."""
	member = tarfile.TarInfo(name)
	member.size = len(payload)
	package.addfile(member, io.BytesIO(payload))


class NormalizeTzdataPackageTests(unittest.TestCase):
	"""Exercise normalization and each security-sensitive rejection path."""

	def setUp(self):
		"""Create an isolated archive workspace."""
		self.temporary = tempfile.TemporaryDirectory()
		self.directory = pathlib.Path(self.temporary.name)

	def tearDown(self):
		"""Remove the isolated archive workspace."""
		self.temporary.cleanup()

	def archive(self, name="tzdata.tar.bz2"):
		"""Return a package path inside the isolated workspace."""
		return self.directory / name

	def create_package(self, archive, include_posix=False):
		"""Create a minimal tzdata package containing a file and aliases."""
		with tarfile.open(archive, "w:bz2") as package:
			add_file(package, "./usr/share/zoneinfo/Etc/UTC", b"TZif standard\n")
			add_file(package, "./usr/share/zoneinfo/right/Etc/UTC", b"TZif right\n")
			alias = tarfile.TarInfo("./usr/share/zoneinfo/UTC")
			alias.type = tarfile.SYMTYPE
			alias.linkname = "Etc/UTC"
			package.addfile(alias)
			if include_posix:
				add_file(package, "./usr/share/zoneinfo/posix/Etc/UTC", b"TZif existing\n")

	def test_normalizes_payload_and_materializes_alias(self):
		"""Synthesize POSIX files without copying the leap-second tree."""
		archive = self.archive()
		self.create_package(archive)

		NORMALIZER.main(os.fspath(archive))

		with tarfile.open(archive, "r:bz2") as package:
			members = {NORMALIZER.normalized_member_name(member.name): member for member in package.getmembers()}
			self.assertIn("usr/share/zoneinfo/posix/Etc/UTC", members)
			self.assertNotIn("usr/share/zoneinfo/posix/right/Etc/UTC", members)
			alias = members["usr/share/zoneinfo/posix/UTC"]
			self.assertTrue(alias.isfile())
			with package.extractfile(alias) as stream:
				self.assertEqual(stream.read(), b"TZif standard\n")

	def test_existing_posix_payload_is_unchanged(self):
		"""Return without rewriting a package that already has POSIX data."""
		archive = self.archive()
		self.create_package(archive, include_posix=True)
		before = archive.read_bytes()

		NORMALIZER.main(os.fspath(archive))

		self.assertEqual(archive.read_bytes(), before)

	def test_rejects_unsafe_member_and_link_paths(self):
		"""Reject traversal in both member names and symbolic-link targets."""
		for name, member_name, link_name in (
			("member.tar.bz2", "../escape", None),
			("link.tar.bz2", "usr/share/zoneinfo/UTC", "../../../../escape"),
		):
			with self.subTest(name=name):
				archive = self.archive(name)
				with tarfile.open(archive, "w:bz2") as package:
					member = tarfile.TarInfo(member_name)
					if link_name is not None:
						member.type = tarfile.SYMTYPE
						member.linkname = link_name
					package.addfile(member)
				archive_path = os.fspath(archive)
				with self.assertRaises(SystemExit):
					NORMALIZER.main(archive_path)

	def test_rejects_invalid_archive_paths(self):
		"""Reject missing, incorrectly suffixed, and symbolic-link inputs."""
		missing_path = os.fspath(self.archive("missing.tar.bz2"))
		with self.assertRaises(SystemExit):
			NORMALIZER.main(missing_path)
		invalid_suffix = self.archive("tzdata.tbz")
		invalid_suffix.touch()
		invalid_suffix_path = os.fspath(invalid_suffix)
		with self.assertRaises(SystemExit):
			NORMALIZER.main(invalid_suffix_path)
		target = self.archive()
		self.create_package(target)
		linked = self.archive("linked.tar.bz2")
		linked.symlink_to(target.name)
		linked_path = os.fspath(linked)
		with self.assertRaises(SystemExit):
			NORMALIZER.main(linked_path)

	def test_rejects_unusable_and_broken_alias_payloads(self):
		"""Reject packages without TZif data and invalid selected alias chains."""
		empty = self.archive("empty.tar.bz2")
		with tarfile.open(empty, "w:bz2") as package:
			add_file(package, "./README", b"not timezone data\n")
		empty_path = os.fspath(empty)
		with self.assertRaises(SystemExit):
			NORMALIZER.main(empty_path)

		first = tarfile.TarInfo("usr/share/zoneinfo/First")
		first.type = tarfile.SYMTYPE
		first.linkname = "Second"
		second = tarfile.TarInfo("usr/share/zoneinfo/Second")
		second.type = tarfile.SYMTYPE
		second.linkname = "First"
		members = {
			NORMALIZER.normalized_member_name(first.name): first,
			NORMALIZER.normalized_member_name(second.name): second,
		}
		with self.assertRaises(SystemExit):
			NORMALIZER.linked_file(first, members)
		del members[NORMALIZER.normalized_member_name(second.name)]
		with self.assertRaises(SystemExit):
			NORMALIZER.linked_file(first, members)


if __name__ == "__main__":
	unittest.main(argv=[__file__])
