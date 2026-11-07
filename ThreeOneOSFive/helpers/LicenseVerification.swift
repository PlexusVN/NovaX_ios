import Foundation

/// Shared by initial login and the background monitor. Do not uppercase a
/// credential or interpolate it into a URL: JSON preserves every literal byte.
enum LicenseVerification {
    static func request(origin: String, key: String, hwid: String,
                        secret: String, deviceName: String) throws -> URLRequest {
        guard let url = URL(string: origin + "/api/verify") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "key": key.trimmingCharacters(in: .whitespacesAndNewlines),
            "hwid": hwid, "secret": secret, "device_name": deviceName
        ])
        return request
    }

    static func isTransient(statusCode: Int, json: [String: Any]) -> Bool {
        statusCode == 429 || statusCode >= 500 ||
            ["rate_limited", "backend_unavailable", "schema_not_ready"]
                .contains(json["code"] as? String ?? "") ||
            json["status"] as? String == "rate_limited"
    }

    static func message(statusCode: Int, json: [String: Any]) -> String {
        if isTransient(statusCode: statusCode, json: json) {
            return statusCode == 429 || json["code"] as? String == "rate_limited"
                ? "Quá nhiều yêu cầu, vui lòng đợi rồi thử lại"
                : "Máy chủ xác thực tạm thời không khả dụng, vui lòng thử lại"
        }
        // Prefer the stable protocol code over generic/English server messages.
        switch json["code"] as? String ?? "" {
        case "key_expired": return "KEY đã hết hạn"
        case "key_banned": return "KEY đã bị khóa"
        case "key_invalid", "key_wrong_product":
            return "KEY không hợp lệ hoặc không thuộc ứng dụng này"
        case "key_max_devices": return "KEY đã đạt số thiết bị tối đa"
        case "key_used": return "KEY đã được sử dụng"
        case "hwid_mismatch": return "KEY không khớp với thiết bị này"
        case "hwid_banned": return "Thiết bị đã bị chặn trên hệ thống"
        case "invalid_secret": return "Lỗi cấu hình xác thực sản phẩm"
        default: break
        }
        // Compatible with older servers which only supply status/message.
        switch json["status"] as? String ?? "" {
        case "expired": return "KEY đã hết hạn"
        case "max_devices": return "KEY đã đạt số thiết bị tối đa"
        default: break
        }
        let text = json["message"] as? String ?? ""
        if text == "Authentication failed" {
            return "Không thể xác thực KEY. Kiểm tra key, hạn dùng và thiết bị đăng ký"
        }
        if !text.isEmpty { return text }
        return statusCode == 404 ? "Máy chủ xác thực không khả dụng" : "Xác thực thất bại"
    }
}
