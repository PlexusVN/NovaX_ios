import Foundation

enum DeviceEnvironmentSelfCheck {
    static func run(fixtureURL: URL) throws {
        func expect(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: label, code: 1) }
            print("[PASS] environment: \(label)")
        }
        var snapshot = DeviceEnvironmentSnapshot()
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .allowed, "clean self-signed baseline")
        snapshot.paths = ["/Applications/Cydia.app"]
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .allowed, "one package-manager artifact is not sufficient")
        snapshot.paths = ["/Library/MobileSubstrate/MobileSubstrate.dylib", "/private/var/lib/dpkg/status"]
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "coherent rootful bootstrap")
        snapshot.paths = ["/var/jb/usr/lib/libellekit.dylib", "/var/jb/var/lib/dpkg/status"]
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "coherent rootless bootstrap")
        snapshot.paths = ["/var/jb/var/lib/dpkg/status"]; snapshot.links = ["/var/jb"]
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "rootless topology plus package database")
        snapshot = DeviceEnvironmentSnapshot(); snapshot.images = ["/System/Library/Frameworks/Foundation.framework/Foundation", "/App/Astra.app/Frameworks/AirliftFFI.framework/AirliftFFI"]
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .allowed, "system and AirLift framework remain supported")
        for name in ["FridaGadget.dylib", "libellekit.dylib", "libhooker.dylib", "MobileSubstrate.dylib", "libcycript.dylib"] {
            snapshot.images = ["/App/Astra.app/Frameworks/" + name]
            try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "injected library \(name)")
        }
        snapshot.images = ["/usr/lib/FridaGadget.dylib"]
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "known injected library is still detected under a system-looking path")
        snapshot = DeviceEnvironmentSnapshot(); snapshot.privileged = true
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "privileged process")
        snapshot = DeviceEnvironmentSnapshot(); snapshot.interposedAPI = true
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "system API owned by an unexpected image")
        snapshot = DeviceEnvironmentSnapshot(); snapshot.insertedLibraries = true
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "dynamic loader injection environment")
        snapshot = DeviceEnvironmentSnapshot(); snapshot.debugger = true
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "attached debugger")
        snapshot = DeviceEnvironmentSnapshot(); snapshot.paths = ["/private/var/lib/dpkg/status"]; snapshot.contradictoryPaths = true
        try expect(DeviceEnvironmentInspector.evaluate(snapshot).state == .blocked, "artifact plus repeated API contradictions")
        try expect(DeviceEnvironmentPolicy.evaluate(checked: 1, signals: 0) == .unverified, "incomplete collection is not a clean device")
        try expect(DeviceEnvironmentPolicy.evaluate(checked: 1, signals: 2) == .unverified, "unmeasured signal cannot authorize")
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
        let decisions = Array((fixture["decisions"] as! String).utf8)
        try expect(decisions.count == 16384, "parity fixture covers the full signal space")
        for signals in 0...DeviceEnvironmentResult.requiredMask {
            let state = DeviceEnvironmentPolicy.evaluate(checked: DeviceEnvironmentResult.requiredMask, signals: signals)
            guard decisions[signals] == (state == .blocked ? 98 : 97) else { throw NSError(domain: "environment policy parity", code: signals) }
        }
        try expect(true, "all 16384 combinations match the server policy")
        let environment = DeviceEnvironmentResult(checkedMask: DeviceEnvironmentResult.requiredMask, signalMask: 64)
        let result = SecurityCheckResult(mask: 1023, environment: environment)
        try expect(result.isCompromised && !result.permitsProtectedOperation, "a valid IPA seal cannot override a blocked environment")
        try expect(!SecurityCheckResult(mask: 1023).permitsProtectedOperation, "missing environment measurement cannot authorize a protected operation")
        let url = URL(string: AppSecurityConfiguration.apiOrigin + "/api/v2/security/integrity-v2")!
        // This executable does not link SecureAPIClient; endpoint interoperability
        // is tested separately by ProtectedArtifactSelfCheck.
        try expect(url.path == "/api/v2/security/integrity-v2", "versioned route is exact")
    }
}
