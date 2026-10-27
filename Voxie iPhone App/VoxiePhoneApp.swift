import SwiftUI
import PushToTalk
import AVFoundation

@main
struct VoxiePhoneApp: App {
    @StateObject private var model = VoxieV2Model()

    init() {
        // Apple may relaunch us invisibly for a Push to Talk notification.
        VoxiePushToTalk.shared.initialize()
    }

    var body: some Scene {
        WindowGroup {
            VoxiePhoneHomeView()
                .environmentObject(model)
                .onAppear { VoxiePushToTalk.shared.attach(model) }
                .onOpenURL { url in model.openSharedProfile(url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { model.openSharedProfile(url) }
                }
        }
    }
}

/// iOS/iPadOS system Push to Talk channel. watchOS has no equivalent entitlement.
/// Joining must be triggered by a foreground button press in settings.
@MainActor
final class VoxiePushToTalk: NSObject, ObservableObject, PTChannelManagerDelegate, PTChannelRestorationDelegate {
    static let shared = VoxiePushToTalk()
    @Published private(set) var status = "Niet geactiveerd"
    private var manager: PTChannelManager?
    private weak var model: VoxieV2Model?
    private var token: Data?
    private var channelID = UUID(uuidString: "092a7a87-f354-478d-8d85-5ea370f32d91")!
    private var initialized = false
    private var playbackTask: Task<Void, Never>?

    func initialize() {
        guard !initialized else { return }
        initialized = true
        Task {
            do {
                manager = try await PTChannelManager.channelManager(delegate: self, restorationDelegate: self)
                if let restored = manager?.activeChannelUUID {
                    channelID = restored
                    status = "Achtergrondontvangst actief"
                    await uploadTokenIfPossible()
                }
            } catch { status = "Push to Talk niet beschikbaar: \(error.localizedDescription)" }
        }
    }

    func attach(_ model: VoxieV2Model) {
        self.model = model
        Task { await uploadTokenIfPossible() }
    }

    func join() {
        guard let model, model.ready, !model.username.isEmpty else {
            status = "Stel eerst je profiel in op iPhone/iPad"
            return
        }
        guard let manager else { status = "Push to Talk wordt voorbereid…"; return }
        if manager.activeChannelUUID != nil { status = "Achtergrondontvangst actief"; return }
        status = "Kanaal activeren…"
        manager.requestJoinChannel(channelUUID: channelID, descriptor: channelDescriptor(restoredChannelUUID: channelID))
    }

    func leave() {
        manager?.leaveChannel(channelUUID: channelID)
        status = "Niet geactiveerd"
        Task { await model?.clearPushToTalkToken() }
    }

    private func uploadTokenIfPossible() async {
        guard let token, manager?.activeChannelUUID != nil else { return }
        await model?.registerPushToTalkToken(token, channelID: channelID)
    }

    func channelDescriptor(restoredChannelUUID: UUID) -> PTChannelDescriptor {
        PTChannelDescriptor(name: "Voxie", image: nil)
    }

    func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {
        token = pushToken
        Task { await uploadTokenIfPossible() }
    }

    func incomingPushResult(channelManager: PTChannelManager, channelUUID: UUID, pushPayload: [String: Any]) -> PTPushResult {
        guard let speaker = pushPayload["activeSpeaker"] as? String, !speaker.isEmpty else {
            return .leaveChannel
        }
        // Return immediately. iOS activates the audio session asynchronously.
        return .activeRemoteParticipant(PTParticipant(name: speaker, image: nil))
    }

    func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {
        model?.pttAudioSession(active: true)
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            await self?.model?.receivePushToTalkAudio()
            guard let self else { return }
            channelManager.setActiveRemoteParticipant(nil, channelUUID: self.channelID) { _ in }
        }
    }

    func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {
        playbackTask?.cancel()
        playbackTask = nil
        model?.pttAudioSession(active: false)
    }

    func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {
        channelID = channelUUID
        status = "Achtergrondontvangst actief"
        Task { await uploadTokenIfPossible() }
    }

    func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {
        status = "Niet geactiveerd"
        Task { await model?.clearPushToTalkToken() }
    }

    func channelManager(_ channelManager: PTChannelManager, failedToJoinChannel channelUUID: UUID, error: Error) {
        status = "Kanaal niet beschikbaar: \(error.localizedDescription)"
    }

    func channelManager(_ channelManager: PTChannelManager, failedToLeaveChannel channelUUID: UUID, error: Error) {
        status = "Afmelden mislukt: \(error.localizedDescription)"
    }

    func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didBeginTransmittingFrom source: PTChannelTransmitRequestSource) {}
    func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didEndTransmittingFrom source: PTChannelTransmitRequestSource) {}
    func channelManager(_ channelManager: PTChannelManager, failedToBeginTransmittingInChannel channelUUID: UUID, error: Error) {
        status = "Opnemen mislukt: \(error.localizedDescription)"
    }
    func channelManager(_ channelManager: PTChannelManager, failedToStopTransmittingInChannel channelUUID: UUID, error: Error) {
        status = "Stoppen mislukt: \(error.localizedDescription)"
    }
}
