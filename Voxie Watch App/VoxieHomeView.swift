import SwiftUI
import UIKit
import WatchKit

// Walkie-Talkie palette: Apple's bright card yellow on pure black.
private let walkieYellow = Color(red: 1, green: 0.89, blue: 0.13)
private let walkieGray = Color(white: 0.24)
private let addFriendRoute = "__voxie_add_friend"

struct VoxieHomeView: View {
    @EnvironmentObject private var model: VoxieV2Model

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !model.ready {
                WatchSetupPrompt()
            } else if !model.hasLoadedProfile {
                ProgressView("Verbinden…")
                    .tint(walkieYellow)
            } else if model.username.isEmpty {
                WatchSetupPrompt()
            } else {
                WalkieRootView()
            }
            if model.incomingFriendID != nil {
                IncomingTalkView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.incomingFriendID)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Friend list (Apple Walkie-Talkie main screen)

private struct WalkieRootView: View {
    @EnvironmentObject private var model: VoxieV2Model
    @State private var path: [String] = []
    @State private var friendToRemove: VoxieFriend?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Toggle(isOn: Binding(get: { model.available }, set: { model.setAvailable($0) })) {
                        Text("Walkietalkie")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .tint(walkieYellow)
                } footer: {
                    if !model.available {
                        Text("Je bent niet beschikbaar. Vrienden krijgen een melding als ze willen praten.")
                    }
                }

                if !model.invitations.isEmpty {
                    Section("Uitnodigingen") {
                        ForEach(model.invitations) { invitation in
                            InvitationCard(invitation: invitation)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        }
                    }
                }

                Section {
                    if model.friends.isEmpty {
                        Text("Nog geen vrienden. Voeg iemand toe met zijn of haar Voxie-naam.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(model.friends) { friend in
                        Button { path.append(friend.id) } label: {
                            FriendCard(name: friend.name, avatar: friend.avatar,
                                       active: friend.available, subtitle: friend.available ? nil : "Niet beschikbaar")
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { friendToRemove = friend } label: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
                }

                if !model.pending.isEmpty {
                    Section("Uitgenodigde vrienden") {
                        ForEach(model.pending) { friend in
                            FriendCard(name: friend.name, avatar: nil, active: false, subtitle: "Uitgenodigd")
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        }
                    }
                }

                Section {
                    NavigationLink(value: addFriendRoute) {
                        Label("Voeg vrienden toe", systemImage: "plus")
                            .foregroundStyle(walkieYellow)
                            .font(.system(size: 15, weight: .semibold))
                    }
                } footer: {
                    Text("Je bent @\(model.username). Profiel en foto wijzig je op je iPhone.")
                }
            }
            .navigationTitle("Voxie")
            .navigationDestination(for: String.self) { route in
                if route == addFriendRoute {
                    AddFriendView()
                } else {
                    TalkView(friendID: route)
                }
            }
        }
        .tint(walkieYellow)
        .confirmationDialog("Verwijder \(friendToRemove.map { "@\($0.name)" } ?? "vriend")?",
                            isPresented: Binding(get: { friendToRemove != nil },
                                                 set: { if !$0 { friendToRemove = nil } })) {
            Button("Verwijder", role: .destructive) {
                if let friend = friendToRemove { Task { await model.removeFriend(friend.id) } }
                friendToRemove = nil
            }
            Button("Annuleer", role: .cancel) { friendToRemove = nil }
        }
        // A tapped "praat met je" notification opens that friend directly,
        // also when it launched Voxie before this screen existed.
        .onAppear { openRequestedFriend(model.openFriendRequest) }
        .onChange(of: model.openFriendRequest) { _, id in openRequestedFriend(id) }
    }

    private func openRequestedFriend(_ id: String?) {
        guard let id, model.friends.contains(where: { $0.id == id }) else { return }
        model.openFriendRequest = nil
        path = [id]
    }
}

/// Large rounded card: yellow when you can talk, gray when invited/unavailable.
private struct FriendCard: View {
    let name: String
    let avatar: String?
    let active: Bool
    let subtitle: String?

