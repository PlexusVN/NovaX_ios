import Foundation

@main struct CertificatePinSelfCheck {
    static func main() {
        precondition(AppSecurityConfiguration.permitsCertificatePins([AppSecurityConfiguration.tlsLeafPin]))
        precondition(AppSecurityConfiguration.permitsCertificatePins([
            "new-leaf", "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="]))
        precondition(!AppSecurityConfiguration.permitsCertificatePins([]))
        precondition(!AppSecurityConfiguration.permitsCertificatePins(["proxy-leaf", "user-installed-root"]))
        precondition(!AppSecurityConfiguration.permitsCertificatePins([
            "69QQQOS7PsdCyeOB0x7ypBpItmhclufO88HfbNQzHJk="]))
        print("[PASS] current leaf/WE1 renewal accepted; unknown/user/root-only chain denied")
    }
}
