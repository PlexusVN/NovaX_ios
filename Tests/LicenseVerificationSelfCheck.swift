import Foundation

@main
struct LicenseVerificationSelfCheck {
    static func main() throws {
        for key in ["VA-rbjX-9SWN", "va-RBJx-9swn", "A&B+C%=#?_\\key", "KÍ TỰ thường"] {
            let request = try LicenseVerification.request(
                origin: "https://example.invalid", key: " \n\(key)\r\n",
                hwid: "hwid+&=#", secret: "test-secret", deviceName: "Tên & máy +")
            precondition(request.httpMethod == "POST")
            precondition(request.url?.absoluteString == "https://example.invalid/api/verify")
            precondition(request.url?.query == nil)
            precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            precondition(body["key"] == key)
            precondition(body["hwid"] == "hwid+&=#")
            precondition(body["device_name"] == "Tên & máy +")
        }
        for code in ["key_expired", "key_banned", "key_invalid", "key_max_devices", "hwid_banned"] {
            let json: [String: Any] = ["code": code, "message": "Authentication failed"]
            precondition(!LicenseVerification.isTransient(statusCode: 200, json: json))
            precondition(!LicenseVerification.message(statusCode: 200, json: json).contains("Authentication failed"))
        }
        precondition(LicenseVerification.message(statusCode: 200,
            json: ["code": "key_expired", "message": "Authentication failed"]) == "KEY đã hết hạn")
        precondition(LicenseVerification.isTransient(statusCode: 429, json: [:]))
        precondition(LicenseVerification.isTransient(statusCode: 503, json: [:]))
        precondition(LicenseVerification.isTransient(statusCode: 200, json: ["code": "backend_unavailable"]))
        precondition(!LicenseVerification.isTransient(statusCode: 423,
            json: ["code": "device_jailbreak_quarantined"]))
        print("PASS: literal license POST transport, error mapping and transient failure policy")
    }
}
