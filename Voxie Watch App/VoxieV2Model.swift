import AVFoundation
import Foundation
import UserNotifications
import SwiftUI

struct VoxieFriend: Decodable, Identifiable {
    let id: String
    let name: String
    let available: Bool
    let username: String?
    let avatar: String?
}

struct VoxieInvitation: Decodable, Identifiable {
    let id: Int
    let name: String
}
struct VoxiePendingFriend: Decodable, Identifiable {
    let id: String
    let name: String
}

private struct AppleNonceReply: Decodable { let nonce: String }
private struct WatchSessionReply: Decodable { let token: String }
private struct AppleLoginReply: Decodable {
    let id: String; let token: String; let code: String
    let username: String?; let avatar: String?; let deliveryTarget: String?
}
private struct ProfileReply: Decodable {
    let ok: Bool; let username: String?; let avatar: String?; let deliveryTarget: String?
}
private struct StateReply: Decodable {
    let id: String
    let code: String
    let friends: [VoxieFriend]
    let pending: [VoxiePendingFriend]
    let invitations: [VoxieInvitation]
    let username: String?
    let avatar: String?
    let deliveryTarget: String?
}
private struct FrameReply: Decodable { let frames: [VoxieFrame] }
private struct VoxieFrame: Decodable { let id: Int; let sender: String; let pcm: String }
private struct Body: Encodable { let name: String?; let code: String?; let available: Bool? }

@MainActor
final class VoxieV2Model: ObservableObject {
    @Published var server = SupabaseConfiguration.functionURL
    @Published private(set) var username = ""
    @Published private(set) var hasLoadedProfile = false
    @Published private(set) var avatarBase64: String?
    @Published private(set) var deliveryTarget = "both"
    @Published var pendingProfileUsername: String?
    @Published private(set) var code = ""
    @Published private(set) var status = "Log in met Apple"
    @Published private(set) var friends: [VoxieFriend] = []
    @Published private(set) var pending: [VoxiePendingFriend] = []
    @Published private(set) var invitations: [VoxieInvitation] = []
    @Published var selectedFriendID: String?
    @Published private(set) var available = UserDefaults.standard.object(forKey: "v2.available") as? Bool ?? true
    @Published private(set) var playbackVolume = UserDefaults.standard.object(forKey: "voxie.playbackVolume") as? Double ?? 1.0
    @Published private(set) var isSpeaking = false
    @Published private(set) var isSending = false

    private var identity = ""
    private var token = VoxieCredentialStore.load() ?? ""
    private var refreshTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var transmitTask: Task<Void, Never>?
    private var cursor = 0
    private let audio = LiveAudio()
    private var outgoing: [Data] = []
    private var holding = false
    private var pushToken: String?
    private var maxRecordingTask: Task<Void, Never>?

    init() {
        audio.setPlaybackVolume(Float(playbackVolume))
    }

    var ready: Bool { !token.isEmpty && server.hasPrefix("https://") }
    var selected: VoxieFriend? { friends.first { $0.id == selectedFriendID } }

    func setError(_ message: String) { status = message }

