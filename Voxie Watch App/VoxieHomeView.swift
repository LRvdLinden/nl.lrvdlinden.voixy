import SwiftUI

private let signalYellow = Color(red: 1, green: 0.85, blue: 0)

struct VoxieHomeView: View {
    @EnvironmentObject private var model: VoxieV2Model
    @State private var settings = false
    @State private var invites = false
    @State private var holding = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(signalYellow)
                        Text("VOXIE").tracking(2).font(.system(size: 13, weight: .black, design: .rounded))
                        Spacer()
                        Button { invites = true } label: { Image(systemName: "person.badge.plus") }
                            .buttonStyle(.plain)
                        Button { settings = true } label: { Image(systemName: "gearshape") }
                            .buttonStyle(.plain)
                    }

                    HStack {
                        Text(model.ready ? "JOUW CODE: \(model.code)" : "STEL JE PROFIEL IN")
                            .foregroundStyle(signalYellow)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Spacer()
                    }

                    Toggle("Beschikbaar", isOn: Binding(
                        get: { model.available }, set: { model.setAvailable($0) }
                    ))
                    .tint(signalYellow)
                    .font(.system(size: 11, weight: .semibold))

                    if model.friends.isEmpty {
                        Button("+ Nodig vriend uit") { invites = true }
                            .tint(signalYellow)
                            .foregroundStyle(.black)
                    } else {
                        VStack(spacing: 5) {
                            ForEach(model.friends) { friend in
                                Button {
                                    model.selectedFriendID = friend.id
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle().fill(friend.available ? signalYellow : .gray)
                                            .frame(width: 6, height: 6)
                                        Text(friend.name).lineLimit(1)
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer(minLength: 2)
                                        if model.selectedFriendID == friend.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(signalYellow)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(5)
                                .background(model.selectedFriendID == friend.id ? signalYellow.opacity(0.16) : .white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }

                    Text(model.status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                        .frame(height: 28)

                    ZStack {
                        Circle().stroke(signalYellow.opacity(0.35), lineWidth: 2)
                            .frame(width: 124, height: 124)
                        Circle().fill(holding ? signalYellow.opacity(0.75) : signalYellow)
                            .frame(width: 110, height: 110)
                        VStack(spacing: 4) {
                            Image(systemName: holding ? "waveform" : "mic.fill")
                                .font(.system(size: 30, weight: .bold))
                            Text(holding ? "OPNEMEN" : "HOUD VAST")
                                .font(.system(size: 9, weight: .black, design: .rounded))
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
                .padding(.horizontal, 9)
            }
        }
        .sheet(isPresented: $settings) { VoxieSettingsView() }
        .sheet(isPresented: $invites) { VoxieFriendsView() }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

private struct VoxieSettingsView: View {
    @EnvironmentObject private var model: VoxieV2Model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        Form {
            TextField("Jouw naam", text: $name)
            Text("Supabase-verbinding ingesteld")
                .font(.footnote)
            Button("Verbind") {
                Task { await model.configure(server: model.server, name: name); dismiss() }
            }
            .tint(signalYellow)
        }
        .onAppear { name = model.name }
    }
}

private struct VoxieFriendsView: View {
    @EnvironmentObject private var model: VoxieV2Model
    @State private var friendCode = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("VRIENDEN")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(signalYellow)
                Text("Jouw uitnodigingscode")
                    .font(.system(size: 11))
                Text(model.code.isEmpty ? "Nog niet geregistreerd" : model.code)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(signalYellow)

                TextField("Code van vriend", text: $friendCode)
                Button("Verstuur uitnodiging") {
                    Task { await model.invite(code: friendCode); friendCode = "" }
                }
                .tint(signalYellow)

                ForEach(model.invitations) { invitation in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(invitation.name) nodigt je uit")
                        HStack {
                            Button("Accepteer") {
                                Task { await model.respond(invitation: invitation.id, accept: true) }
                            }.tint(signalYellow)
                            Button("Weiger") {
                                Task { await model.respond(invitation: invitation.id, accept: false) }
                            }
                        }
                    }
                }
                Text(model.status).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .background(.black)
    }
}
