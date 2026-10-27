import AuthenticationServices
import CryptoKit
import SwiftUI

struct VoxieSignInView: View {
    @EnvironmentObject private var model: VoxieV2Model
    @State private var nonce: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.yellow)
            Text("VOXIE")
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(.yellow)
            Group {
                #if os(watchOS)
                Text("Stel Voxie eerst in op je iPhone of iPad. Meld je daarna hier aan met hetzelfde Apple-account.")
                #else
                Text("Log in om met vrienden te praten")
                #endif
            }
                .font(.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            if let nonce {
                SignInWithAppleButton(.signIn, onRequest: { request in
                    request.requestedScopes = []
                    request.nonce = Self.sha256(nonce)
                }, onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                              let identityToken = credential.identityToken,
                              let jwt = String(data: identityToken, encoding: .utf8) else {
                            model.setError("Apple-aanmelding kon niet worden gelezen")
                            Task { await loadNonce() }
                            return
                        }
                        Task {
                            await model.finishAppleSignIn(identityToken: jwt, nonce: nonce)
                            await loadNonce()
                        }
                    case .failure(let error):
                        model.setError(error.localizedDescription)
                        Task { await loadNonce() }
                    }
                })
                .signInWithAppleButtonStyle(.white)
                .frame(height: 44)
            } else {
                ProgressView("Verbinding voorbereiden…")
                    .tint(.yellow)
                Button("Opnieuw proberen") { Task { await loadNonce() } }
                    .font(.footnote)
                    .foregroundStyle(.yellow)
            }

            Text(model.status)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .task { await loadNonce() }
    }

    private func loadNonce() async { nonce = await model.requestAppleNonce() }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