    func requestAppleNonce() async -> String? {
        do {
            var request = try makeRequest("/v3/nonce", method: "POST", authenticated: false)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response)
            return try JSONDecoder().decode(AppleNonceReply.self, from: data).nonce
        } catch {
            status = "Kan niet verbinden. Controleer je internetverbinding."
            return nil
        }
    }

    func finishAppleSignIn(identityToken: String, nonce: String) async {
        do {
            var request = try makeRequest("/v3/apple", method: "POST", authenticated: false)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = try JSONSerialization.data(withJSONObject: ["identityToken": identityToken, "nonce": nonce])
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            try validate(response)
            let result = try JSONDecoder().decode(AppleLoginReply.self, from: data)
            token = result.token; identity = result.id; code = result.code
            username = result.username ?? ""; avatarBase64 = result.avatar
            deliveryTarget = result.deliveryTarget ?? "both"
            hasLoadedProfile = true
            VoxieCredentialStore.save(token)
            status = username.isEmpty ? "Kies je gebruikersnaam op iPhone/iPad" : "Verbonden als @\(username)"
            if let pushToken { await uploadPushToken(pushToken) }
            start()
        } catch { status = "Aanmelden: \(error.localizedDescription)" }
    }

    func updateUsername(_ value: String) async -> Bool {
        let handle = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "@", with: "")
        guard handle.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil else {
            status = "Gebruik 3–20 letters, cijfers of _"; return false
        }
        do {
            let reply: ProfileReply = try await sendJSONObject("/v3/profile", value: ["username": handle])
            username = reply.username ?? handle
            status = "Verbonden als @\(username)"
            return true
        } catch { status = error.localizedDescription; return false }
    }

    func updateAvatar(_ jpeg: Data) async -> Bool {
        guard jpeg.count <= 80000 else { status = "Foto is te groot"; return false }
        do {
            let reply: ProfileReply = try await sendJSONObject("/v3/profile", value: ["avatar": jpeg.base64EncodedString()])
            avatarBase64 = reply.avatar
            status = "Profielfoto opgeslagen"
            return true
        } catch { status = error.localizedDescription; return false }
    }

    func updateDeliveryTarget(_ value: String) async -> Bool {
        guard ["watch", "phone", "both"].contains(value) else { return false }
        do {
            let reply: ProfileReply = try await sendJSONObject("/v3/profile", value: ["deliveryTarget": value])
            deliveryTarget = reply.deliveryTarget ?? value
            status = "Ontvangst ingesteld"
            return true
        } catch { status = "Ontvangst: \(error.localizedDescription)"; return false }
    }

    #if os(iOS)
    func createWatchSession() async -> String? {
        guard ready, !username.isEmpty else { return nil }
        do {
            let result: WatchSessionReply = try await sendJSONObject("/v3/watch-session", value: [:])
            return result.token
        } catch {
            status = "Watch-koppeling: \(error.localizedDescription)"
            return nil
        }
    }
    #endif

    #if os(watchOS)
    func acceptWatchSession(_ pairedToken: String?) {
        guard let pairedToken, pairedToken.count == 64 else {
            signOut()
            return
        }
        guard token != pairedToken else { return }
        stop()
        token = pairedToken
        VoxieCredentialStore.save(pairedToken)
        UserDefaults.standard.set(true, forKey: "voxie.watchPairedViaPhone")
        hasLoadedProfile = false
        status = "Profiel ophalen van iPhone…"
        start()
    }
    #endif

    func signOut() {
        stop(); VoxieCredentialStore.clear(); token = ""; identity = ""
        #if os(watchOS)
        UserDefaults.standard.removeObject(forKey: "voxie.watchPairedViaPhone")
        #endif
        username = ""; avatarBase64 = nil; deliveryTarget = "both"
        pendingProfileUsername = nil
        hasLoadedProfile = false; code = ""; friends = []; pending = []; invitations = []
        selectedFriendID = nil; status = "Log in met Apple"
    }

    func openSharedProfile(_ url: URL) {
        let handle: String
        if url.scheme?.lowercased() == "https", url.host?.lowercased() == "voxie.online",
           url.pathComponents.count == 3, url.pathComponents[1] == "u" {
            handle = url.pathComponents[2]
        } else if url.scheme?.lowercased() == "voxie", url.host?.lowercased() == "u",
                  url.pathComponents.count == 2 {
            handle = url.pathComponents[1]
        } else { return }
        guard handle.range(of: "^[a-zA-Z0-9_]{3,20}$", options: .regularExpression) != nil else { return }
        pendingProfileUsername = handle.lowercased()
    }

    func deleteAccount() async -> Bool {
        guard ready else { return false }
        do {
            let request = try makeRequest("/v3/account", method: "DELETE")
            let (_, response) = try await URLSession.shared.data(for: request)
            try validate(response)
            signOut()
            return true
        } catch {
            status = "Account verwijderen: \(error.localizedDescription)"
            return false
        }
    }

    func start() {
        guard ready, refreshTask == nil else { return }
        if !available { setAvailable(false) }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        audioTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.receiveFrames()
                try? await Task.sleep(for: .milliseconds(220))
            }
        }
        transmitTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.flushAudio()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() {
        refreshTask?.cancel(); audioTask?.cancel(); transmitTask?.cancel()
        refreshTask = nil; audioTask = nil; transmitTask = nil
        audio.stopCapture(); isSpeaking = false; outgoing.removeAll()
        maxRecordingTask?.cancel(); maxRecordingTask = nil
        isSending = false
    }

    func invite(username: String) async {
        do {
            let _: OkReply = try await sendJSONObject("/v3/invite", value: ["username": username])
            status = "Uitnodiging verstuurd"; await refresh()
        } catch { status = "Uitnodigen: \(error.localizedDescription)" }
    }

    func removeFriend(_ id: String) async {
        do {
            let _: OkReply = try await sendJSONObject("/v3/friends/\(id)/remove", value: [:])
            if selectedFriendID == id { selectedFriendID = nil }
            await refresh()
        } catch { status = "Verwijderen: \(error.localizedDescription)" }
    }

    func uploadPushToken(_ pushToken: String) async {
        self.pushToken = pushToken
        guard ready else { return }
        do {
            var request = try makeRequest("/v2/device", method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = try JSONSerialization.data(withJSONObject: ["token": pushToken])
            let (_, response) = try await URLSession.shared.upload(for: request, from: body)
            try validate(response)
        } catch { /* notification support is optional; foreground calling still works */ }
    }

    @discardableResult
    func respond(invitation: Int, accept: Bool) async -> Bool {
        do {
            let path = "/v2/invitations/\(invitation)/" + (accept ? "accept" : "decline")
            let _: OkReply = try await send(path, body: Body(name: nil, code: nil, available: nil))
            status = accept ? "Vriend toegevoegd" : "Uitnodiging geweigerd"
            await refresh()
            return true
        } catch {
            status = "Vriendschapsverzoek: \(error.localizedDescription)"
            await refresh()
            return false
        }
    }

    func setAvailable(_ value: Bool) {
        available = value
        UserDefaults.standard.set(value, forKey: "v2.available")
        if !value { endSpeaking() }
        Task {
            do { let _: OkReply = try await send("/v2/presence", body: Body(name: nil, code: nil, available: value)) }
            catch { status = "Status: \(error.localizedDescription)" }
        }
    }

    func setPlaybackVolume(_ value: Double) {
        playbackVolume = min(1, max(0.1, value))
        UserDefaults.standard.set(playbackVolume, forKey: "voxie.playbackVolume")
        audio.setPlaybackVolume(Float(playbackVolume))
        #if os(iOS)
        VoxieWatchBridge.shared.publishVolume(playbackVolume)
        #endif
    }

    func beginSpeaking() {
        guard let friend = selected, ready, available, friend.available else {
            status = "Selecteer een beschikbare vriend"; return
        }
        guard !isSpeaking, !isSending else { return }
        holding = true
        Task {
            let permission = await AVAudioApplication.requestRecordPermission()
            guard permission else { status = "Geef toegang tot microfoon"; return }
            guard holding else { return }
            do {
                try audio.startCapture { [weak self] pcm in
                    Task { @MainActor [weak self] in self?.outgoing.append(pcm) }
                }
                isSpeaking = true
                status = "Neem op voor \(friend.name)…"
                maxRecordingTask?.cancel()
                maxRecordingTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled else { return }
                    self?.endSpeaking()
                }
            } catch { status = "Microfoon: \(error.localizedDescription)" }
        }
    }

    func endSpeaking() {
        holding = false
        maxRecordingTask?.cancel(); maxRecordingTask = nil
        audio.stopCapture()
        let hadSpeech = isSpeaking
        isSpeaking = false
        if hadSpeech { status = "Versturen…" }
    }

    private func refresh() async {
        guard ready else { return }
        do {
            let result: StateReply = try await get("/v2/state")
            code = result.code
            username = result.username ?? ""
            avatarBase64 = result.avatar
            deliveryTarget = result.deliveryTarget ?? "both"
            hasLoadedProfile = true
            friends = result.friends
            pending = result.pending
            invitations = result.invitations
            if status == "Log in met Apple" || status == "Profiel ophalen van iPhone…" {
                status = username.isEmpty ? "Rond je profiel af op iPhone/iPad" : "Verbonden als @\(username)"
            }
            if let id = selectedFriendID, !friends.contains(where: { $0.id == id }) { selectedFriendID = nil }
        } catch VoxieError.unauthorized {
            signOut()
        } catch { status = "Netwerk: \(error.localizedDescription)" }
    }

    private func receiveFrames() async {
        guard ready else { return }
        do {
            #if os(watchOS)
            let device = "watch"
            #else
            let device = "phone"
            #endif
            let response: FrameReply = try await get("/v2/frames?after=\(cursor)&device=\(device)")
            for frame in response.frames {
                cursor = max(cursor, frame.id)
                guard available, !isSpeaking, frame.sender == selectedFriendID,
                      let data = Data(base64Encoded: frame.pcm) else { continue }
                let playedID = frame.id
                try audio.play(data) { [weak self] in
                    Task { @MainActor [weak self] in
                        await self?.acknowledgeFrame(playedID, device: device, phase: "played")
                    }
                }
                // Queued in the local audio engine: this device has its copy.
                Task { [weak self] in
                    await self?.acknowledgeFrame(playedID, device: device, phase: "received")
                }
                status = "\(selected?.name ?? "Vriend") praat…"
            }
        } catch { /* transient audio network drop: next poll retries */ }
    }

    private func acknowledgeFrame(_ id: Int, device: String, phase: String) async {
        guard ready else { return }
        do {
            var request = try makeRequest("/v2/frames/ack", method: "POST")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = try JSONSerialization.data(withJSONObject: ["ids": [id], "device": device, "phase": phase])
            let (_, response) = try await URLSession.shared.upload(for: request, from: body)
            try validate(response)
        } catch { /* 15-second expiry remains a fallback if an ACK is lost */ }
    }

    private func flushAudio() async {
        // Hold = record locally; release = transmit buffered PCM immediately.
        guard ready, !isSpeaking, !isSending,
              let recipient = selectedFriendID, !outgoing.isEmpty else { return }
        isSending = true
        var chunk = Data()
        while let next = outgoing.first, chunk.count + next.count <= 32768 {
            chunk.append(next)
            outgoing.removeFirst()
        }
        if chunk.isEmpty, !outgoing.isEmpty {
            chunk = Data(outgoing.removeFirst().prefix(32768))
        }
        do {
            let request = try makeRequest("/v2/frames/\(recipient)", method: "POST")
            var upload = request
            upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.upload(for: upload, from: chunk)
            try validate(response)
            if outgoing.isEmpty { status = "Verzonden ✓" }
        } catch { status = "Audioverbinding verbroken" }
        isSending = false
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: makeRequest(path))
        try validate(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send<T: Decodable>(_ path: String, body: Body, authenticated: Bool = true) async throws -> T {
        var request = try makeRequest(path, method: "POST", authenticated: authenticated)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try JSONEncoder().encode(body)
        let (result, response) = try await URLSession.shared.upload(for: request, from: data)
        try validate(response)
        return try JSONDecoder().decode(T.self, from: result)
    }

    private func sendJSONObject<T: Decodable>(_ path: String, value: [String: String]) async throws -> T {
        var request = try makeRequest(path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try JSONSerialization.data(withJSONObject: value)
        let (result, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse else { throw VoxieError.server }
        if http.statusCode == 409 { throw VoxieError.usernameTaken }
        if !(200...299).contains(http.statusCode) {
            let payload = (try? JSONSerialization.jsonObject(with: result)) as? [String: String]
            throw VoxieError.detail("Serverfout \(http.statusCode): \(payload?["error"] ?? "onbekend")")
        }
        try validate(response)
        return try JSONDecoder().decode(T.self, from: result)
    }

    private func makeRequest(_ path: String, method: String = "GET", authenticated: Bool = true) throws -> URLRequest {
        guard let url = URL(string: server + path), url.scheme == "https" else { throw VoxieError.address }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        if authenticated { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func validate(_ response: URLResponse) throws {
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            throw VoxieError.unauthorized
        }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw VoxieError.server
        }
    }
}

private struct OkReply: Decodable { let ok: Bool }
private enum VoxieError: LocalizedError {
    case address, server, usernameTaken, unauthorized, detail(String)
    var errorDescription: String? {
        switch self {
        case .address: return "Ongeldig HTTPS-adres"
        case .server: return "Serverfout of niet beschikbaar"
        case .usernameTaken: return "Deze gebruikersnaam bestaat al. Kies een andere."
        case .unauthorized: return "Je sessie is verlopen. Meld je opnieuw aan."
        case .detail(let message): return message
        }
    }
}
