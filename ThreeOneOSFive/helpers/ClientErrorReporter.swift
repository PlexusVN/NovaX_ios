import Foundation

final class ClientErrorReporter {
    static let shared = ClientErrorReporter()
    private init() {}

    func report(
        key: String?,
        action: String,
        message: String,
        fullLog: String
    ) {
        let cleanKey = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanAction = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMsg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLog = fullLog.trimmingCharacters(in: .whitespacesAndNewlines)
        let iosExact = "\(AppInfo.osVersion) (\(AppInfo.osBuild))"

        Task.detached(priority: .utility) {
            guard AppSecurityConfiguration.isConfigured else { return }
            guard let url = URL(string: "https://\(AppSecurityConfiguration.apiHost)/api/client/report-error") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15

            let payload: [String: Any] = [
                "key": cleanKey,
                "ios": iosExact,
                "action": cleanAction,
                "message": cleanMsg,
                "full_log": cleanLog,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                _ = try await SecureAPIClient.shared.data(for: request)
            } catch {
                // Silently ignore telemetry failure to avoid disturbing the user
            }
        }
    }
}
