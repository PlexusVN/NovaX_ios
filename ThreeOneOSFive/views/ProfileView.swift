import SwiftUI

struct ProfileView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var showAttribution = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AppLogo(size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NovaX")
                                .font(.title2.weight(.bold))
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section(language.text("common.device")) {
                    LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
                    LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    LabeledContent(language.text("settings.compatibility")) {
                        Text(language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"))
                            .foregroundStyle(appState.isSupported ? Color.green : Color.red)
                    }
                }

                Section(language.text("settings.social_media")) {
                    LinkRow(
                        name: "GitHub",
                        role: language.text("social.github_role"),
                        url: "https://github.com/YangJiiii/3105"
                    )
                    LinkRow(
                        name: "Cộng Đồng IOSVN",
                        role: language.text("social.iosvn_role"),
                        url: "https://t.me/ioscrackvn"
                    )
                }

                Section(language.text("settings.credits")) {
                    LinkRow(name: "YangJiii", role: language.text("credit.yangjiii"), url: "https://x.com/duongduong0908")
                    LinkRow(name: "0xjohnnydev", role: language.text("credit.filzaslop"), url: "https://github.com/0xjohnnydev/FilzaSlop")
                    LinkRow(name: "LeminLimez", role: language.text("credit.pocket_poster"), url: "https://github.com/leminlimez/Pocket-Poster")
                    LinkRow(name: "CrazyMind90", role: language.text("credit.sandbox_escape"), url: "https://github.com/CrazyMind90")
                    LinkRow(name: "forcequitOS", role: language.text("credit.forcequit"), url: "https://github.com/forcequitOS")
                }
            }
            .navigationTitle(language.text("tab.profile"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct LinkRow: View {
    @Environment(\.appLanguage) private var language
    let name: String
    let role: String
    let url: String

    var body: some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(language.text("accessibility.open_profile", name))
        }
    }
}
