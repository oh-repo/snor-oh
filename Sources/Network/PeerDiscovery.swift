import Foundation
import Network

/// Discovers peers on the local network via Bonjour (DNS-SD).
///
/// Peers are added immediately on discovery. IP is resolved in the background
/// via NWConnection to the Bonjour endpoint and the peer is updated when ready.
final class PeerDiscovery {
    private let sessionManager: SessionManager
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.snoroh.discovery", qos: .utility)

    private(set) var instanceName: String = ""
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

    // MARK: - Local IP

    static func localIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, ip: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var addr = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                           &addr, socklen_t(addr.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: addr)
                let name = String(cString: ptr.pointee.ifa_name)
                if !name.hasPrefix("utun") && !name.hasPrefix("llw") && !name.hasPrefix("awdl") {
                    candidates.append((name: name, ip: ip))
                }
            }
        }

        if let en0 = candidates.first(where: { $0.name == "en0" }) { return en0.ip }
        if let en1 = candidates.first(where: { $0.name == "en1" }) { return en1.ip }
        return candidates.first?.ip
    }

    // MARK: - Advertising

    private func startAdvertising() {
        do {
            listener = try NWListener(using: .tcp)
        } catch {
            print("[discovery] failed to create listener: \(error)")
            return
        }

        let localIP = Self.localIPAddress() ?? "127.0.0.1"

        var txtRecord = NWTXTRecord()
        txtRecord["nickname"] = sessionManager.nickname
        txtRecord["pet"] = sessionManager.pet
        txtRecord["port"] = "\(sessionManager.httpPort)"
        txtRecord["ip"] = localIP

        listener?.service = NWListener.Service(
            name: instanceName,
            type: "_snor-oh._tcp",
            txtRecord: txtRecord
        )

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[discovery] advertising as \(self?.instanceName ?? "?"), ip=\(localIP)")
            case .failed(let error):
                print("[discovery] listener failed: \(error)")
            case .waiting(let error):
                print("[discovery] listener waiting: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { $0.cancel() }
        listener?.start(queue: queue)
    }

    // MARK: - Browsing

    private func startBrowsing() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_snor-oh._tcp", domain: nil)
        browser = NWBrowser(for: descriptor, using: .tcp)

        browser?.browseResultsChangedHandler = { [weak self] _, changes in
            for change in changes {
                switch change {
                case .added(let result), .changed(old: _, new: let result, flags: _):
                    self?.handlePeerFound(result)
                case .removed(let result):
                    self?.handlePeerRemoved(result)
                case .identical:
                    break
                @unknown default:
                    break
                }
            }
        }

        browser?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[discovery] browsing for peers")
            case .failed(let error):
                print("[discovery] browser failed: \(error)")
            case .waiting(let error):
                print("[discovery] browser waiting: \(error)")
            default:
                break
            }
        }

        browser?.start(queue: queue)
    }

    private func handlePeerFound(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else { return }
        if name == instanceName || name.hasSuffix(pidSuffix) { return }

        // Extract TXT if available
        var nickname = name
        var pet = "sprite"
        var httpPort: UInt16 = 1234
        var txtIP: String?

        if case .bonjour(let txtRecord) = result.metadata {
            for entry in txtRecord {
                guard let val = txtRecord[entry.key], !val.isEmpty else { continue }
                switch entry.key.lowercased() {
                case "nickname": nickname = val
                case "pet":      pet = val
                case "port":     if let p = UInt16(val) { httpPort = p }
                case "ip":       txtIP = val
                default:         break
                }
            }
        }

        if let ip = txtIP {
            // Have IP from TXT — add peer directly
            print("[discovery] peer ready: \(nickname) ip=\(ip) port=\(httpPort)")
            let peer = PeerInfo(instanceName: name, nickname: nickname, pet: pet,
                                host: ip, port: httpPort, ip: ip, endpoint: result.endpoint)
            DispatchQueue.main.async { [weak self] in
                self?.sessionManager.addPeer(peer)
            }
        } else {
            // No IP from TXT — add with placeholder, resolve via NWConnection
            print("[discovery] peer found: \(nickname) (resolving IP...)")
            let peer = PeerInfo(instanceName: name, nickname: nickname, pet: pet,
                                host: name, port: httpPort, ip: nil, endpoint: result.endpoint)
            DispatchQueue.main.async { [weak self] in
                self?.sessionManager.addPeer(peer)
            }

            // Resolve IP by connecting to Bonjour endpoint (on discovery queue)
            let connection = NWConnection(to: result.endpoint, using: .tcp)
            var resolved = false
            connection.stateUpdateHandler = { [weak self, name, nickname, pet, httpPort] state in
                guard !resolved else { return }
                switch state {
                case .ready:
                    resolved = true
                    var ip: String?
                    if let path = connection.currentPath,
                       let remote = path.remoteEndpoint,
                       case .hostPort(let host, _) = remote {
                        switch host {
                        case .ipv4(let addr): ip = "\(addr)"
                        case .ipv6(let addr):
                            ip = "\(addr)".components(separatedBy: "%").first
                        default: break
                        }
                    }
                    connection.cancel()
                    if let ip {
                        print("[discovery] resolved \(nickname) → \(ip)")
                        let updated = PeerInfo(instanceName: name, nickname: nickname, pet: pet,
                                               host: ip, port: httpPort, ip: ip, endpoint: nil)
                        DispatchQueue.main.async {
                            self?.sessionManager.addPeer(updated)
                        }
                    }
                case .failed(let err):
                    resolved = true
                    print("[discovery] resolve failed for \(nickname): \(err)")
                    connection.cancel()
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) {
                if !resolved {
                    resolved = true
                    print("[discovery] resolve timeout for \(nickname)")
                    connection.cancel()
                }
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
