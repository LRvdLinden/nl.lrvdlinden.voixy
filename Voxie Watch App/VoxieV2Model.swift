import AVFoundation
import Foundation
import UserNotifications
import SwiftUI

struct VoxieFriend: Decodable, Identifiable {
    let id: String
    let name: String
    let available: Bool
}

struct VoxieInvitation: Decodable, Identifiable {
    let id: Int
    let name: String
}

private struct RegisterReply: Decodable { let id: String; let token: String; let code: String }
private struct StateReply: Decodable {
    let id: String
    let code: String
    let friends: [VoxieFriend]
    let invitations: [VoxieInvitation]
}
private struct FrameReply: Decodable { let frames: [VoxieFrame] }
private struct VoxieFrame: Decodable { let id: Int; let sender: String; let pcm: String }
private struct Body: Encodable { let name: String?; let code: String?; let available: Bool? }

@MainActor
final class VoxieV2Model: ObservableObject {
    @Published var server = SupabaseConfiguration.functionURL
    @Published var name = UserDefaults.standard.string(forKey: "v2.name") ?? ""
    @Published private(set) var code = ""
    @Published private(set) var status = "Stel je profiel in"
    @Published private(set) var friends: [VoxieFriend] = []
    @Published private(set) var invitations: [VoxieInvitation] = []
    @Published var selectedFriendID: String?
    @Published private(set) var available = UserDefaults.standard.object(forKey: "v2.available") as? Bool ?? true
    @Published private(set) var isSpeaking = false
    @Published private(set) var isSending = false

    private var identity = UserDefaults.standard.string(forKey: "v2.identity") ?? ""
    private var token = UserDefaults.standard.string(forKey: "v2.token") ?? ""
    private var refreshTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var transmitTask: Task<Void, Never>?
    private var cursor = 0
    private let audio = LiveAudio()
    private var outgoing: [Data] = []
    private var holding = false
    private var pushToken: String?
    private var maxRecordingTask: Task<Void, Never>?

    var ready: Bool { !token.isEmpty && server.hasPrefix("https://") }
    var selected: VoxieFriend? { friends.first { $0.id == selectedFriendID } }

    init() {
        // A previous Voxie build used an unrelated Python host. Its opaque
        // identity token must never be submitted to a different backend.
        if UserDefaults.standard.string(forKey: "v2.server") != SupabaseConfiguration.functionURL {
            token = ""
            identity = ""
            UserDefaults.standard.removeObject(forKey: "v2.token")
            UserDefaults.standard.removeObject(forKey: "v2.identity")
        }
    }

    func configure(server newServer: String, name newName: String) async {
        let address = SupabaseConfiguration.functionURL
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.hasPrefix("https://"), newName.count >= 1 else {
            status = "Vul HTTPS-server en naam in"; return
        }
        stop()
        if address != server || newName != name {
            token = ""; identity = ""; code = ""
            UserDefaults.standard.removeObject(forKey: "v2.token")
            UserDefaults.standard.removeObject(forKey: "v2.identity")
        }
        server = address; name = newName
        UserDefaults.standard.set(server, forKey: "v2.server")
        UserDefaults.standard.set(name, forKey: "v2.name")
        if token.isEmpty { await register() }
        if let pushToken { await uploadPushToken(pushToken) }
        start()
    }

    private func register() async {
        do {
            let result: RegisterReply = try await send("/v2/register", body: Body(name: name, code: nil, available: nil), authenticated: false)
            token = result.token; identity = result.id; code = result.code
            UserDefaults.standard.set(token, forKey: "v2.token")
            UserDefaults.standard.set(identity, forKey: "v2.identity")
            status = "Je code: \(code)"
        } catch { status = "Registratie: \(error.localizedDescription)" }
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

    func invite(code: String) async {
        do {
            let _: OkReply = try await send("/v2/invite", body: Body(name: nil, code: code, available: nil))
            status = "Uitnodiging verstuurd"; await refresh()
        } catch { status = "Uitnodigen: \(error.localizedDescription)" }
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

    func respond(invitation: Int, accept: Bool) async {
        do {
            let path = "/v2/invitations/\(invitation)/" + (accept ? "accept" : "decline")
            let _: OkReply = try await send(path, body: Body(name: nil, code: nil, available: nil))
            status = accept ? "Vriend toegevoegd" : "Uitnodiging geweigerd"
            await refresh()
        } catch { status = "Antwoord: \(error.localizedDescription)" }
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
            friends = result.friends
            invitations = result.invitations
            if let id = selectedFriendID, !friends.contains(where: { $0.id == id }) { selectedFriendID = nil }
        } catch { status = "Netwerk: \(error.localizedDescription)" }
    }

    private func receiveFrames() async {
        guard ready else { return }
        do {
            let response: FrameReply = try await get("/v2/frames?after=\(cursor)")
            for frame in response.frames {
                cursor = max(cursor, frame.id)
                guard available, !isSpeaking, frame.sender == selectedFriendID,
                      let data = Data(base64Encoded: frame.pcm) else { continue }
                try audio.play(data)
                status = "\(selected?.name ?? "Vriend") praat…"
            }
        } catch { /* transient audio network drop: next poll retries */ }
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
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw VoxieError.server
        }
    }
}

private struct OkReply: Decodable { let ok: Bool }
private enum VoxieError: LocalizedError {
    case address, server
    var errorDescription: String? {
        switch self {
        case .address: return "Ongeldig HTTPS-adres"
        case .server: return "Serverfout of niet beschikbaar"
        }
    }
}
