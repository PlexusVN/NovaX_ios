// macOS CLI self-check. The fixture's keys are intentionally public test data.
// Compile with the production verifier and decoder; this stub makes accidental
// production-key access fail, so every test must inject its fixture identity.
import Foundation
import CryptoKit
import Security

enum SelfCheckFailure: Error { case failed(String) }

// Only the live-debugger observation is needed by the release verifier. The
// offline harness never inspects or changes the host's debugger/code-sign state.
enum AntiTamper {
    static let isDebuggerAttached = false
}

// The macOS harness exercises endpoint policy only, never a network session.
// The iOS app links the real UIKit-based pinning delegate from SecurityUtils.
final class CertPinningDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = CertPinningDelegate()
}

final class NetworkSecurityGuard {
    static let shared = NetworkSecurityGuard()
    func probeConnection() async -> NetworkProbeResult { .unavailable("No network in offline self-check") }
}

private actor ControlledNetworkProbe {
    private(set) var calls = 0
    private var waiting: [CheckedContinuation<NetworkProbeResult, Never>] = []
    func run() async -> NetworkProbeResult {
        calls += 1
        return await withCheckedContinuation { waiting.append($0) }
    }
    func finish(_ result: NetworkProbeResult) {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume(returning: result)
    }
}

final class DeviceIdentityService {
    static let shared = DeviceIdentityService()
    func persistedEnrollmentID() throws -> String? { throw SelfCheckFailure.failed("production identity accessed") }
    func getOrCreateAgreementKey() throws -> (publicKeyX963Base64: String, assurance: String) {
        throw SelfCheckFailure.failed("production identity accessed")
    }
    func agreementSharedSecret(peerPublicKeyX963: Data) throws -> SharedSecret {
        throw SelfCheckFailure.failed("production identity accessed")
    }
}

@main
struct ProtectedArtifactSelfCheck {
    static var checks = 0

