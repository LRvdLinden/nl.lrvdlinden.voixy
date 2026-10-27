import SwiftUI

private let voxieYellow = Color(red: 1, green: 0.85, blue: 0)

struct VoxieHomeView: View {
    @EnvironmentObject private var model: VoxieV2Model

    var body: some View {
        Group {
            if !model.ready {
                watchSetupPrompt
            } else if !model.hasLoadedProfile {
                ProgressView("Profiel laden…")
                    .tint(voxieYellow)
            } else if model.username.isEmpty {
                watchSetupPrompt
            } else {
                TabView {
                    talkingPage
                    friendsPage
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "voxie.watchPairedViaPhone") {
                model.signOut()
            }
            VoxieWatchBridge.shared.onSessionChanged = { token in
                model.acceptWatchSession(token)
            }
            VoxieWatchBridge.shared.onVolumeChanged = { volume in
                model.setPlaybackVolume(volume)
            }
            VoxieWatchBridge.shared.activate()
            model.start()
        }
        .onDisappear { model.stop() }
    }

    private var watchSetupPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 34))
                .foregroundStyle(voxieYellow)
            Text("STEL VOXIE IN OP IPHONE")
                .font(.headline)
                .foregroundStyle(voxieYellow)
                .multilineTextAlignment(.center)
            Text("Open Voxie op je iPhone en doorloop de installatie. De Watch wordt daarna via je iPhone gekoppeld.")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.black)
    }

    private var talkingPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Text("VOXIE").tracking(2)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(voxieYellow)
                    Spacer()
                    Circle().fill(model.available ? voxieYellow : .gray)
                        .frame(width: 8, height: 8)
                }

                if let selected = model.selected {
                    Button {
                        model.endSpeaking()
                        model.selectedFriendID = nil
                    } label: {
                        Label("Terug", systemImage: "chevron.left")
                            .font(.caption)
                    }
                    .tint(voxieYellow)
                    Text("PRATEN MET \(selected.name.uppercased())")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(voxieYellow)
                        .multilineTextAlignment(.center)
                    TalkPad()
                } else if model.friends.isEmpty {
                    Text("Veeg omhoog en nodig een vriend uit")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                } else {
                    Text("KIES EEN VRIEND")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.gray)
                    ForEach(model.friends) { friend in
                        Button {
                            model.selectedFriendID = friend.id
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(friend.available ? voxieYellow : .gray)
                                    .frame(width: 6, height: 6)
                                Text(friend.name).lineLimit(1)
                                Spacer(minLength: 2)
                                if model.selectedFriendID == friend.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.black)
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(7)
                            .foregroundStyle(.black)
                            .background(voxieYellow.opacity(friend.available ? 1 : 0.6),
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if model.selected == nil {
                  ForEach(model.pending) { friend in
                    HStack {
                        Image(systemName: "hourglass")
                        Text("@\(friend.name)").lineLimit(1)
                        Spacer()
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.gray)
                  }
                }
                Text(model.status)
                    .font(.system(size: 10))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.gray)
            }
            .padding(10)
        }
        .background(.black)
    }

    private var friendsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                Text("VRIENDEN")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(voxieYellow)
                Text(model.username.isEmpty ? "Kies je naam op iPhone" : "@\(model.username)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(voxieYellow)
                WatchInviteForm()
                if model.invitations.isEmpty {
                    Text("Geen openstaande verzoeken")
                        .font(.caption2).foregroundStyle(.gray)
                } else {
                    ForEach(model.invitations) { invitation in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("@\(invitation.name)")
                                .font(.system(size: 11, weight: .semibold))
                            HStack {
                                Button("Accepteer") {
                                    Task { await model.respond(invitation: invitation.id, accept: true) }
                                }
                                .tint(voxieYellow)
                                Button("Weiger") {
                                    Task { await model.respond(invitation: invitation.id, accept: false) }
                                }
                            }
                            .font(.system(size: 10))
                        }
                    }
                }
                if !model.friends.isEmpty {
                    Text("Vriend verwijderen")
                        .font(.system(size: 10, weight: .bold))
                    ForEach(model.friends) { friend in
                        Button(role: .destructive) {
                            Task { await model.removeFriend(friend.id) }
                        } label: {
                            Label(friend.name, systemImage: "minus.circle")
                                .lineLimit(1)
                        }
                        .font(.system(size: 11))
                    }
                }
                Toggle("Beschikbaar", isOn: Binding(
                    get: { model.available }, set: { model.setAvailable($0) }
                ))
                .tint(voxieYellow)
                .font(.system(size: 11))
                Text("Profiel en foto wijzig je op iPhone of iPad.")
                    .font(.system(size: 10)).foregroundStyle(.gray)
            }
            .padding(10)
        }
        .background(.black)
    }
}

private struct TalkPad: View {
    @EnvironmentObject private var model: VoxieV2Model
    @State private var holding = false

    var body: some View {
        ZStack {
            Circle().stroke(voxieYellow.opacity(0.3), lineWidth: 2)
                .frame(width: 122, height: 122)
            Circle().fill(holding ? voxieYellow.opacity(0.75) : voxieYellow)
                .frame(width: 110, height: 110)
            VStack(spacing: 5) {
                Image(systemName: holding ? "waveform" : "mic.fill")
                    .font(.system(size: 29, weight: .bold))
                Text(holding ? "OPNEMEN" : "HOUD VAST")
                    .font(.system(size: 10, weight: .black))
            }
            .foregroundStyle(.black)
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !holding else { return }
                holding = true
                model.beginSpeaking()
            }
            .onEnded { _ in
                holding = false
                model.endSpeaking()
            })
        .accessibilityLabel("Houd ingedrukt om op te nemen, laat los om te versturen")
    }
}

private struct WatchInviteForm: View {
    @EnvironmentObject private var model: VoxieV2Model
    @State private var handle = ""

    var body: some View {
        VStack(spacing: 5) {
            TextField("@gebruikersnaam", text: $handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 12))
            Button("Nodig uit") {
                Task { await model.invite(username: handle); handle = "" }
            }
            .tint(voxieYellow)
            .disabled(handle.isEmpty)
        }
    }
}
