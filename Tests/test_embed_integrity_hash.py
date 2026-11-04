import importlib.util
import pathlib
import struct
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "tools" / "embed_integrity_hash.py"
SPEC = importlib.util.spec_from_file_location("embed_integrity_hash", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def fixture() -> bytes:
    text = b"\x01\x02\x03\x04astra-text-section"
    text_offset = 32 + 72 + 80
    command_size = 72 + 80
    header = struct.pack("<IiiIIIII", MODULE.MH_MAGIC_64, 0x0100000C, 0, 2, 1, command_size, 0, 0)
    segment = struct.pack(
        "<II16sQQQQiiII", MODULE.LC_SEGMENT_64, command_size, b"__TEXT\0" + b"\0" * 9,
        0, text_offset + len(text), 0, text_offset + len(text), 5, 5, 1, 0
    )
    section = struct.pack(
        "<16s16sQQIIIIIIII", b"__text\0" + b"\0" * 9, b"__TEXT\0" + b"\0" * 9,
        text_offset, len(text), text_offset, 2, 0, 0, 0, 0, 0, 0
    )
    return header + segment + section + text + MODULE.MARKER + MODULE.EMPTY + b"\0"


class IntegrityHashTests(unittest.TestCase):
    def test_embed_and_verify(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "Astra"
            path.write_bytes(fixture())
            digest = MODULE.embed(path)
            self.assertEqual(MODULE.verify(path), digest)
            self.assertNotEqual(MODULE.expected_digest(path.read_bytes()), MODULE.EMPTY)

    def test_text_tamper_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "Astra"
            path.write_bytes(fixture())
            MODULE.embed(path)
            blob = bytearray(path.read_bytes())
            start, _ = MODULE.text_range(blob)
            blob[start] ^= 0xFF
            path.write_bytes(blob)
            with self.assertRaisesRegex(ValueError, "integrity_hash_mismatch"):
                MODULE.verify(path)

    def test_resigning_area_does_not_change_text_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "Astra"
            path.write_bytes(fixture())
            digest = MODULE.embed(path)
            with path.open("ab") as handle:
                handle.write(b"replacement-code-signature")
            self.assertEqual(MODULE.verify(path), digest)


if __name__ == "__main__":
    unittest.main()
