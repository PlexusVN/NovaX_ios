import Foundation

@main
@MainActor
struct ProtectedDownloadSelfCheck {
    static var checks = 0
    static let artifactID = "10000000-0000-4000-8000-000000000001"
    static let grantID = "20000000-0000-4000-8000-000000000001"
    static let variant = "bundle:com.garena.ffvn"
    static let plaintext = Data("actual download orchestration fixture".utf8)
    static let ciphertext = Data([1, 2, 3, 4, 5])

    static func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { throw DownloadCheckFailure.failed(label) }
        checks += 1
    }
    static func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    static func hash(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }
    static func manifest() -> [String: Any] {
        ["protocol": "astra-artifact-v1", "type": "manifest", "algorithm": "RS256",
         "keyId": "public-test-only", "signature": "fixture-signature-not-used-by-boundary-double",
         "body": ["artifactId": artifactID, "releaseId": artifactID, "releaseVersion": 1,
            "variant": variant, "kind": "package", "fileName": "protected.3105",
            "plaintextSHA256": hash(plaintext), "plaintextSize": plaintext.count,
            "ciphertextSHA256": hash(ciphertext), "ciphertextSize": plaintext.count,
            "contentEncryption": ["algorithm": "A256GCM", "nonce": "fixture", "tag": "fixture"]]]
    }
    static func descriptor(_ signed: [String: Any]) throws -> ProtectedArtifactDescriptor {
        ProtectedArtifactDescriptor(artifactID: artifactID, fileHash: hash(plaintext), fileSize: plaintext.count,
            version: 1, manifestDigest: hash(try ProtectedArtifactDecoder.canonicalData(signed)),
            variant: variant, kind: "package", fileName: nil)
    }
    static func copy(_ old: ProtectedArtifactDescriptor, artifactID: String? = nil,
                     fileHash: String? = nil, fileSize: Int? = nil, version: Int64? = nil,
                     manifestDigest: String? = nil, variant: String? = nil,
                     kind: String? = nil, fileName: String? = nil) -> ProtectedArtifactDescriptor {
        ProtectedArtifactDescriptor(artifactID: artifactID ?? old.artifactID,
            fileHash: fileHash ?? old.fileHash, fileSize: fileSize ?? old.fileSize,
            version: version ?? old.version, manifestDigest: manifestDigest ?? old.manifestDigest,
            variant: variant ?? old.variant, kind: kind ?? old.kind, fileName: fileName)
    }
    static func resetBoundary() {
        ProtectedArtifactDecoder.plaintext = plaintext
        ProtectedArtifactDecoder.expectedCiphertext = ciphertext
        ProtectedArtifactDecoder.decryptCalls = 0
        ProtectedArtifactDecoder.afterDecrypt = nil
        AppIntegrityRuntime.shared.checks = 0
        AppIntegrityRuntime.shared.hook = nil
    }
    static func makeHarness(_ signed: [String: Any], grantResponse: [String: Any]? = nil,
                            contentResponse: [String: Any]? = nil,
                            beforeGrant: ((ProtectedDownloadHarness) -> Void)? = nil,
                            beforeContent: ((ProtectedDownloadHarness) -> Void)? = nil) -> ProtectedDownloadHarness {
        let validGrant: [String: Any] = ["success": true, "grant_id": grantID, "artifact_id": artifactID]
        let validContent: [String: Any] = ["success": true, "signed_manifest": signed,
            "signed_grant": ["body": ["grantId": grantID]], "ciphertext_b64": ciphertext.base64EncodedString()]
        var harness: ProtectedDownloadHarness!
        harness = ProtectedDownloadHarness { route, body in
            if route.hasSuffix("/grants") {
                beforeGrant?(harness)
                try check(body.isEmpty, "grant request contains unexpected fields")
                return (try json(grantResponse ?? validGrant), "grant-request-nonce")
            }
            try check(route.hasSuffix("/content"), "unexpected protected route")
            try check(body["grant_id"] as? String == grantID && body.count == 1,
                      "content request did not use the one issued grant")
            beforeContent?(harness)
            return (try json(contentResponse ?? validContent), ProtectedArtifactDecoder.expectedNonce)
        }
        return harness
    }
    static func rejects(_ name: String, code: String? = nil,
                        _ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch {
            if let code {
                try check(ProtectedDownloadError.diagnosticCode(for: error) == code,
                          name + " returned unexpected diagnostic: " + String(describing: error))
            } else {
                checks += 1
            }
            return
        }
        throw DownloadCheckFailure.failed("accepted: " + name)
    }
    static func main() async throws {
        resetBoundary()
        let signed = manifest(), expected = try descriptor(signed)
        let body = try ProtectedArtifactDecoder.shared.verifyManifest(json(signed))
        let harness = makeHarness(signed)
        let result = try await harness.run(expected)
        try check(result.data == plaintext && result.fileName == "protected.3105", "successful payload differs")
        try check(harness.requests.count == 2, "success replayed transport requests")
        try check(ProtectedArtifactDecoder.decryptCalls == 1, "success did not decrypt once")

        let changes: [(ProtectedArtifactDescriptor, String)] = [
            (copy(expected, artifactID: "10000000-0000-4000-8000-000000000002"), "DL30"),
            (copy(expected, manifestDigest: String(repeating: "0", count: 64)), "DL31"),
            (copy(expected, kind: "mod"), "DL32"),
            (copy(expected, variant: "ffth"), "DL33"),
            (copy(expected, version: 2), "DL34"),
            (copy(expected, fileHash: String(repeating: "0", count: 64)), "DL35"),
            (copy(expected, fileSize: plaintext.count + 1), "DL36"),
            (copy(expected, fileName: "different.3105"), "DL37"),
        ]
        for (invalid, code) in changes {
            try await rejects("catalog/manifest mismatch " + code, code: code) {
                try harness.validate(invalid, manifest: body, signedDocument: signed)
            }
        }
        for code in ["DL02", "DL03", "DL30", "DL37"] {
            let error = ProtectedDownloadError.invalidResponse(at: code)
            try check(ProtectedDownloadError.diagnosticCode(for: error) == code, "valid diagnostic code lost")
            try check(error.localizedDescription.contains(code), "diagnostic missing from user-facing detail")
        }
        for value in ["", "DL1", "DL001", "dl01", "DL01\n", "DL01/file", "key=private"] {
            try check(ProtectedDownloadError.diagnosticCode(for: ProtectedDownloadError.invalidResponse(at: value)) == nil,
                      "untrusted detail became a diagnostic")
        }

        resetBoundary()
        let unsuccessful = makeHarness(signed, grantResponse: ["success": false])
        try await rejects("unsuccessful grant payload", code: "DL03") { _ = try await unsuccessful.run(expected) }
        try check(unsuccessful.requests.count == 1 && ProtectedArtifactDecoder.decryptCalls == 0,
                  "invalid grant advanced or retried")
        let notDictionary = ProtectedDownloadHarness { _, _ in (try json([1, 2, 3]), "nonce") }
        try await rejects("non-dictionary grant payload", code: "DL02") { _ = try await notDictionary.run(expected) }

        let malformedGrants: [([String: Any], String)] = [
            (["success": true, "artifact_id": artifactID], "DL15"),
            (["success": true, "grant_id": "invalid", "artifact_id": artifactID], "DL15"),
            (["success": true, "grant_id": grantID, "artifact_id": "10000000-0000-4000-8000-000000000002"], "DL16")]
        for (changed, code) in malformedGrants {
            resetBoundary()
            let failed = makeHarness(signed, grantResponse: changed)
            try await rejects("malformed grant", code: code) { _ = try await failed.run(expected) }
            try check(failed.requests.count == 1 && ProtectedArtifactDecoder.decryptCalls == 0,
                      "malformed grant was retried or reached content")
        }
        let malformedContent: [([String: Any], String)] = [
            (["success": true], "DL18"),
            (["success": true, "signed_manifest": signed, "signed_grant": ["body": ["grantId": grantID]], "ciphertext_b64": "not base64!"], "DL19")]
        for (changed, code) in malformedContent {
            resetBoundary()
            let failed = makeHarness(signed, contentResponse: changed)
            try await rejects("malformed content", code: code) { _ = try await failed.run(expected) }
            try check(failed.requests.count == 2 && ProtectedArtifactDecoder.decryptCalls == 0,
                      "malformed content was replayed or decrypted")
        }
        resetBoundary()
        let absentIdentity = makeHarness(signed, beforeContent: { $0.identity = nil })
        do {
            _ = try await absentIdentity.run(expected)
            throw DownloadCheckFailure.failed("missing identity accepted")
        } catch DeviceIdentityError.identityMissing { checks += 1 }
        try check(ProtectedArtifactDecoder.decryptCalls == 0, "missing identity reached decrypt")
        resetBoundary()
        let absentEnrollment = makeHarness(signed, beforeContent: { $0.identity?.deviceID = nil })
        do {
            _ = try await absentEnrollment.run(expected)
            throw DownloadCheckFailure.failed("missing enrollment accepted")
        } catch DeviceIdentityError.identityMissing { checks += 1 }
        try check(ProtectedArtifactDecoder.decryptCalls == 0, "missing enrollment reached decrypt")
        resetBoundary()
        let malformedAgreement = makeHarness(signed, beforeContent: { $0.identity?.agreementBase64 = "invalid key" })
        do {
            _ = try await malformedAgreement.run(expected)
            throw DownloadCheckFailure.failed("invalid identity accepted")
        } catch DeviceIdentityError.invalidIdentity { checks += 1 }

        resetBoundary()
        let wrongSession = makeHarness(signed, beforeContent: { $0.sessionID = "50000000-0000-4000-8000-000000000001" })
        try await rejects("session changed during transfer") { _ = try await wrongSession.run(expected) }
        try check(wrongSession.requests.count == 2, "session failure replayed consumed grant")
        resetBoundary()
        let wrongPlaintext = makeHarness(signed)
        ProtectedArtifactDecoder.plaintext = Data("damaged plaintext".utf8)
        try await rejects("plaintext differs from catalog", code: "DL20") { _ = try await wrongPlaintext.run(expected) }
        try check(ProtectedArtifactDecoder.decryptCalls == 1 && wrongPlaintext.requests.count == 2,
                  "plaintext failure replayed grant/content")
        resetBoundary()
        let expiredLicense = makeHarness(signed)
        ProtectedArtifactDecoder.afterDecrypt = { expiredLicense.validLicense = false }
        try await rejects("license changed after decrypt") { _ = try await expiredLicense.run(expected) }
        resetBoundary()
        let changedBinding = makeHarness(signed)
        ProtectedArtifactDecoder.afterDecrypt = { changedBinding.licenseDigest = "changed-license" }
        try await rejects("license binding changed after decrypt") { _ = try await changedBinding.run(expected) }

        resetBoundary()
        var wrongSizeManifest = signed
        var wrongSizeBody = signed["body"] as! [String: Any]
        wrongSizeBody["plaintextSize"] = plaintext.count + 1
        wrongSizeManifest["body"] = wrongSizeBody
        let wrongSizeDescriptor = copy(expected, fileSize: plaintext.count + 1,
            manifestDigest: hash(try ProtectedArtifactDecoder.canonicalData(wrongSizeManifest)))
        let wrongSize = makeHarness(wrongSizeManifest)
        try await rejects("decrypted size differs from catalog", code: "DL21") {
            _ = try await wrongSize.run(wrongSizeDescriptor)
        }
        try check(wrongSize.requests.count == 2 && ProtectedArtifactDecoder.decryptCalls == 1,
                  "size mismatch retried a consumed grant")

        resetBoundary()
        let clocked = makeHarness(signed, beforeContent: { service in
            let receipt = ProcessInfo.processInfo.systemUptime
            service.lastResponseTime = ProtectedResponseTime(serverDate: Date(timeIntervalSince1970: 1000),
                requestStartedAt: receipt - 0.5, receivedAt: receipt)
        })
        _ = try await clocked.run(expected)
        let verificationTime = ProtectedArtifactDecoder.verificationDate?.timeIntervalSince1970 ?? 0
        try check(verificationTime >= 1001.5 && verificationTime < 1010,
                  "download did not forward the admitted response's conservative monotonic time")
        try check(clocked.requests.count == 2, "clock handling replayed a consumed grant")

        print("[PASS] \(checks) production protected download transport, descriptor, identity and diagnostic checks")
    }
}
