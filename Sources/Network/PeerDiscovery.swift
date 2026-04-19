import Foundation
import Network

/// Discovers peers on the local network via Bonjour (DNS-SD).
/// Advertises this instance and browses for other snor-oh instances.
///
/// Service type: `_snor-oh._tcp`
/// TXT records: `nickname`, `pet`, `port` (HTTP port for visits)
final class PeerDiscovery {
    private let sessionManager: SessionManager
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.snoroh.discovery", qos: .utility)

    /// Our advertised instance name, used to filter self-discovery.
    private(set) var instanceName: String = ""

    /// The PID-based suffix ensures uniqueness even if nicknames collide.
    private let pidSuffix = "-\(ProcessInfo.processInfo.processIdentifier)"

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func start() {
        instanceName = sessionManager.nickname + pidSuffix
        startAdvertising()
        startBrowsing()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
    }

    func updateTXT() {
        instanceName = sessionManager.nickname + pidSuffix
        stop()
        start()
    }

    // MARK: - Advertising

    private func startAdvertising() {
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            print("[discovery] failed to create listener: \(error)")
            return
        }

        var txtRecord = NWTXTRecord()
        txtRecord["nickname"] = sessionManager.nickname
        txtRecord["pet"] = sessionManager.pet
        txtRecord["port"] = "\(sessionManager.httpPort)"
        listener?.service = NWListener.Service(
            name: instanceName,
            type: "_snor-oh._tcp",
            txtRecord: txtRecord
        )

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue {
                    print("[discovery] advertising as \(self?.instanceName ?? "?") on port \(port)")
                }
            case .failed(let error):
                print("[discovery] listener failed: \(error)")
            case .waiting(let error):
                print("[discovery] listener waiting: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { connection in
            connection.cancel()
        }

        listener?.start(queue: queue)
    }

    // MARK: - Browsing

    private func startBrowsing() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_snor-oh._tcp", domain: nil)
        browser = NWBrowser(for: descriptor, using: .tcp)

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleBrowseChanges(results: results, changes: changes)
        }

        browser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[discovery] browsing for peers")
            case .failed(let error):
                print("[discovery] browser failed: \(error)")
            case .waiting(let error):
                print("[discovery] browser waiting (local network permission needed?): \(error)")
            default:
                break
            }
        }

        browser?.start(queue: queue)
    }

    private func handleBrowseChanges(results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                handlePeerFound(result)
            case .removed(let result):
                handlePeerRemoved(result)
            case .changed(old: _, new: let result, flags: _):
                handlePeerFound(result)
            case .identical:
                break
            @unknown default:
                break
            }
        }
    }

    private func handlePeerFound(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }

        // Skip self — check both exact name and PID suffix
        if name == instanceName || name.hasSuffix(pidSuffix) {
            return
        }

        // Extract TXT record
        var nickname = name  // fallback: use service name
        var pet = "sprite"
        var httpPort: UInt16 = 1234

        if case .bonjour(let txtRecord) = result.metadata {
            // NWTXTRecord key lookup
            if let n = txtRecord["nickname"], !n.isEmpty { nickname = n }
            if let p = txtRecord["pet"], !p.isEmpty { pet = p }
            if let portStr = txtRecord["port"], let p = UInt16(portStr) { httpPort = p }
        }

        print("[discovery] found peer: \(name) nickname=\(nickname) pet=\(pet) port=\(httpPort)")

        // Resolve IP by connecting to the service endpoint
        let connection = NWConnection(to: result.endpoint, using: .tcp)
        var resolved = false

        connection.stateUpdateHandler = { [weak self, name, nickname, pet, httpPort] state in
            guard let self else {
                connection.cancel()
                return
            }
            switch state {
            case .ready:
                guard !resolved else { break }
                resolved = true

                var ip = "127.0.0.1"
                if let path = connection.currentPath,
                   let endpoint = path.remoteEndpoint,
                   case .hostPort(let host, _) = endpoint {
                    switch host {
                    case .ipv4(let addr): ip = "\(addr)"
                    case .ipv6(let addr): ip = "[\(addr)]"
                    default: break
                    }
                }

                let peer = PeerInfo(
                    instanceName: name,
                    nickname: nickname,
                    pet: pet,
                    ip: ip,
                    port: httpPort
                )
                print("[discovery] resolved peer \(nickname) at \(ip):\(httpPort)")
                DispatchQueue.main.async {
                    self.sessionManager.addPeer(peer)
                }
                connection.cancel()

            case .failed(let error):
                guard !resolved else { break }
                resolved = true
                print("[discovery] failed to resolve \(name): \(error)")
                connection.cancel()

            case .cancelled:
                break

            default:
                break
            }
        }
        connection.start(queue: queue)

        // Timeout: cancel if not resolved within 5s
        queue.asyncAfter(deadline: .now() + 5) {
            if !resolved {
                resolved = true
                print("[discovery] timeout resolving \(name)")
                connection.cancel()
            }
        }
    }

    private func handlePeerRemoved(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }
        print("[discovery] peer removed: \(name)")
        DispatchQueue.main.async { [weak self] in
            self?.sessionManager.removePeer(instanceName: name)
        }
    }
}
