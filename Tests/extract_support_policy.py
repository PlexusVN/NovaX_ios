"""Compile the actual pure Swift OS routing policy, without device-only bridges."""
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding='utf-8')
begin = source.index('enum ExploitSupportPolicy {')
end = source.index('// MARK: - Sandbox & Filesystem Access Helpers', begin)
Path(sys.argv[2]).write_text('import Foundation\n' + source[begin:end], encoding='utf-8')
