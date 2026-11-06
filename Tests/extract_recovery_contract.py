"""Extract the actual production declarations for offline macOS tests.
Usage: python3 extract_recovery_contract.py CLIENT_DIRECTORY OUTPUT.swift
The output is disposable; production source is never changed.
"""
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve()
pds=(root/'ProtectedDownloadService.swift').read_text(encoding='utf-8')
identity=(root/'DeviceIdentityService.swift').read_text(encoding='utf-8')
errors=pds[pds.index('enum ProtectedDownloadError:'):pds.index('@MainActor')]
identity_errors=identity[identity.index('enum DeviceIdentityError:'):identity.index('struct DeviceIdentityStorage')]
start='// BEGIN RECOVERY CHALLENGE CONTRACT'
end='// END RECOVERY CHALLENGE CONTRACT'
policy=pds[pds.index(start):pds.index(end)]
Path(sys.argv[2]).write_text('import Foundation\nimport Security\n'+errors+'\n'+identity_errors+'\n'+policy,encoding='utf-8')
