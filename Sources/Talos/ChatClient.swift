import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

@MainActor
final class ChatClient: ObservableObject {
    static let shared = ChatClient()
    private init() {}

    @Published var messages: [ChatMessage] = []
    @Published var streamingResponse: String = ""
    @Published var isStreaming = false
    @Published var error: String?

    private var streamTask: Task<Void, Never>?

    func send(_ userMessage: String) {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: "user", content: trimmed))
        isStreaming = true
        streamingResponse = ""
        error = nil

        let port = Settings.shared.port
        let history = messages

        streamTask = Task {
            do {
                guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120

                let body: [String: Any] = [
                    "model": "local",
                    "messages": history.map { ["role": $0.role, "content": $0.content] },
                    "stream": true,
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                for try await line in bytes.lines {
                    guard !Task.isCancelled else { break }
                    guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
                    let jsonString = String(line.dropFirst(6))
                    guard
                        let data = jsonString.data(using: .utf8),
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let choices = json["choices"] as? [[String: Any]],
                        let delta = choices.first?["delta"] as? [String: Any],
                        let chunk = delta["content"] as? String
                    else { continue }
                    streamingResponse += chunk
                }
                if !streamingResponse.isEmpty {
                    messages.append(ChatMessage(role: "assistant", content: streamingResponse))
                }
            } catch {
                self.error = error.localizedDescription
            }
            streamingResponse = ""
            isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if !streamingResponse.isEmpty {
            messages.append(ChatMessage(role: "assistant", content: streamingResponse))
        }
        streamingResponse = ""
        isStreaming = false
    }

    func clearHistory() {
        messages = []
        streamingResponse = ""
        error = nil
    }

    // MARK: - Prompt refinement

    @Published var refinedPrompt: String?
    @Published var isRefining = false
    private var refineTask: Task<Void, Never>?

    func refine(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        refineTask?.cancel()
        isRefining = true
        refinedPrompt = ""

        let port = Settings.shared.port

        refineTask = Task {
            do {
                guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 60

                let body: [String: Any] = [
                    "model": "local",
                    "messages": [
                        [
                            "role": "system",
                            "content": "Rewrite the user's prompt to be clearer and more precise for a coding assistant. Return only the rewritten prompt — no explanation, no preamble, no quotes.",
                        ],
                        ["role": "user", "content": trimmed],
                    ],
                    "stream": true,
                    "max_tokens": 300,
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                var result = ""
                for try await line in bytes.lines {
                    guard !Task.isCancelled else { break }
                    guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
                    let jsonString = String(line.dropFirst(6))
                    guard
                        let data = jsonString.data(using: .utf8),
                        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                        let choices = json["choices"] as? [[String: Any]],
                        let delta = choices.first?["delta"] as? [String: Any],
                        let chunk = delta["content"] as? String
                    else { continue }
                    result += chunk
                    refinedPrompt = result
                }
            } catch {
                // silent — user still has original input
            }
            isRefining = false
        }
    }

    func dismissRefinement() {
        refineTask?.cancel()
        refineTask = nil
        refinedPrompt = nil
        isRefining = false
    }
}
