import Foundation

/// Handles sending visits to peers and tracking our "away" state.
/// Visit protocol: POST to peer's /visit endpoint, wait duration, POST /visit-end.
final class VisitManager {
    private let sessionManager: SessionManager
    private let discovery: PeerDiscovery
    private var returnWork: DispatchWorkItem?

    static let maxVisitDuration: UInt64 = 60  // Cap at 60 seconds

    init(sessionManager: SessionManager, discovery: PeerDiscovery) {
        self.sessionManager = sessionManager
        self.discovery = discovery
    }

    /// Visit a peer. Returns error string on failure, nil on success.
    func visit(peerInstanceName: String) -> String? {
        guard sessionManager.visiting == nil else {
            return "Already visiting someone"
        }

        guard let peer = sessionManager.peers[peerInstanceName] else {
            return "Peer not found"
        }

        let ourInstanceName = discovery.instanceName
        let nickname = sessionManager.nickname
        let pet = sessionManager.pet
        let duration = min(UInt64(15), Self.maxVisitDuration)

        // Mark as visiting
        sessionManager.setVisiting(peerInstanceName)

        // Send visit request in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let payload: [String: Any] = [
                "instance_name": ourInstanceName,
                "pet": pet,
                "nickname": nickname,
                "duration_secs": duration
            ]

            guard self.sendPost(
                to: "http://\(peer.ip):\(peer.port)/visit",
                payload: payload
            ) else {
                DispatchQueue.main.async { self.sessionManager.clearVisiting() }
                return
            }

            // Schedule return after visit duration (cancellable)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let endPayload: [String: Any] = [
                    "instance_name": ourInstanceName,
                    "nickname": nickname
                ]
                self.sendPost(
                    to: "http://\(peer.ip):\(peer.port)/visit-end",
                    payload: endPayload
                )
                DispatchQueue.main.async {
                    self.sessionManager.clearVisiting()
                }
            }
            DispatchQueue.main.async { self.returnWork = work }
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + Double(duration),
                execute: work
            )
        }

        return nil
    }

    /// Cancel the current visit early (e.g., user clicks "return").
    func cancelVisit() {
        returnWork?.cancel()
        returnWork = nil
        // Execute the visit-end in background to avoid blocking the calling thread
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            // Send visit-end if we know who we're visiting
            if let visiting = self.sessionManager.visiting,
               let peer = self.sessionManager.peers[visiting] {
                let endPayload: [String: Any] = [
                    "instance_name": self.discovery.instanceName,
                    "nickname": self.sessionManager.nickname
                ]
                self.sendPost(to: "http://\(peer.ip):\(peer.port)/visit-end", payload: endPayload)
            }
            DispatchQueue.main.async {
                self.sessionManager.clearVisiting()
            }
        }
    }

    // MARK: - Private

    @discardableResult
    private func sendPost(to urlString: String, payload: [String: Any]) -> Bool {
        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = body

        var success = false
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                success = true
            } else if let error {
                print("[visit] request failed: \(error.localizedDescription)")
            }
            semaphore.signal()
        }.resume()

        let result = semaphore.wait(timeout: .now() + 10)
        if result == .timedOut { return false }
        return success
    }
}
