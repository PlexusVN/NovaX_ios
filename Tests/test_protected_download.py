"""Run actual download orchestration; crypto and network boundaries are isolated."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest
from extract_protected_download import source

ROOT = Path(__file__).resolve().parents[1]


class ProtectedDownloadChecks(unittest.TestCase):
    def test_actual_download_response_guards(self):
        compiler = shutil.which('swiftc')
        distro = os.environ.get('ASTRA_SWIFT_WSL_DISTRIBUTION')
        if compiler:
            command, translate = [compiler], str
            execute = lambda binary: [str(binary)]
        elif os.name == 'nt' and distro:
            compiler = subprocess.check_output(['wsl', '-d', distro, '--', 'bash', '-lc',
                'command -v swiftc'], text=True).strip()
            command = ['wsl', '-d', distro, '--', compiler]
            def translate(value):
                value = str(Path(value).resolve()).replace('\\', '/')
                return '/mnt/' + value[0].lower() + value[2:]
            execute = lambda binary: ['wsl', '-d', distro, '--', translate(binary)]
        else:
            self.skipTest('requires Swift; ASTRA_SWIFT_WSL_DISTRIBUTION enables Windows checks')
        with tempfile.TemporaryDirectory() as directory:
            actual = Path(directory)/'ProtectedDownload.swift'
            actual.write_text(source(), encoding='utf-8')
            binary = Path(directory)/'protected-download-check'
            subprocess.run(command+['-swift-version', '5',
                translate(ROOT/'ThreeOneOSFive/helpers/AppSecurityConfiguration.swift'),
                translate(actual), translate(ROOT/'Tests/ProtectedDownloadSelfCheck.swift'),
                '-o', translate(binary)], check=True)
            subprocess.run(execute(binary), check=True)


if __name__ == '__main__':
    unittest.main()
