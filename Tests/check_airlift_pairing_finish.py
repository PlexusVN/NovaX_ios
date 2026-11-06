#!/usr/bin/env python3
"""Regression contract for successful on-device AirLift pairing completion."""

from pathlib import Path
import sys


def extract_function(source: str, signature: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise AssertionError(f"missing function: {signature}")
    brace = source.find("{", start)
    if brace < 0:
        raise AssertionError(f"missing function body: {signature}")

    depth = 0
    for index in range(brace, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    raise AssertionError(f"unterminated function body: {signature}")


def require(condition: bool, label: str) -> None:
    if not condition:
        raise AssertionError(label)
    print(f"[PASS] airlift pairing: {label}")


def main() -> int:
    source_path = Path(sys.argv[1] if len(sys.argv) > 1 else "ThreeOneOSFive/helpers/AirLiftPairingManager.swift")
    source = source_path.read_text(encoding="utf-8")
    body = extract_function(source, "private func finishPairing(")
    start_body = extract_function(source, "func startBonjourPairingBroadcast()")

    validation = "Self.isSupportedPairingRecord(record)"
    canonical_write = "try data.write(to: pairingFileURL"
    backup = "backupPairingDataToKeychain(data)"
    verified = "status = .verified"

    require(validation in body, "completion validates the returned plist directly")
    require("preparePairingStagingFile().path" in start_body,
            "native pairing writes to staging instead of the canonical record")
    require("defer { discardPairingStagingFile() }" in body,
            "staging output is removed on every completion path")
    require("checkPairingStatus()" not in body, "completion does not reuse transient UI status")
    require("guard status.isPaired" not in body, "waitingSettings cannot reject a valid record")
    require(canonical_write in body and "try? data.write(to: pairingFileURL" not in body,
            "canonical persistence errors are not discarded")
    require(body.index(validation) < body.index(canonical_write) < body.index(backup),
            "validation and canonical persistence happen before Keychain backup")
    require("pairingFilePath = pairingFileURL.path" in body and verified in body,
            "successful completion publishes the canonical path and verified state")
    require(body.index(backup) < body.index(verified),
            "verified state is published only after persistence and backup attempt")
    require("status = .invalid" in body and "PairingError.invalidRecord" in body,
            "non-empty malformed records fail closed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"[FAIL] airlift pairing: {error}", file=sys.stderr)
        raise SystemExit(1)