    var body: some View {
        HStack(spacing: 9) {
            AvatarView(name: name, avatar: avatar, size: 34,
                       background: active ? .black.opacity(0.85) : Color(white: 0.4))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(active ? .black : .white)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(active ? walkieYellow : walkieGray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct InvitationCard: View {
    @EnvironmentObject private var model: VoxieV2Model
    let invitation: VoxieInvitation
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                AvatarView(name: invitation.name, avatar: nil, size: 28, background: Color(white: 0.4))
                VStack(alignment: .leading, spacing: 0) {
                    Text("@\(invitation.name)").font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("wil met je praten").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Button("Sta toe") { respond(true) }
                    .buttonStyle(.borderedProminent)
                    .tint(walkieYellow)
                    .foregroundStyle(.black)
                Button("Weiger") { respond(false) }
                    .buttonStyle(.bordered)
            }
            .font(.system(size: 13, weight: .semibold))
            .disabled(busy)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(walkieGray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func respond(_ accept: Bool) {
        busy = true
        Task { await model.respond(invitation: invitation.id, accept: accept); busy = false }
    }
}

private struct AvatarView: View {
    let name: String
    let avatar: String?
    let size: CGFloat
    let background: Color

    var body: some View {
        Group {
            if let avatar, let data = Data(base64Encoded: avatar), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
                    .foregroundStyle(walkieYellow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(background)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Talk screen

private struct TalkView: View {
    @EnvironmentObject private var model: VoxieV2Model
    let friendID: String
    @State private var crownVolume = 1.0
    @State private var showVolume = false
    @State private var hideVolumeTask: Task<Void, Never>?

    private var friend: VoxieFriend? { model.friends.first { $0.id == friendID } }

    var body: some View {
        VStack(spacing: 6) {
            if let friend {
                HStack(spacing: 6) {
                    AvatarView(name: friend.name, avatar: friend.avatar, size: 22, background: walkieGray)
                    Text(friend.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(walkieYellow)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                TalkButton()
                Text(stateLine(friend))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(minHeight: 30)
            } else {
                Text("Deze vriend is niet meer beschikbaar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .trailing) {
            if showVolume { VolumeIndicator(level: crownVolume).padding(.trailing, 1) }
        }
        .focusable()
        .digitalCrownRotation($crownVolume, from: 0.1, through: 1, by: 0.05,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crownVolume) { _, value in
            model.setPlaybackVolume(value)
            showVolume = true
            hideVolumeTask?.cancel()
            hideVolumeTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled { showVolume = false }
            }
        }
        .onAppear {
            crownVolume = model.playbackVolume
            model.selectedFriendID = friendID
        }
        .onDisappear {
            model.endSpeaking()
            if model.selectedFriendID == friendID { model.selectedFriendID = nil }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isError: Bool {
        let text = model.status
        return text.contains("mislukt") || text.contains("niet verzonden") || text.contains("verlopen")
            || text.contains("Geef toegang") || text.contains("Microfoon")
    }

    private func stateLine(_ friend: VoxieFriend) -> String {
        if model.isSpeaking { return "Praat…" }
        if model.isSending { return "Verbinden…" }
        if !model.available { return "Zet Walkietalkie aan om te praten" }
        if isError || model.status.contains("niet beschikbaar") { return model.status }
        if model.lastSendOK { return "Verzonden" }
        if !friend.available { return "@\(friend.name) is niet beschikbaar" }
        return UserDefaults.standard.bool(forKey: "voxie.tapToTalk") ? "Tik om te praten" : "Houd vast om te praten"
    }
}

/// The big yellow Walkie-Talkie button. Hold to talk (default) or tap to talk.
private struct TalkButton: View {
    @EnvironmentObject private var model: VoxieV2Model
    @AppStorage("voxie.tapToTalk") private var tapToTalk = false
    @State private var pressed = false

    var body: some View {
        let live = pressed || model.isSpeaking
        ZStack {
            Circle()
                .fill(walkieYellow.opacity(model.available ? 1 : 0.4))
                .shadow(color: walkieYellow.opacity(live ? 0.8 : 0), radius: live ? 14 : 0)
            if live {
                Circle()
                    .stroke(walkieYellow.opacity(0.55), lineWidth: 5)
                    .scaleEffect(1.12)
            }
            VStack(spacing: 2) {
                Image(systemName: live ? "waveform" : "mic.fill")
                    .font(.system(size: 30, weight: .heavy))
                    .symbolEffect(.variableColor.iterative, isActive: live)
                Text(live ? "PRATEN" : "PRAAT")
                    .font(.system(size: 13, weight: .black, design: .rounded))
            }
            .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .scaleEffect(live ? 0.95 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: live)
        .contentShape(Circle())
        .gesture(tapToTalk ? nil : DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressed else { return }
                pressed = true
                model.beginSpeaking()
            }
            .onEnded { _ in
                pressed = false
                model.endSpeaking()
            })
        .onTapGesture {
            guard tapToTalk else { return }
            if model.isSpeaking || pressed {
                pressed = false
                model.endSpeaking()
            } else {
                pressed = true
                model.beginSpeaking()
            }
        }
        .onChange(of: model.isSpeaking) { _, speaking in
            // 15-second limit or an error ended the recording.
            if !speaking && tapToTalk { pressed = false }
        }
        .accessibilityLabel(tapToTalk ? "Tik om te praten, tik nogmaals om te versturen"
                                      : "Houd vast om te praten, laat los om te versturen")
        .accessibilityAddTraits(.isButton)
    }
}

private struct VolumeIndicator: View {
    let level: Double

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color(white: 0.3))
                    Capsule().fill(walkieYellow)
                        .frame(height: geometry.size.height * level)
                }
            }
            .frame(width: 5, height: 70)
        }
        .foregroundStyle(walkieYellow)
        .accessibilityLabel("Volume \(Int(level * 100)) procent")
    }
}

// MARK: - Incoming speech (friend is talking)

private struct IncomingTalkView: View {
    @EnvironmentObject private var model: VoxieV2Model
    @State private var pulse = false

    private var friend: VoxieFriend? { model.friends.first { $0.id == model.incomingFriendID } }

    var body: some View {
        let name = friend?.name ?? model.incomingName ?? "Vriend"
        VStack(spacing: 10) {
            ZStack {
                ForEach(0..<3) { ring in
                    Circle()
                        .stroke(walkieYellow.opacity(0.7 - Double(ring) * 0.2), lineWidth: 3)
                        .frame(width: 74, height: 74)
                        .scaleEffect(pulse ? 1.25 + Double(ring) * 0.22 : 1)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)
                            .delay(Double(ring) * 0.3), value: pulse)
                }
                AvatarView(name: name, avatar: friend?.avatar, size: 74, background: walkieGray)
                    .overlay(Circle().stroke(walkieYellow, lineWidth: 3))
            }
            .frame(height: 110)
            Text(name.hasPrefix("@") ? name : "@\(name)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(walkieYellow)
                .lineLimit(1)
            Text("praat…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.94).ignoresSafeArea())
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) praat")
    }
}

// MARK: - Add friends

private struct AddFriendView: View {
    @EnvironmentObject private var model: VoxieV2Model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("voxie.tapToTalk") private var tapToTalk = false
    @State private var handle = ""
    @State private var sending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nodig een vriend uit met zijn of haar Voxie-naam.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("@gebruikersnaam", text: $handle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    sending = true
                    Task {
                        await model.invite(username: handle)
                        sending = false
                        if model.status == "Uitnodiging verstuurd" { dismiss() }
                    }
                } label: {
                    Text(sending ? "Versturen…" : "Nodig uit")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(walkieYellow)
                .foregroundStyle(.black)
                .disabled(handle.trimmingCharacters(in: .whitespaces).count < 3 || sending)
                if model.status.hasPrefix("Uitnodigen") {
                    Text(model.status).font(.system(size: 11)).foregroundStyle(.red)
                }
                Divider().padding(.vertical, 4)
                Toggle("Tik om te praten", isOn: $tapToTalk)
                    .tint(walkieYellow)
                    .font(.system(size: 14))
                Text("Aan: tik één keer om te beginnen en nog eens om te versturen, in plaats van ingedrukt houden.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Toevoegen")
    }
}

// MARK: - Setup

private struct WatchSetupPrompt: View {
    @EnvironmentObject private var model: VoxieV2Model

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(walkieYellow)
                        .frame(width: 52, height: 52)
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.black)
                }
                Text("Stel Voxie in op je iPhone")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Open Voxie op je iPhone en rond de installatie af. Je Watch wordt daarna automatisch gekoppeld.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if model.status != "Log in met Apple" {
                    Text(model.status)
                        .font(.system(size: 11))
                        .foregroundStyle(walkieYellow)
                        .multilineTextAlignment(.center)
                }
                Button("Koppel opnieuw") { VoxieWatchBridge.shared.requestSessionFromPhone() }
                    .buttonStyle(.borderedProminent)
                    .tint(walkieYellow)
                    .foregroundStyle(.black)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 6)
        }
    }
}
