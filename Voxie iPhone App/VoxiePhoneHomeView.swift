import SwiftUI
import PhotosUI
import UIKit

private enum Palette {
    static let yellow = Color(red: 1, green: 0.85, blue: 0)
    static let charcoal = Color(red: 0.09, green: 0.09, blue: 0.10)
}

struct VoxiePhoneHomeView: View {
    @EnvironmentObject private var model: VoxieV2Model
    @Environment(\.scenePhase) private var scenePhase
    @State private var showFriends = false
    @State private var showSettings = false
    @State private var holding = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !model.ready {
                VoxieSignInView()
            } else if !model.hasLoadedProfile {
                ProgressView("Profiel laden…")
                    .tint(Palette.yellow)
            } else if model.username.isEmpty {
                PhoneSettingsSheet(onboarding: true)
            } else {
              ScrollView {
                VStack(spacing: 20) {
                    header
                    profileCard
                    friendsList
                    talkButton
                    Text(model.status)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Text("Houd de knop ingedrukt om op te nemen. Laat los om te verzenden.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
              }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFriends) { PhoneFriendsSheet() }
        .sheet(isPresented: $showSettings) { PhoneSettingsSheet() }
        .onAppear { if model.ready { model.start() } }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.start()
            case .inactive, .background:
                holding = false
                model.endSpeaking()
                model.stop()
            @unknown default: break
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VOXIE")
                    .tracking(3)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                Text("WALKIETALKIE")
                    .tracking(2)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Palette.yellow)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.yellow)
                    .frame(width: 42, height: 42)
                    .background(Palette.charcoal, in: Circle())
            }
            .accessibilityLabel("Instellingen")
        }
    }

    private var profileCard: some View {
        HStack {
            if let avatar = model.avatarBase64,
               let data = Data(base64Encoded: avatar),
               let picture = UIImage(data: data) {
                Image(uiImage: picture)
                    .resizable().scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("JOUW GEBRUIKERSNAAM")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.58))
                Text(model.username.isEmpty ? "Nog geen naam" : "@\(model.username)")
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundStyle(Palette.yellow)
            }
            Spacer()
            Toggle("Beschikbaar", isOn: Binding(
                get: { model.available }, set: { model.setAvailable($0) }
            ))
            .labelsHidden()
            .tint(Palette.yellow)
        }
        .padding(18)
        .background(Palette.charcoal, in: RoundedRectangle(cornerRadius: 18))
    }

    private var friendsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("VRIENDEN")
                    .font(.system(.headline, design: .rounded, weight: .black))
                Spacer()
                Button { showFriends = true } label: {
                    Label("Uitnodigen", systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.bold))
                }
                .tint(Palette.yellow)
            }
            if model.friends.isEmpty {
                Button { showFriends = true } label: {
                    Label("Voeg je eerste vriend toe", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .foregroundStyle(Palette.yellow)
                .background(Palette.charcoal, in: RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(model.friends) { friend in
                    HStack(spacing: 4) {
                     Button { model.selectedFriendID = friend.id } label: {
                        HStack(spacing: 12) {
                            if let encoded = friend.avatar,
                               let data = Data(base64Encoded: encoded),
                               let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            }
                            Circle()
                                .fill(friend.available ? Palette.yellow : .gray)
                                .frame(width: 10, height: 10)
                            Text(friend.name)
                                .font(.body.weight(.semibold))
                            Spacer()
                            if model.selectedFriendID == friend.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Palette.yellow)
                            }
                        }
                        .padding(15)
                        .background(Palette.charcoal, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(model.selectedFriendID == friend.id ? Palette.yellow : .clear, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                     Button(role: .destructive) {
                         Task { await model.removeFriend(friend.id) }
                     } label: {
                         Image(systemName: "minus.circle")
                             .foregroundStyle(.red)
                             .padding(8)
                     }
                     .accessibilityLabel("Verwijder \(friend.name)")
                    }
                }
            }
        }
    }

    private var talkButton: some View {
        VStack(spacing: 12) {
            Text(model.selected.map { "PRATEN MET \($0.name.uppercased())" } ?? "KIES EEN VRIEND")
                .font(.caption.weight(.black))
                .tracking(1.8)
                .foregroundStyle(Palette.yellow)

            ZStack {
                Circle()
                    .stroke(Palette.yellow.opacity(0.25), lineWidth: 2)
                    .frame(width: 254, height: 254)
                Circle()
                    .fill(holding ? Palette.yellow.opacity(0.72) : Palette.yellow)
                    .frame(width: 220, height: 220)
                VStack(spacing: 9) {
                    Image(systemName: holding ? "waveform" : "mic.fill")
                        .font(.system(size: 58, weight: .heavy))
                    Text(holding ? "OPNEMEN" : "HOUD VAST")
                        .tracking(2)
                        .font(.system(size: 17, weight: .black, design: .rounded))
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
            .accessibilityLabel("Houd vast om te praten en laat los om te verzenden")
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PhoneSettingsSheet: View {
    @EnvironmentObject private var model: VoxieV2Model
    @Environment(\.dismiss) private var dismiss
    var onboarding = false
    @State private var handle = ""
    @State private var photo: PhotosPickerItem?
    @State private var isSaving = false
    @State private var feedback = ""
    @State private var savingDelivery = false
    @State private var showDeleteConfirmation = false
    @State private var deletingAccount = false

    var body: some View {
        NavigationStack {
            Form {
                if onboarding {
                    Section {
                        Label("Welkom bij Voxie", systemImage: "waveform")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.yellow)
                        Text("Stel Voxie één keer in op je iPhone of iPad. Kies een unieke gebruikersnaam om vrienden te kunnen uitnodigen.")
                    }
                }
                Section("Jouw profiel") {
                    TextField("Unieke gebruikersnaam", text: $handle)
                        .textContentType(.nickname)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Gebruikersnaam opslaan") {
                        Task {
                            isSaving = true
                            let saved = await model.updateUsername(handle)
                            feedback = saved ? "Gebruikersnaam opgeslagen als @\(model.username) ✓" : model.status
                            isSaving = false
                        }
                    }
                    .tint(Palette.yellow)
                    .disabled(isSaving || handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if isSaving { ProgressView("Opslaan…") }
                    if !feedback.isEmpty {
                        Text(feedback)
                            .font(.footnote)
                            .foregroundStyle(feedback.contains("✓") ? .green : .orange)
                    }
                }
                Section("Profielfoto") {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Kies een profielfoto", systemImage: "photo.on.rectangle")
                    }
                    .tint(Palette.yellow)
                }
                Section("Berichten ontvangen op") {
                    Picker("Ontvangst", selection: Binding(
                        get: { model.deliveryTarget },
                        set: { choice in
                            savingDelivery = true
                            Task {
                                let saved = await model.updateDeliveryTarget(choice)
                                feedback = saved ? "Ontvangst opgeslagen ✓" : model.status
                                savingDelivery = false
                            }
                        }
                    )) {
                        Text("Alleen Apple Watch").tag("watch")
                        Text("Alleen iPhone/iPad").tag("phone")
                        Text("Beide apparaten").tag("both")
                    }
                    .disabled(savingDelivery)
                    Text("Bepaalt waar inkomende spraak wordt afgespeeld zolang Voxie actief is.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("Je vrienden en profiel worden via je Apple-account op iPhone, iPad en Apple Watch gesynchroniseerd. De Watch heeft geen aparte profielinstellingen.")
                        .font(.footnote)
                }
                Section { Button("Log uit", role: .destructive) { model.signOut(); dismiss() } }
                Section {
                    Button("Account en gegevens verwijderen", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(deletingAccount)
                    Text("Dit verwijdert je gebruikersnaam, profielfoto, uitnodigingen, vrienden, spraakframes en aanmeldsessies definitief van de Voxie-server. Verwijder daarna eventueel de app van je apparaten.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(onboarding ? "Voxie instellen" : "Instellingen")
            .toolbar {
                if !onboarding {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Gereed") { dismiss() }
                    }
                }
            }
            .onAppear { handle = model.username }
            .onChange(of: photo) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        feedback = "De gekozen foto kon niet worden gelezen."
                        return
                    }
                    isSaving = true
                    feedback = "Profielfoto uploaden…"
                    let size = CGSize(width: 256, height: 256)
                    let rendered = UIGraphicsImageRenderer(size: size).image { _ in
                        let side = min(image.size.width, image.size.height)
                        let rect = CGRect(x: (size.width-image.size.width*size.width/side)/2,
                                          y: (size.height-image.size.height*size.height/side)/2,
                                          width: image.size.width*size.width/side,
                                          height: image.size.height*size.height/side)
                        image.draw(in: rect)
                    }
                    if let jpeg = rendered.jpegData(compressionQuality: 0.55) {
                        let saved = await model.updateAvatar(jpeg)
                        feedback = saved ? "Profielfoto opgeslagen ✓" : model.status
                    } else {
                        feedback = "De foto kon niet worden verwerkt."
                    }
                    isSaving = false
                }
            }
            .confirmationDialog("Voxie-account definitief verwijderen?",
                                isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Verwijder mijn account en alle gegevens", role: .destructive) {
                    Task {
                        deletingAccount = true
                        let deleted = await model.deleteAccount()
                        deletingAccount = false
                        if deleted { dismiss() }
                        else { feedback = model.status }
                    }
                }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("Dit is definitief en kan niet ongedaan gemaakt worden.")
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct PhoneFriendsSheet: View {
    @EnvironmentObject private var model: VoxieV2Model
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Jouw code") {
                    Text(model.username.isEmpty ? "Kies eerst een gebruikersnaam" : "@\(model.username)")
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(Palette.yellow)
                    if !model.username.isEmpty {
                        ShareLink(item: "@\(model.username)") { Label("Deel gebruikersnaam", systemImage: "square.and.arrow.up") }
                    }
                }
                Section("Vriend uitnodigen") {
                    TextField("@gebruikersnaam", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Verstuur uitnodiging") {
                        Task { await model.invite(username: code); code = "" }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !model.invitations.isEmpty {
                    Section("Ontvangen uitnodigingen") {
                        ForEach(model.invitations) { invitation in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(invitation.name)
                                HStack {
                                    Button("Accepteer") {
                                        Task { await model.respond(invitation: invitation.id, accept: true) }
                                    }
                                    Button("Weiger", role: .destructive) {
                                        Task { await model.respond(invitation: invitation.id, accept: false) }
                                    }
                                }
                            }
                        }
                    }
                }
                if !model.pending.isEmpty {
                    Section("Uitgenodigde vrienden") {
                        ForEach(model.pending) { friend in
                            Label("@\(friend.name)", systemImage: "hourglass")
                                .foregroundStyle(.gray)
                        }
                    }
                }
                Section("Status") { Text(model.status).font(.footnote) }
            }
            .navigationTitle("Vrienden")
        }
        .preferredColorScheme(.dark)
    }
}
