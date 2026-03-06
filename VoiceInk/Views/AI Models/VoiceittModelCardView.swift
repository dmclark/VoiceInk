import SwiftUI

struct VoiceittModelCardView: View {
    let model: CloudModel
    let isCurrent: Bool
    var setDefaultAction: () -> Void

    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @State private var isExpanded = false
    @State private var email = ""
    @State private var password = ""
    @State private var appId = ""
    @State private var apiKey = ""
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var isSignedIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    headerSection
                    metadataSection
                    descriptionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionSection
            }
            .padding(16)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                configurationSection
                    .padding(16)
            }
        }
        .background(CardBackground(isSelected: isCurrent, useAccentGradientWhenSelected: isCurrent))
        .onAppear {
            isSignedIn = VoiceittAuthService.shared.isSignedIn
        }
    }

    private var headerSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            statusBadge

            Spacer()
        }
    }

    private var statusBadge: some View {
        Group {
            if isCurrent {
                Text("Default")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundColor(.white)
            } else if isSignedIn {
                Text("Configured")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.systemGreen).opacity(0.2)))
                    .foregroundColor(Color(.systemGreen))
            } else {
                Text("Setup Required")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(.systemOrange).opacity(0.2)))
                    .foregroundColor(Color(.systemOrange))
            }
        }
    }

    private var metadataSection: some View {
        HStack(spacing: 12) {
            Label(model.provider.rawValue, systemImage: "cloud")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)

            Label(model.language, systemImage: "globe")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
                .lineLimit(1)
        }
        .lineLimit(1)
    }

    private var descriptionSection: some View {
        Text(model.description)
            .font(.system(size: 11))
            .foregroundColor(Color(.secondaryLabelColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private var actionSection: some View {
        HStack(spacing: 8) {
            if isCurrent {
                Text("Default Model")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.secondaryLabelColor))
            } else if isSignedIn {
                Button(action: setDefaultAction) {
                    Text("Set as Default")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(action: {
                    withAnimation(.interpolatingSpring(stiffness: 170, damping: 20)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Configure")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "gear")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.controlAccentColor))
                            .shadow(color: Color(.controlAccentColor).opacity(0.2), radius: 2, x: 0, y: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            if isSignedIn {
                Menu {
                    if let email = VoiceittAuthService.shared.email {
                        Text("Signed in as \(email)")
                    }
                    Divider()
                    Button {
                        signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20, height: 20)
            }
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Voiceitt Login")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(.labelColor))

            Text("Sign in with your Voiceitt account to use your personal speech model.")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))

            VStack(spacing: 8) {
                TextField("App ID", text: $appId)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSigningIn)

                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSigningIn)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSigningIn)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSigningIn)
            }

            HStack {
                Button(action: signIn) {
                    HStack(spacing: 4) {
                        if isSigningIn {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Text(isSigningIn ? "Signing in..." : "Sign In")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.controlAccentColor))
                    )
                }
                .buttonStyle(.plain)
                .disabled(email.isEmpty || password.isEmpty || appId.isEmpty || apiKey.isEmpty || isSigningIn)

                Spacer()
            }

            if let error = signInError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(Color(.systemRed))
            }
        }
    }

    private func signIn() {
        isSigningIn = true
        signInError = nil

        Task {
            do {
                try await VoiceittAuthService.shared.signIn(
                    appId: appId,
                    apiKey: apiKey,
                    email: email,
                    password: password
                )
                await MainActor.run {
                    isSigningIn = false
                    isSignedIn = true
                    password = ""
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    signInError = error.localizedDescription
                }
            }
        }
    }

    private func signOut() {
        VoiceittAuthService.shared.signOut()
        isSignedIn = false
        email = ""
        password = ""
        appId = ""
        apiKey = ""
        signInError = nil

        if isCurrent {
            Task {
                await MainActor.run {
                    transcriptionModelManager.clearCurrentTranscriptionModel()
                }
            }
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            isExpanded = false
        }
    }
}
