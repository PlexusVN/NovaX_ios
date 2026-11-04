#!/usr/bin/env python3
"""Embed/verify SHA-256 of a thin arm64 Mach-O __TEXT,__text section."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import struct
import sys

MARKER = b"ASTRA_HASH_MARKER:"
EMPTY = b"0" * 64
LC_SEGMENT_64 = 0x19
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C


def _u32(blob: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(blob):
        raise ValueError("mach_o_truncated")
    return struct.unpack_from("<I", blob, offset)[0]


def _u64(blob: bytes, offset: int) -> int:
    if offset < 0 or offset + 8 > len(blob):
        raise ValueError("mach_o_truncated")
    return struct.unpack_from("<Q", blob, offset)[0]


def _name(blob: bytes, offset: int) -> bytes:
    return blob[offset:offset + 16].split(b"\0", 1)[0]


def text_range(blob: bytes) -> tuple[int, int]:
    if len(blob) < 32 or _u32(blob, 0) != MH_MAGIC_64 or _u32(blob, 4) != CPU_TYPE_ARM64:
        raise ValueError("thin_arm64_mach_o_required")
    command_count, command_bytes = _u32(blob, 16), _u32(blob, 20)
    if not 0 < command_count <= 16384 or 32 + command_bytes > len(blob):
        raise ValueError("mach_o_load_commands_invalid")
    cursor = 32
    for _ in range(command_count):
        command, size = _u32(blob, cursor), _u32(blob, cursor + 4)
        if size < 8 or cursor + size > len(blob):
            raise ValueError("mach_o_load_command_invalid")
        if command == LC_SEGMENT_64 and size >= 72 and _name(blob, cursor + 8) == b"__TEXT":
            section_count = _u32(blob, cursor + 64)
            if section_count > 4096 or 72 + section_count * 80 > size:
                raise ValueError("mach_o_sections_invalid")
            section = cursor + 72
            for _ in range(section_count):
                if _name(blob, section) == b"__text" and _name(blob, section + 16) == b"__TEXT":
                    length, offset = _u64(blob, section + 40), _u32(blob, section + 48)
                    if not length or offset + length > len(blob):
                        raise ValueError("mach_o_text_range_invalid")
                    return offset, length
                section += 80
        cursor += size
    raise ValueError("mach_o_text_section_missing")


def expected_digest(blob: bytes) -> bytes:
    matches = list(re.finditer(re.escape(MARKER) + rb"([0-9a-f]{64})", blob))
    if len(matches) != 1:
        raise ValueError(f"integrity_anchor_count_{len(matches)}")
    return matches[0].group(1)


def embed(path: pathlib.Path) -> str:
    blob = bytearray(path.read_bytes())
    start, length = text_range(blob)
    digest = hashlib.sha256(blob[start:start + length]).hexdigest().encode("ascii")
    anchor = blob.find(MARKER)
    if anchor < 0 or blob.find(MARKER, anchor + 1) >= 0:
        raise ValueError("integrity_anchor_missing_or_duplicate")
    digest_offset = anchor + len(MARKER)
    current = bytes(blob[digest_offset:digest_offset + 64])
    if not re.fullmatch(rb"[0-9a-f]{64}", current):
        raise ValueError("integrity_anchor_payload_invalid")
    if start <= digest_offset < start + length:
        raise ValueError("integrity_anchor_inside_measured_text")
    blob[digest_offset:digest_offset + 64] = digest
    path.write_bytes(blob)
    return digest.decode("ascii")


def verify(path: pathlib.Path) -> str:
    blob = path.read_bytes()
    start, length = text_range(blob)
    embedded = expected_digest(blob)
    actual = hashlib.sha256(blob[start:start + length]).hexdigest().encode("ascii")
    if embedded == EMPTY or embedded != actual:
        raise ValueError("integrity_hash_mismatch")
    return actual.decode("ascii")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=pathlib.Path)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    try:
        digest = verify(args.executable) if args.verify else embed(args.executable)
    except (OSError, ValueError) as error:
        print(f"[integrity] {error}", file=sys.stderr)
        return 1
    print(f"[integrity] __TEXT,__text sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
