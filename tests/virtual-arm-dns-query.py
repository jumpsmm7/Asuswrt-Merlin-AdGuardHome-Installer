#!/usr/bin/env python3
"""Check native DNS assertion parsing against real local UDP/TCP responses."""

from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "tools/virtual-arm/dns-query.c"


def wire_name(name):
    """Encode the PTR response name without borrowing the client's parser."""
    return b"".join(bytes([len(label)]) + label.encode("ascii")
                    for label in name.split(".")) + b"\0"


def compression_pointer(offset):
    """Encode an explicit message offset for compression traversal cases."""
    return struct.pack("!H", 0xc000 | offset)


def receive_exact(connection, count):
    """Read one TCP DNS frame, including short stream reads."""
    result = b""
    while len(result) < count:
        chunk = connection.recv(count - len(result))
        if not chunk:
            raise RuntimeError("test client closed before sending its DNS request")
        result += chunk
    return result


class DnsAnswerValidation(unittest.TestCase):
    """Only complete messages with a matching answer can pass DNS assertions."""

    @classmethod
    def setUpClass(cls):
        """Compile the native DNS query helper once for the test class."""
        cls.temporary = tempfile.TemporaryDirectory(prefix="virtual-arm-dns-query-")
        cls.binary = Path(cls.temporary.name) / "agh-dns-query"
        try:
            subprocess.run(["cc", "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror",
                            str(SOURCE), "-o", str(cls.binary)], check=True, timeout=30)
        except BaseException:
            cls.temporary.cleanup()
            raise

    @classmethod
    def tearDownClass(cls):
        """Remove the temporary native DNS helper and its build directory."""
        cls.temporary.cleanup()

    def exercise(self, transport, kind, form):
        """Serve one crafted DNS response and assert the helper's validation result."""
        record_type, expected, data = {
            "A": (1, "192.168.77.42", socket.inet_pton(socket.AF_INET, "192.168.77.42")),
            "AAAA": (28, "fd00:77::42", socket.inet_pton(socket.AF_INET6, "fd00:77::42")),
            "PTR": (12, "client.test", wire_name("client.test")),
        }[kind]
        record = b"\xc0\x0c" + struct.pack("!HHIH", record_type, 1, 60, len(data)) + data
        authority_data = wire_name("ns.test")
        authority = b"\xc0\x0c" + struct.pack("!HHIH", 2, 1, 60, len(authority_data)) + authority_data
        opt = b"\0" + struct.pack("!HHIH", 41, 4096, 0, 0)
        forms = {
            "single": (1, 0, 0, record, True),
            "complete": (2, 0, 0, record + record, True),
            "missing": (2, 0, 0, record, False),
            "short-header": (2, 0, 0, record + b"\xc0\x0c\x00", False),
            "short-data": (2, 0, 0, record + record[:-1], False),
            "complete-authority": (1, 1, 0, record + authority, True),
            "missing-authority": (1, 1, 0, record, False),
            "short-authority-header": (1, 1, 0, record + b"\xc0\x0c\x00", False),
            "short-authority-data": (1, 1, 0, record + authority[:-1], False),
            "complete-additional": (1, 0, 1, record + opt, True),
            "missing-additional": (1, 0, 1, record, False),
            "short-additional-header": (1, 0, 1, record + b"\0\x00", False),
            "short-additional-data": (1, 0, 1,
                                      record + b"\0" + struct.pack("!HHIH", 41, 4096, 0, 4) + b"\0", False),
            "complete-all-sections": (1, 1, 1, record + authority + opt, True),
            "matching-authority-only": (0, 1, 0, record, False),
            "matching-additional-only": (0, 0, 1, record, False),
        }
        if kind == "PTR":
            owner_offset = 12 + len(wire_name("client.test")) + 4
            data_offset = owner_offset + 12

            def ptr_record(pointer):
                """Build a PTR record whose RDATA is the supplied name pointer."""
                return b"\xc0\x0c" + struct.pack("!HHIH", 12, 1, 60, len(pointer)) + pointer

            def cname_record(pointer):
                """Build a CNAME record for compression-chain validation cases."""
                return b"\xc0\x0c" + struct.pack("!HHIH", 5, 1, 60, len(pointer)) + pointer

            additional_header = struct.pack("!HHIH", 1, 1, 60, 4)
            additional_data = socket.inet_pton(socket.AF_INET, "192.168.77.42")
            forms.update({
                "backward-pointer": (1, 0, 0, ptr_record(compression_pointer(12)), True),
                "self-pointer": (1, 0, 0, ptr_record(compression_pointer(data_offset)), False),
                "forward-pointer": (1, 0, 1,
                                    ptr_record(compression_pointer(data_offset + 2)) +
                                    wire_name("client.test") + additional_header + additional_data, False),
                "backward-chain": (1, 0, 0, ptr_record(compression_pointer(owner_offset)), True),
                "forward-chain": (1, 0, 1,
                                  ptr_record(compression_pointer(data_offset + 2)) +
                                  compression_pointer(12) + additional_header + additional_data, False),
                # The second PTR first jumps backward, then encounters a forward
                # CNAME pointer whose target still precedes the original PTR data.
                "chain-forward": (2, 0, 0,
                                  cname_record(compression_pointer(data_offset + 2)) +
                                  ptr_record(compression_pointer(data_offset)), False),
                "chain-self": (2, 0, 0,
                               cname_record(compression_pointer(data_offset)) +
                               ptr_record(compression_pointer(data_offset)), False),
            })
        answer_count, authority_count, additional_count, records, accepted = forms[form]
        socktype = socket.SOCK_STREAM if transport == "tcp" else socket.SOCK_DGRAM
        server = socket.socket(socket.AF_INET, socktype)
        server.settimeout(3)
        server.bind(("127.0.0.1", 0))
        port = server.getsockname()[1]
        if transport == "tcp":
            server.listen(1)
        errors = []

        def respond():
            """Receive one query and send the crafted response over the test transport."""
            try:
                connection = None
                try:
                    if transport == "tcp":
                        connection, _ = server.accept()
                        connection.settimeout(3)
                        size = struct.unpack("!H", receive_exact(connection, 2))[0]
                        request = receive_exact(connection, size)
                    else:
                        request, address = server.recvfrom(4096)
                    response = request[:2] + struct.pack("!HHHHH", 0x8180, 1, answer_count,
                                                        authority_count, additional_count)
                    response += request[12:] + records
                    if transport == "tcp":
                        connection.sendall(struct.pack("!H", len(response)) + response)
                    else:
                        server.sendto(response, address)
                finally:
                    if connection is not None:
                        connection.close()
            except BaseException as error:
                errors.append(error)

        thread = threading.Thread(target=respond, daemon=True)
        thread.start()
        try:
            result = subprocess.run([str(self.binary), "127.0.0.1", str(port), transport,
                                     kind, "client.test", expected], capture_output=True,
                                    text=True, timeout=5)
            thread.join(timeout=4)
            self.assertFalse(thread.is_alive(), "local DNS responder did not finish")
            if errors:
                raise errors[0]
            if accepted:
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("PASS: DNS", result.stdout)
            else:
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("DNS assertion failed:", result.stderr)
                self.assertNotIn("PASS: DNS", result.stdout)
        finally:
            server.close()
            thread.join(timeout=4)

    def test_complete_and_truncated_declared_answers(self):
        """Check complete and truncated answer sections over UDP and TCP."""
        for transport in ("udp", "tcp"):
            for kind in ("A", "AAAA", "PTR"):
                for form in ("single", "complete", "missing", "short-header", "short-data"):
                    with self.subTest(transport=transport, kind=kind, form=form):
                        self.exercise(transport, kind, form)

    def test_declared_authority_and_additional_records(self):
        """Check declared authority and additional sections, including truncation."""
        for transport in ("udp", "tcp"):
            for kind in ("A", "AAAA", "PTR"):
                for form in ("complete-authority", "missing-authority", "short-authority-header",
                             "short-authority-data", "complete-additional", "missing-additional",
                             "short-additional-header", "short-additional-data", "complete-all-sections",
                             "matching-authority-only", "matching-additional-only"):
                    with self.subTest(transport=transport, kind=kind, form=form):
                        self.exercise(transport, kind, form)


    def test_compression_pointers_reference_prior_labels(self):
        """Check backward, forward, self, and chained DNS compression pointers."""
        for transport in ("udp", "tcp"):
            for form in ("backward-pointer", "self-pointer", "forward-pointer", "backward-chain",
                         "forward-chain", "chain-forward", "chain-self"):
                with self.subTest(transport=transport, form=form):
                    self.exercise(transport, "PTR", form)


if __name__ == "__main__":
    unittest.main(verbosity=2)
