"""Run actual AirLift entry/continuation bodies with isolated boundary spies.

No iOS/native sockets are opened. The production methods and FFI lifetime types
are extracted unchanged; only UIKit, the native work and persistence boundaries
are replaced. macOS Swift or the configured WSL compiler can execute this check.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from check_airlift_pairing_finish import extract_function

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / 'ThreeOneOSFive/helpers'


class AirLiftIsolationChecks(unittest.TestCase):
    def test_actual_airlift_entries_and_native_lifetime(self):
        native = shutil.which('swiftc')
        distro = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
        if native:
            compiler, translate = [native], str
            execute = lambda binary: [str(binary)]
        elif os.name == 'nt' and distro:
            native = subprocess.check_output(
                ['wsl', '-d', distro, '--', 'bash', '-lc', 'command -v swiftc'], text=True).strip()
            if not native:
                self.skipTest('Swift unavailable in configured WSL distribution')
            compiler = ['wsl', '-d', distro, '--', native]
            def translate(value):
                value = str(Path(value).resolve()).replace('\\', '/')
                return '/mnt/' + value[0].lower() + value[2:]
            execute = lambda binary: ['wsl', '-d', distro, '--', translate(binary)]
        else:
            self.skipTest('requires Swift; ASTRA_SWIFT_WSL_DISTRIBUTION enables Windows checks')

        client = (HELPERS / 'AirTrafficProtocolClient.swift').read_text(encoding='utf-8')
        pairing = (HELPERS / 'AirLiftPairingManager.swift').read_text(encoding='utf-8')
        tunnel = (HELPERS / 'AirLiftTunnelManager.swift').read_text(encoding='utf-8')
        source = (ROOT / 'Tests/AirLiftIsolationSelfCheck.swift').read_text(encoding='utf-8')
        pieces = {
            '// ACTUAL_FFI_TYPES': client[client.index('private final class FFIContinuationGate'):client.index('private let novaAirLiftLogCallback')],
            '// ACTUAL_RUN_BLOCKING': extract_function(client, 'private func runBlocking<T: Sendable>('),
            '// ACTUAL_PROVIDER_GUARD': extract_function(client, 'private func requireSelectedProvider()'),
            '// ACTUAL_HEALTH': extract_function(client, 'func checkRealAirLiftHealth()'),
            '// ACTUAL_PAIR_VERIFY': extract_function(pairing, 'func verifyPairingWithDevice(silent:'),
            '// ACTUAL_PAIR_CANCEL': extract_function(pairing, 'func cancelPendingChecks()'),
            '// ACTUAL_PAIR_IMPORT': extract_function(pairing, 'func importPairingFile('),
            '// ACTUAL_PAIR_PIN': extract_function(pairing, 'fileprivate func showPIN('),
            '// ACTUAL_TUNNEL_PROBE': extract_function(tunnel, 'func verifyLoopbackService()'),
            '// ACTUAL_TUNNEL_CANCEL': extract_function(tunnel, 'func cancelPendingChecks()'),
        }
        for marker, body in pieces.items():
            self.assertIn(marker, source)
            source = source.replace(marker, body)
        with tempfile.TemporaryDirectory() as directory:
            generated = Path(directory) / 'ActualAirLiftIsolation.swift'
            generated.write_text(source, encoding='utf-8')
            binary = Path(directory) / 'airlift-isolation'
            subprocess.run(compiler + ['-swift-version', '5', '-parse-as-library', translate(generated),
                '-o', translate(binary)], check=True)
            subprocess.run(execute(binary), check=True)


if __name__ == '__main__':
    unittest.main()
