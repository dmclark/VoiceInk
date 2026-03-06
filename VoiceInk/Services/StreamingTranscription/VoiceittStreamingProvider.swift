import Foundation
import SocketIO
import os

/// Voiceitt streaming provider using Socket.IO for real-time transcription
/// of non-standard speech via per-user trained models.
final class VoiceittStreamingProvider: StreamingTranscriptionProvider {

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "VoiceittStreamingProvider")
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var eventsContinuation: AsyncStream<StreamingTranscriptionEvent>.Continuation?

    private var connectionReady = false
    private var modelReady = false

    private(set) var transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>

    init() {
        var continuation: AsyncStream<StreamingTranscriptionEvent>.Continuation!
        transcriptionEvents = AsyncStream { continuation = $0 }
        eventsContinuation = continuation
    }

    deinit {
        eventsContinuation?.finish()
    }

    func connect(model: any TranscriptionModel, language: String?) async throws {
        // Refresh token if needed before connecting
        try? await VoiceittAuthService.shared.refreshTokenIfNeeded()

        guard let token = APIKeyManager.shared.getAPIKey(forProvider: "voiceitt"), !token.isEmpty else {
            throw StreamingTranscriptionError.missingAPIKey
        }

        let refreshToken = KeychainService.shared.getString(forKey: "voiceittRefreshToken") ?? ""

        connectionReady = false
        modelReady = false

        let url = URL(string: "https://casr-dictation-recognition.voiceitt.com")!
        let manager = SocketManager(socketURL: url, config: [
            .log(false),
            .forceWebsockets(true),
            .connectParams(["token": token, "refresh_token": refreshToken])
        ])
        self.manager = manager

        let socket = manager.defaultSocket
        self.socket = socket

        setupEventHandlers(socket: socket)

        // Connect and wait for both connection_ready and model_ready
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false

            let readyCheck = { [weak self] in
                guard let self, !resumed else { return }
                if self.connectionReady && self.modelReady {
                    resumed = true
                    self.eventsContinuation?.yield(.sessionStarted)
                    continuation.resume()
                }
            }

            socket.on("connection_ready") { [weak self] _, _ in
                self?.connectionReady = true
                readyCheck()
            }

            socket.on("model_ready") { [weak self] _, _ in
                self?.modelReady = true
                readyCheck()
            }

            socket.on("model_missing") { _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: StreamingTranscriptionError.serverError("Voiceitt model not found for this user"))
            }

            socket.on("model_loading_error") { _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: StreamingTranscriptionError.serverError("Voiceitt model failed to load"))
            }

            socket.on(clientEvent: .error) { data, _ in
                guard !resumed else { return }
                resumed = true
                let message = (data.first as? String) ?? "Connection error"
                continuation.resume(throwing: StreamingTranscriptionError.connectionFailed(message))
            }

            socket.on(clientEvent: .disconnect) { _, _ in
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: StreamingTranscriptionError.connectionFailed("Disconnected during setup"))
            }

            socket.connect()

            // Timeout after 120 seconds (model loading can be slow)
            DispatchQueue.global().asyncAfter(deadline: .now() + 120) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(throwing: StreamingTranscriptionError.timeout)
            }
        }

        // Send options after ready
        socket.emit("set_options", ["recognition_mode": "dictation", "save_audio": true])
    }

    func sendAudioChunk(_ data: Data) async throws {
        guard let socket, socket.status == .connected, connectionReady, modelReady else {
            throw StreamingTranscriptionError.notConnected
        }

        // Convert raw PCM Int16 LE bytes to [Int16] array
        let samples = data.withUnsafeBytes { buffer -> [Int16] in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            return Array(int16Buffer)
        }

        socket.emit("stream_audio_samples", samples, "int16")
    }

    func commit() async throws {
        guard let socket, socket.status == .connected else {
            throw StreamingTranscriptionError.notConnected
        }
        socket.emit("stop_stream_processing")
    }

    func disconnect() async {
        socket?.disconnect()
        socket = nil
        manager?.disconnect()
        manager = nil
        connectionReady = false
        modelReady = false
        eventsContinuation?.finish()
    }

    // MARK: - Private

    private func setupEventHandlers(socket: SocketIOClient) {
        socket.on("partial_recognition") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let text = dict["text"] as? String else { return }
            let unstable = dict["unstable_text"] as? String ?? ""
            let combined = unstable.isEmpty ? text : "\(text) \(unstable)"
            self?.eventsContinuation?.yield(.partial(text: combined))
        }

        socket.on("recognition") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let text = dict["text"] as? String else { return }
            self?.eventsContinuation?.yield(.committed(text: text))
        }

        socket.on("error") { [weak self] data, _ in
            let message = (data.first as? String) ?? "Unknown Voiceitt error"
            self?.eventsContinuation?.yield(.error(StreamingTranscriptionError.serverError(message)))
        }

        socket.on("reset_alb_cookies") { [weak self] _, _ in
            self?.logger.notice("Received reset_alb_cookies — reconnecting")
            // The StreamingTranscriptionService will handle reconnection
            self?.eventsContinuation?.yield(.error(StreamingTranscriptionError.connectionFailed("Server requested reconnection")))
        }

        socket.on("token_updated") { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                  let newToken = dict["token"] as? String else { return }
            // Persist refreshed token
            APIKeyManager.shared.saveAPIKey(newToken, forProvider: "voiceitt")
            if let newRefresh = dict["refresh_token"] as? String {
                KeychainService.shared.save(newRefresh, forKey: "voiceittRefreshToken")
            }
            self?.logger.info("Voiceitt token refreshed")
        }
    }
}