    static func require(_ condition: Bool, _ name: String) throws {
        guard condition else { throw SelfCheckFailure.failed(name) }
        checks += 1
    }
    static func rejects(_ name: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch { checks += 1; return }
        throw SelfCheckFailure.failed("accepted: " + name)
    }
    static func json(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    static func bytes(_ hex: String) throws -> Data {
        guard hex.count % 2 == 0 else { throw SelfCheckFailure.failed("bad fixture hex") }
        var result = Data()
        var cursor = hex.startIndex
        while cursor != hex.endIndex {
            let next = hex.index(cursor, offsetBy: 2)
            guard let byte = UInt8(hex[cursor..<next], radix: 16) else { throw SelfCheckFailure.failed("bad fixture hex") }
            result.append(byte); cursor = next
        }
        return result
    }
    @MainActor
    static func main() async throws {
        let path = CommandLine.arguments.dropFirst().first ?? "Tests/Fixtures/artifact_crypto_v1.json"
        let fixtureData = try Data(contentsOf: URL(fileURLWithPath: path))
        let fixture = try JSONSerialization.jsonObject(with: fixtureData) as! [String: Any]
        let manifestObject = fixture["signedManifest"] as! [String: Any]
        let grantObject = fixture["signedGrant"] as! [String: Any]
        let grantBody = grantObject["body"] as! [String: Any]
        let context = fixture["verificationContext"] as! [String: Any]
        let expected = fixture["expected"] as! [String: Any]
        let publicDER = Data(base64Encoded: fixture["signerPublicKeyPKCS1Base64"] as! String)!
        let verifier = ServerSignatureVerifier(trustedPublicKeys: ["fixture-rsa-2048": publicDER])
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: bytes(fixture["recipientPrivateKeyHex"] as! String))
        let recipientID = context["recipientId"] as! String
        let sessionID = context["sessionId"] as! String
        let nonce = context["requestNonce"] as! String
        let date = Date(timeIntervalSince1970: (context["now"] as! NSNumber).doubleValue)
        let decoder = ProtectedArtifactDecoder(verifier: verifier,
            recipientIdentity: { (recipientID, privateKey.publicKey.x963Representation) },
            sharedSecret: { try privateKey.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: $0)) })
        let manifest = try json(manifestObject)
        let grant = try json(grantObject)
        let ciphertext = Data(base64Encoded: fixture["ciphertextBase64"] as! String)!
        let artifactID = (manifestObject["body"] as! [String: Any])["artifactId"] as! String
        let grantID = grantBody["grantId"] as! String
        func decrypt(_ input: Data? = nil, _ manifestData: Data? = nil,
                     _ grantData: Data? = nil, session: String? = nil,
                     requestNonce: String? = nil, at: Date? = nil,
                     expectedGrant: String? = nil) throws -> Data {
            try decoder.decrypt(signedManifest: manifestData ?? manifest, signedGrant: grantData ?? grant, ciphertext: input ?? ciphertext,
                recipientID: recipientID, sessionID: session ?? sessionID,
                requestNonce: requestNonce ?? nonce, expectedArtifactID: artifactID,
                expectedGrantID: expectedGrant ?? grantID, now: at ?? date)
        }
        try require(try decrypt() == bytes(fixture["expectedPlaintextHex"] as! String), "golden ECDH/HKDF/GCM plaintext")
        var unsigned = manifestObject; unsigned.removeValue(forKey: "signature")
        try require(String(data: ProtectedArtifactDecoder.canonicalData(unsigned), encoding: .utf8) == expected["manifestSignatureInputUTF8"] as? String,
                    "manifest canonical signature bytes")
        try require(String(data: ProtectedArtifactDecoder.canonicalData(manifestObject), encoding: .utf8) == expected["manifestCanonicalUTF8"] as? String,
                    "manifest canonical digest bytes")
        var unsignedGrant = grantObject; unsignedGrant.removeValue(forKey: "signature")
        try require(String(data: ProtectedArtifactDecoder.canonicalData(unsignedGrant), encoding: .utf8) == expected["grantSignatureInputUTF8"] as? String,
                    "grant canonical signature bytes")
        var damaged = ciphertext; damaged[0] ^= 1
        try rejects("ciphertext tamper") { _ = try decrypt(damaged) }
        try rejects("different session") { _ = try decrypt(session: "00000000-0000-4000-8000-000000000099") }
        try rejects("different request nonce") { _ = try decrypt(requestNonce: String(repeating: "0", count: 32)) }
        try rejects("different grant") { _ = try decrypt(expectedGrant: "00000000-0000-4000-8000-000000000099") }
        try rejects("expired grant") { _ = try decrypt(at: Date(timeIntervalSince1970: (grantBody["expiresAt"] as! NSNumber).doubleValue)) }
        try require(try decrypt(at: Date(timeIntervalSince1970: (grantBody["issuedAt"] as! NSNumber).doubleValue - 10)) == bytes(fixture["expectedPlaintextHex"] as! String),
                    "small clock skew does not reject an authenticated grant")
        try rejects("future grant beyond bounded clock skew") { _ = try decrypt(at: Date(timeIntervalSince1970: (grantBody["issuedAt"] as! NSNumber).doubleValue - 31)) }
        var changedManifest = manifestObject
        var changedBody = changedManifest["body"] as! [String: Any]
        changedBody["plaintextSHA256"] = String(repeating: "0", count: 64)
        changedManifest["body"] = changedBody
        try rejects("manifest tamper") { _ = try decrypt(ciphertext, json(changedManifest)) }
        try rejects("production keyring rejects fixture signer") { _ = try ProtectedArtifactDecoder.shared.verifyManifest(manifest) }
        try rejects("Unicode canonical ambiguity") { _ = try ProtectedArtifactDecoder.canonicalData(["name": "\u{00e9}"]) }
        try rejects("fractional canonical number") { _ = try ProtectedArtifactDecoder.canonicalData(["size": 1.5]) }
        try rejects("unsafe integer canonical number") { _ = try ProtectedArtifactDecoder.canonicalData(["size": 9_007_199_254_740_992 as Int64]) }
        try require(String(data: ProtectedArtifactDecoder.canonicalData(["bool": true, "integer": 1]), encoding: .utf8) == "{\"bool\":true,\"integer\":1}",
                    "bool and integer canonical distinction")
        try checkResponseEnvelope()
        try checkEndpointPolicy()
        try checkRequestRegistry()
        try await checkNetworkGate()
        print("Astra security self-check: \(checks) checks passed")
    }

    static func checkResponseEnvelope() throws {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                        kSecAttrKeySizeInBits as String: 2048]
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicData = SecKeyCopyExternalRepresentation(publicKey, nil) else {
            throw SelfCheckFailure.failed("fixture RSA generation")
        }
        let verifier = ServerSignatureVerifier(trustedPublicKeys: ["test-only": publicData as Data])
        let payload = Data("{\"success\":true}".utf8)
        let nonce = String(repeating: "a", count: 32)
        let now = Date(timeIntervalSince1970: 1_730_000_000)
        var object: [String: Any] = ["protocol": 2, "kid": "test-only", "purpose": "test-response",
            "request_nonce": nonce, "issued_ms": 1_730_000_000_000 as Int64,
            "expires_ms": 1_730_000_060_000 as Int64,
            "payload_sha256": SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
            "payload_b64": payload.base64EncodedString(), "signature": ""]
        let unsigned = try JSONDecoder().decode(AstraServerEnvelope.self, from: json(object))
        guard let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256,
                Data(verifier.canonicalEnvelopeString(unsigned).utf8) as CFData, nil) else {
            throw SelfCheckFailure.failed("fixture RSA signature")
        }
        object["signature"] = (signature as Data).base64EncodedString()
        let valid = try JSONDecoder().decode(AstraServerEnvelope.self, from: json(object))
        try require(verifier.verifyEnvelope(envelope: valid, expectedNonce: nonce,
            expectedPurpose: "test-response", payloadData: payload, now: now), "valid response RSA signature")
        try require(!verifier.verifyEnvelope(envelope: valid, expectedNonce: "",
            expectedPurpose: "test-response", payloadData: payload, now: now), "empty nonce rejected")
        try require(!verifier.verifyEnvelope(envelope: valid, expectedNonce: nonce,
            expectedPurpose: "another-purpose", payloadData: payload, now: now), "wrong purpose rejected")
        try require(!verifier.verifyEnvelope(envelope: valid, expectedNonce: nonce,
            expectedPurpose: "test-response", payloadData: Data(), now: now), "wrong payload rejected")
        try require(!verifier.verifyEnvelope(envelope: valid, expectedNonce: nonce,
            expectedPurpose: "test-response", payloadData: payload, now: now.addingTimeInterval(60)), "response expiry rejected")
        object["signature"] = "invalid base64"
        let malformed = try JSONDecoder().decode(AstraServerEnvelope.self, from: json(object))
        try require(!verifier.verifyEnvelope(envelope: malformed, expectedNonce: nonce,
            expectedPurpose: "test-response", payloadData: payload, now: now), "malformed signature fails closed")
    }

    static func checkEndpointPolicy() throws {
        let missing = SignedReleaseCheckResult(enforced: true, mask: 0,
            releaseID: "", sealDigest: "", issue: .missingSeal)
        try require(missing.enforced && missing.mask == 0 && missing.isCompromised,
                    "missing seal never pretends to be a verified release")
        try require(!missing.requiresLocalBlock && missing.isMissingSeal,
                    "missing seal can negotiate server policy without declaring jailbreak")
        for issue in [SignedReleaseIssue.invalidSeal, .unreadableInstallation, .verificationFailed] {
            let invalid = SignedReleaseCheckResult(enforced: true, mask: 0,
                releaseID: "", sealDigest: "", issue: issue)
            try require(invalid.requiresLocalBlock, "invalid present seal remains fail-closed")
        }
        try require(AstraServerTrust.protectedHost == "zynox.click", "production host decodes correctly")
        try require(AstraServerTrust.protectedOrigin == "https://" + AstraServerTrust.protectedHost,
                    "production origin agrees with endpoint policy")
        try require(!AstraServerTrust.leafCertificatePins.isEmpty &&
                    AstraServerTrust.leafCertificatePins.allSatisfy { Data(base64Encoded: $0)?.count == 32 },
                    "production pins remain SHA256 leaf digests")
        for address in [
            "https://zynox.click/api/v2/artifacts/sync",
            "https://zynox.click/api/v2/artifacts/resolve",
            "https://zynox.click:443/api/v2/novax/session/open",
            "https://zynox.click/api/v2/artifacts/00000000-0000-4000-8000-000000000004/content"
        ] {
            try require(SecureAPIEndpointPolicy.permits(URL(string: address)!), "allowed endpoint: " + address)
        }
        for address in [
            "http://zynox.click/api/v2/artifacts/sync",
            "https://zynox.click.evil.test/api/v2/artifacts/sync",
            "https://zynox.click:444/api/v2/artifacts/sync",
            "https://user:password@zynox.click/api/v2/artifacts/sync",
            "https://zynox.click/api/admin/keys",
            "https://zynox.click/api/novax/codepatch/ffth/mod/download",
            "https://zynox.click/api/v2/artifacts/sync#fragment",
            "https://zynox.click/api/v2/artifacts%2fsync",
            "https://zynox.click/api/v2//artifacts/sync",
            "https://10.7.0.1/api/v2/artifacts/sync"
        ] {
            try require(!SecureAPIEndpointPolicy.permits(URL(string: address)!), "rejected endpoint: " + address)
        }
    }

    @MainActor
    static func checkNetworkGate() async throws {
        var mobilePolicy = NetworkAccessPolicy()
        mobilePolicy.record(.allowed, now: 100)
        let mobileLease = mobilePolicy.generation
        try require(mobilePolicy.permits(mobileLease, now: 115), "bounded reprobe latency does not prematurely cancel healthy requests")
        try require(!mobilePolicy.permits(mobileLease, now: 117), "network lease remains bounded after reprobe timeout")
        mobilePolicy.record(.blocked("pin mismatch"), now: 102)
        try require(!mobilePolicy.permits(mobileLease, now: 102), "positive interception revokes without waiting for lease expiry")
        var policy = NetworkAccessPolicy(maximumAge: 6)
        try require(!policy.isAllowed(now: 100), "initial policy blocks")
        policy.record(.allowed, now: 100)
        let lease = policy.generation
        try require(policy.permits(lease, now: 105), "fresh monotonic lease")
        try require(!policy.permits(lease, now: 106), "expired monotonic lease")
        try require(!policy.permits(lease, now: 99), "backwards monotonic clock rejected")
        policy.record(.blocked("pin mismatch"), now: 101)
        try require(!policy.permits(lease, now: 101), "block invalidates previous lease")
        policy.record(.allowed, now: 102)
        try require(!policy.permits(lease, now: 103), "recovery does not revive old lease")
        policy.invalidate(.unavailable)
        try require(!policy.isAllowed(now: 103), "offline cannot authorize work")

        let probe = ControlledNetworkProbe()
        let gate = NetworkAccessGate(probe: { await probe.run() }, automaticallyPoll: false)
        gate.setActive(true)
        var firstStarted = false
        var secondStarted = false
        let first = Task { firstStarted = true; await gate.checkNow() }
        let second = Task { secondStarted = true; await gate.checkNow() }
        for _ in 0..<100 {
            let count = await probe.calls
            if firstStarted && secondStarted && count == 1 { break }
            await Task.yield()
        }
        let initialCalls = await probe.calls
        try require(firstStarted && secondStarted && initialCalls == 1, "single-flight probe deduplication")
        await probe.finish(.allowed)
        await first.value
        await second.value
        try require(gate.isAllowed, "successful current probe opens gate")
        let currentGeneration = try await gate.requireAllowed()
        try gate.validateGeneration(currentGeneration)
        gate.setActive(false)
        try rejects("inactive invalidates old generation") { try gate.validateGeneration(currentGeneration) }

        gate.setActive(true)
        let stale = Task { await gate.checkNow() }
        try await waitForProbeCalls(2, probe)
        try require((await probe.calls) == 2, "foreground starts fresh probe")
        gate.recordCertificateFailure()
        await probe.finish(.allowed)
        await stale.value
        try require(gate.state == .blocked && !gate.isAllowed, "stale success cannot undo newer certificate failure")

        let offline = Task { await gate.checkNow() }
        try await waitForProbeCalls(3, probe)
        await probe.finish(.unavailable("offline"))
        await offline.value
        try require(gate.state == .unavailable && !gate.isAllowed, "offline differs from detected proxy")

        let recovery = Task { await gate.checkNow() }
        try await waitForProbeCalls(4, probe)
        await probe.finish(.allowed)
        await recovery.value
        try require(gate.isAllowed, "verified retry recovers gate")

        let priorForeground = Task { await gate.checkNow() }
        try await waitForProbeCalls(5, probe)
        gate.setActive(false)
        gate.setActive(true)
        let newForeground = Task { await gate.checkNow() }
        try await waitForProbeCalls(6, probe)
        await probe.finish(.allowed)
        await priorForeground.value
        try require(!gate.isAllowed, "old foreground probe cannot reopen new foreground")
        await probe.finish(.allowed)
        await newForeground.value
        try require(gate.isAllowed, "new foreground needs its own verified probe")
        gate.setActive(false)

        let cancellationProbe = ControlledNetworkProbe()
        let cancellationGate = NetworkAccessGate(probe: { await cancellationProbe.run() }, automaticallyPoll: false)
        cancellationGate.setActive(true)
        var cancelledStarted = false
        var survivorStarted = false
        let cancelled = Task { cancelledStarted = true; return try await cancellationGate.requireAllowed() }
        let survivor = Task { survivorStarted = true; return try await cancellationGate.requireAllowed() }
        for _ in 0..<100 {
            let count = await cancellationProbe.calls
            if cancelledStarted && survivorStarted && count == 1 { break }
            await Task.yield()
        }
        cancelled.cancel()
        await cancellationProbe.finish(.allowed)
        do {
            _ = try await cancelled.value
            throw SelfCheckFailure.failed("cancelled caller was allowed")
        } catch is CancellationError { checks += 1 }
        let survivorGeneration = try await survivor.value
        try cancellationGate.validateGeneration(survivorGeneration)
        try require(cancellationGate.isAllowed, "one cancelled caller does not cancel shared probe")
        cancellationGate.setActive(false)
    }

    private static func waitForProbeCalls(_ expected: Int, _ probe: ControlledNetworkProbe) async throws {
        for _ in 0..<10_000 {
            if (await probe.calls) == expected { return }
            await Task.yield()
        }
        throw SelfCheckFailure.failed("probe task did not start")
    }

    static func checkRequestRegistry() throws {
        let registry = APIRequestRegistry()
        let beforeRevocation = registry.epoch
        let old = APIRequestCancellation()
        var oldCancelled = false
        old.install { oldCancelled = true }
        try registry.register(old, id: UUID(), expectedEpoch: beforeRevocation)
        registry.cancelActive()
        try require(oldCancelled, "gate revocation cancels registered request")
        try rejects("old epoch registration") {
            try registry.register(APIRequestCancellation(), id: UUID(), expectedEpoch: beforeRevocation)
        }
        let recovered = APIRequestCancellation()
        var recoveredCancelled = false
        recovered.install { recoveredCancelled = true }
        let recoveredID = UUID()
        try registry.register(recovered, id: recoveredID, expectedEpoch: registry.epoch)
        old.cancel()
        try require(!recoveredCancelled, "late old cancellation cannot touch recovered request")
        registry.remove(recoveredID)
        registry.cancelActive()
        try require(!recoveredCancelled, "completed requests are removed from registry")
        let early = APIRequestCancellation()
        early.cancel()
        var earlyCancelled = false
        early.install { earlyCancelled = true }
        try require(earlyCancelled, "cancellation before operation creation is retained")
    }
}
