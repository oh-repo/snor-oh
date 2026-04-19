import Foundation
import Network

/// Discovers peers on the local network via Bonjour (DNS-SD).
/// Advertises this instance and browses for other snor-oh instances.
///
/// Service type: `_snor-oh._tcp`
/// TXT records: `nickname`, `pet`, `port`, `ip`
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

    /// Get the local WiFi/Ethernet IPv4 address (not VPN, not loopback).
    private static func localIPAddress() -> String? {
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
                // Skip utun/llw/awdl (VPN/Apple Wireless Direct Link)
                if !name.hasPrefix("utun") && !name.hasPrefix("llw") && !name.hasPrefix("awdl") {
                    candidates.append((name: name, ip: ip))
                }
            }
        }

        // Prefer en0 (WiFi) or en1 (Ethernet), then any other
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
                print("[discovery] browser waiting: \(error) — check System Settings > Privacy > Local Network")
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
                // TXT records often arrive in a .changed event after the initial .added
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

        // Skip self
        if name == instanceName || name.hasSuffix(pidSuffix) { return }

        // Extract TXT record — skip if no metadata yet (wait for .changed event)
        guard case .bonjour(let txtRecord) = result.metadata else {
            print("[discovery] waiting for TXT from \(name)...")
            return
        }

        var txtDict: [String: String] = [:]
        for entry in txtRecord {
            if let val = txtRecord[entry.key] {
                txtDict[entry.key.lowercased()] = val
            }
        }

        // Must have at least the IP to be useful
        guard let ip = txtDict["ip"], !ip.isEmpty else {
            print("[discovery] TXT for \(name) missing ip: \(txtDict)")
            return
        }

        let nickname = txtDict["nickname"] ?? name
        let pet = txtDict["pet"] ?? "sprite"
        let httpPort = txtDict["port"].flatMap(UInt16.init) ?? 1234

        print("[discovery] peer ready: \(nickname) ip=\(ip) port=\(httpPort)")

        let peer = PeerInfo(
            instanceName: name,
            nickname: nickname,
            pet: pet,
            host: ip,
            port: httpPort
        )
        DispatchQueue.main.async { [weak self] in
            self?.sessionManager.addPeer(peer)
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
