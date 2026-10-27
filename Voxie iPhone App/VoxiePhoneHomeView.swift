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
    @State private var showTalk = false
    @State private var holding = false
    @State private var handlingInvitationID: Int?
    @State private var invitationFeedback = ""
    @State private var onboardingActive = VoxieCredentialStore.load() == nil
    @State private var onboardingStep = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !model.ready || onboardingActive || (model.hasLoadedProfile && model.username.isEmpty) {
                PhoneOnboardingFlow(step: $onboardingStep) {
                    onboardingActive = false
                    synchronizeWatch()
                }
            } else if !model.hasLoadedProfile {
                ProgressView("Profiel laden…")
                    .tint(Palette.yellow)
            } else {
              ScrollView {
                VStack(spacing: 20) {
                    header
                    profileCard
                    incomingInvitations
                    friendsList
                    if model.status != "Log in met Apple" {
                        Text(model.status)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 22)
              }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFriends) { PhoneFriendsSheet() }
        .sheet(isPresented: $showSettings) { PhoneSettingsSheet() }
        .confirmationDialog("Vriendschapsverzoek sturen?",
                            isPresented: Binding(
                                get: { model.ready && model.hasLoadedProfile && !model.username.isEmpty && model.pendingProfileUsername != nil },
                                set: { if !$0 { model.pendingProfileUsername = nil } }
                            ), titleVisibility: .visible) {
            Button("Verstuur vriendschapsverzoek") {
                guard let handle = model.pendingProfileUsername else { return }
                model.pendingProfileUsername = nil
                Task { await model.invite(username: handle) }
            }
            Button("Annuleren", role: .cancel) { model.pendingProfileUsername = nil }
        } message: {
            Text("Wil je @\(model.pendingProfileUsername ?? "deze persoon") uitnodigen als vriend op Voxie? Deze persoon moet je verzoek daarna nog accepteren.")
        }
        .sheet(isPresented: $showTalk) {
            NavigationStack {
                ScrollView {
                    talkButton
                        .padding(.top, 30)
                        .padding(.horizontal, 20)
                }
                .background(.black)
                .navigationTitle(model.selected?.name ?? "Praten")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Gereed") { showTalk = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .onDisappear { model.endSpeaking() }
        }
        .onAppear {
            VoxieWatchBridge.shared.activate()
            if model.ready { model.start() }
            if model.ready && model.hasLoadedProfile && !model.username.isEmpty { synchronizeWatch() }
        }
        .onChange(of: model.hasLoadedProfile) { _, loaded in
            if loaded && model.username.isEmpty { onboardingActive = true }
            if loaded && !model.username.isEmpty && onboardingActive && onboardingStep <= 3 {
                // Existing Apple account on a newly installed device: setup already done.
                onboardingActive = false
            }
            if loaded && !model.username.isEmpty && !onboardingActive { synchronizeWatch() }
        }
        .onChange(of: model.ready) { _, ready in
            if ready && onboardingStep == 2 { onboardingStep = 3 }
            if !ready {
                onboardingActive = true
                onboardingStep = 0
                VoxieWatchBridge.shared.publish(token: nil)
            }
        }
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

    private func synchronizeWatch() {
        Task {
            if let token = await model.createWatchSession() {
                VoxieWatchBridge.shared.publish(token: token)
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
                if !model.username.isEmpty {
                    ShareLink(item: URL(string: "https://voxie.online/u/\(model.username)")!) {
                        Label("Deel je profiel", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(Palette.yellow)
                }
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
                     Button {
                         model.selectedFriendID = friend.id
                         showTalk = true
                     } label: {
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

    @ViewBuilder
    private var incomingInvitations: some View {
        if !model.invitations.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundStyle(.black)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VRIENDSCHAPSVERZOEKEN")
                            .font(.system(.headline, design: .rounded, weight: .black))
                            .foregroundStyle(.black)
                        Text("\(model.invitations.count) ontvangen")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.black.opacity(0.75))
                    }
                    Spacer()
                }
                ForEach(model.invitations) { invitation in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("@\(invitation.name) wil jouw vriend worden")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.black)
                        HStack(spacing: 12) {
                            Button {
                                handleInvitation(invitation.id, accept: true)
                            } label: {
                                Label("Accepteren", systemImage: "checkmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.black)
                            Button {
                                handleInvitation(invitation.id, accept: false)
                            } label: {
                                Text("Weigeren").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.black)
                        }
                        .disabled(handlingInvitationID != nil)
                        if handlingInvitationID == invitation.id {
                            ProgressView("Verzoek verwerken…")
                                .tint(.black)
                        }
                    }
                    .padding(14)
                    .background(.black.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                }
                if !invitationFeedback.isEmpty {
                    Text(invitationFeedback)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                }
            }
            .padding(18)
            .background(Palette.yellow, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
        } else if !invitationFeedback.isEmpty {
            Text(invitationFeedback)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func handleInvitation(_ id: Int, accept: Bool) {
        guard handlingInvitationID == nil else { return }
        handlingInvitationID = id
        invitationFeedback = ""
        Task {
            let saved = await model.respond(invitation: id, accept: accept)
            invitationFeedback = saved
                ? (accept ? "Vriendschapsverzoek geaccepteerd. Je vriend staat nu bij Vrienden." : "Vriendschapsverzoek geweigerd.")
                : model.status
            handlingInvitationID = nil
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

private struct PhoneOnboardingFlow: View {
    @EnvironmentObject private var model: VoxieV2Model
    @Binding var step: Int
    let onFinish: () -> Void

    @State private var introPage = 0
    @State private var handle = ""
    @State private var photo: PhotosPickerItem?
    @State private var avatarFeedback = ""
    @State private var feedback = ""
    @State private var busy = false
    @State private var selectedDelivery = "both"

    var body: some View {
        VStack(spacing: 18) {
            if step != 2 {
                Text("VOXIE")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(Palette.yellow)
                    .padding(.top, 25)
            }
            Group {
                switch step {
                case 0, 1: welcome
                case 2: VoxieSignInView()
                case 3: usernameStep
                case 4: photoStep
                case 5: deliveryStep
                default: finishStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if step != 2 {
                Text("\(min(step + 1, 7)) / 7")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.gray)
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 22)
        .background(.black)
        .preferredColorScheme(.dark)
        .onAppear {
            handle = model.username
            selectedDelivery = model.deliveryTarget
            if model.ready && step < 3 { step = 3 }
        }
        .onChange(of: model.ready) { _, ready in
            if ready && step == 2 { step = 3 }
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            TabView(selection: $introPage) {
                VStack(spacing: 24) {
                    Image(systemName: "waveform")
                        .font(.system(size: 90, weight: .bold))
                        .foregroundStyle(Palette.yellow)
                    Text("Welkom bij Voxie")
                        .font(.largeTitle.bold())
                    Text("Praat direct met je vrienden via iPhone, iPad of Apple Watch.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Text("Veeg naar links")
                        .font(.footnote).foregroundStyle(Palette.yellow)
                }.tag(0)
                VStack(spacing: 22) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 76))
                        .foregroundStyle(Palette.yellow)
                    Text("Houd vast om te praten")
                        .font(.title.bold())
                    Text("Nodig eerst vrienden uit. Kies daarna een vriend, houd de knop ingedrukt en laat los om je spraak te verzenden.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Button(introPage == 0 ? "Volgende" : "Log in met Apple") {
                if introPage == 0 { introPage = 1 }
                else { step = 2 }
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.yellow)
            .foregroundStyle(.black)
            .controlSize(.large)
        }
    }

    private var usernameStep: some View {
        VStack(spacing: 22) {
            Text("Kies je gebruikersnaam")
                .font(.title.bold())
            Text("Je vrienden kunnen je vinden met deze unieke naam.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("Gebruikersnaam", text: $handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.nickname)
                .padding(15)
                .background(Palette.charcoal, in: RoundedRectangle(cornerRadius: 14))
            Button("Gebruikersnaam opslaan") {
                Task {
                    busy = true
                    let saved = await model.updateUsername(handle)
                    feedback = saved ? "Opgeslagen ✓" : model.status
                    busy = false
                    if saved { step = 4 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.yellow)
            .foregroundStyle(.black)
            .disabled(busy || handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text(feedback).font(.footnote).foregroundStyle(.orange)
        }
    }

    private var photoStep: some View {
        VStack(spacing: 22) {
            Text("Jouw profielfoto")
                .font(.title.bold())
            Text("Voeg een foto toe zodat vrienden je herkennen. Je kunt dit ook later doen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let encoded = model.avatarBase64,
               let data = Data(base64Encoded: encoded),
               let picture = UIImage(data: data) {
                Image(uiImage: picture)
                    .resizable().scaledToFill()
                    .frame(width: 128, height: 128)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 115))
                    .foregroundStyle(Palette.yellow)
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Kies profielfoto", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.yellow)
            .foregroundStyle(.black)
            Text(avatarFeedback).font(.footnote).foregroundStyle(.orange)
            Button(model.avatarBase64 == nil ? "Overslaan" : "Verder") { step = 5 }
                .disabled(busy)
                .foregroundStyle(Palette.yellow)
        }
        .onChange(of: photo) { _, selected in
            Task {
                busy = true
                guard let data = try? await selected?.loadTransferable(type: Data.self),
                      let picture = UIImage(data: data) else {
                    avatarFeedback = "Foto kon niet worden geladen"
                    busy = false
                    return
                }
                let size = CGSize(width: 256, height: 256)
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    let scale = max(size.width / picture.size.width, size.height / picture.size.height)
                    let width = picture.size.width * scale
                    let height = picture.size.height * scale
                    picture.draw(in: CGRect(x: (size.width-width)/2, y: (size.height-height)/2,
                                            width: width, height: height))
                }
                if let jpeg = image.jpegData(compressionQuality: 0.5) {
                    let saved = await model.updateAvatar(jpeg)
                    avatarFeedback = saved ? "Foto opgeslagen ✓" : model.status
                }
                busy = false
            }
        }
    }

    private var deliveryStep: some View {
        VStack(spacing: 22) {
            Text("Waar wil je spraak ontvangen?")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            ForEach(["watch", "phone", "both"], id: \.self) { choice in
                Button {
                    selectedDelivery = choice
                } label: {
                    HStack {
                        Text(deliveryLabel(choice))
                        Spacer()
                        Image(systemName: selectedDelivery == choice ? "checkmark.circle.fill" : "circle")
                    }
                    .padding(16)
                    .background(Palette.charcoal, in: RoundedRectangle(cornerRadius: 14))
                }
                .foregroundStyle(selectedDelivery == choice ? Palette.yellow : .white)
            }
            Button("Keuze opslaan") {
                Task {
                    busy = true
                    let saved = await model.updateDeliveryTarget(selectedDelivery)
                    feedback = saved ? "" : model.status
                    busy = false
                    if saved { step = 6 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.yellow)
            .foregroundStyle(.black)
            .disabled(busy)
            Text(feedback).font(.footnote).foregroundStyle(.orange)
        }
    }

    private func deliveryLabel(_ value: String) -> String {
        switch value {
        case "watch": return "Alleen Apple Watch"
        case "phone": return "Alleen iPhone/iPad"
        default: return "Beide apparaten"
        }
    }

    private var finishStep: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 95))
                .foregroundStyle(Palette.yellow)
            Text("Voxie is ingesteld!")
                .font(.largeTitle.bold())
            Text("Je kunt nu vrienden uitnodigen. Ook je Apple Watch wordt via je iPhone gekoppeld.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start Voxie") { onFinish() }
                .buttonStyle(.borderedProminent)
                .tint(Palette.yellow)
                .foregroundStyle(.black)
                .controlSize(.large)
        }
    }
}

private struct PhoneSettingsSheet: View {
    @EnvironmentObject private var model: VoxieV2Model
    @Environment(\.dismiss) private var dismiss
    var onboarding = false
    var onSetupComplete: () -> Void = {}
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
                if onboarding {
                    Section {
                        Button("Start Voxie") { onSetupComplete() }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .tint(Palette.yellow)
                            .disabled(model.username.isEmpty || isSaving || savingDelivery)
                        Text("Sla eerst je gebruikersnaam op en kies hierboven waar je spraak wilt ontvangen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
                        ShareLink(item: URL(string: "https://voxie.online/u/\(model.username)")!) {
                            Label("Deel profiellink", systemImage: "square.and.arrow.up")
                        }
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
