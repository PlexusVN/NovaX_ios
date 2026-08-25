import SwiftUI

struct LoadingScreenView: View {
    @State private var logoOpacity: Double = 0
    @State private var spinnerOpacity: Double = 0
    @State private var showContent = false

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                AppLogo(size: 80)
                    .opacity(logoOpacity)
                    .scaleEffect(logoOpacity == 0 ? 0.92 : 1.0)

                ProgressView()
                    .tint(Color.secondary)
                    .opacity(spinnerOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                logoOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                spinnerOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeIn(duration: 0.35)) {
                    logoOpacity = 0
                    spinnerOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showContent = true
                }
            }
        }
        .opacity(showContent ? 0 : 1)
    }
}
