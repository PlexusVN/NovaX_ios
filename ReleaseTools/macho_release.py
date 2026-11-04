import hashlib
import json
import struct
import sys
from pathlib import Path


def inspect_macho(data):
    if len(data) < 32 or struct.unpack_from('<I', data)[0] != 0xfeedfacf:
        raise ValueError('macho64_required')
    cpu, _, _, count, commands, _, _ = struct.unpack_from('<7I', data, 4)
    if cpu != 0x100000c or count > 4096 or 32 + commands > len(data):
        raise ValueError('arm64_executable_required')
    sections, dependencies, position = [], [], 32
    for _ in range(count):
        if position + 8 > 32 + commands:
            raise ValueError('load_command_invalid')
        command, size = struct.unpack_from('<II', data, position)
        if size < 8 or position + size > 32 + commands:
            raise ValueError('load_command_invalid')
        if command == 0x19:
            if size < 72:
                raise ValueError('segment_invalid')
            segment = data[position + 8:position + 24].split(b'\0')[0]
            section_count = struct.unpack_from('<I', data, position + 64)[0]
            if section_count > 256 or 72 + section_count * 80 > size:
                raise ValueError('section_table_invalid')
            for index in range(section_count):
                at = position + 72 + index * 80
                name = data[at:at + 16].split(b'\0')[0].decode('ascii')
                length = struct.unpack_from('<Q', data, at + 40)[0]
                offset = struct.unpack_from('<I', data, at + 48)[0]
                if segment == b'__TEXT' and length:
                    if length > 128 * 1024 * 1024 or offset + length > len(data):
                        raise ValueError('section_bounds_invalid')
                    sections.append({
                        'name': name,
                        'size': length,
                        'sha256': hashlib.sha256(data[offset:offset + length]).hexdigest(),
                    })
        if command in (0xc, 0x80000018, 0x8000001f, 0x80000023):
            offset = struct.unpack_from('<I', data, position + 8)[0]
            if offset < 24 or offset >= size:
                raise ValueError('dependency_invalid')
            dependencies.append(data[position + offset:position + size]
                                .split(b'\0')[0].decode('ascii'))
        position += size
    if position != 32 + commands or not any(item['name'] == '__text' for item in sections):
        raise ValueError('executable_sections_missing')
    if len({item['name'] for item in sections}) != len(sections):
        raise ValueError('duplicate_section_name')
    return sorted(sections, key=lambda item: item['name']), sorted(dependencies)


if __name__ == '__main__':
    found_sections, found_dependencies = inspect_macho(Path(sys.argv[1]).read_bytes())
    print(json.dumps({'sections': found_sections, 'dependencies': found_dependencies}, sort_keys=True))
