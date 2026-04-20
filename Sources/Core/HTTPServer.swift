import Foundation
import NIO
import NIOHTTP1

/// Lightweight HTTP server on 0.0.0.0:1234 using SwiftNIO.
/// Binds to all interfaces so peers on LAN can send /visit requests.
final class HTTPServer {
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?
    private let sessionManager: SessionManager
    let port: Int

    init(sessionManager: SessionManager, port: Int = 1234) {
        self.sessionManager = sessionManager
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    func start() throws {
        let sm = sessionManager
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(sessionManager: sm))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)

        channel = try bootstrap.bind(host: "0.0.0.0", port: port).wait()
    }

    func stop() {
        try? channel?.close().wait()
        try? group.syncShutdownGracefully()
    }
}

// MARK: - HTTP Handler

private final class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let sessionManager: SessionManager
    private var requestHead: HTTPRequestHead?
    private var body = ByteBuffer()

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            body.clear()
        case .body(var buf):
            body.writeBuffer(&buf)
        case .end:
            guard let head = requestHead else { return }
            handleRequest(context: context, head: head, body: body)
            requestHead = nil
            body.clear()
        }
    }

    private func handleRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer) {
        let (path, query) = parseURI(head.uri)

        // pet-status and debug must read @Observable state on main thread.
        // Use async dispatch + eventLoop callback to avoid deadlocking the NIO thread.
        switch path {
        case "/mcp/pet-status":
            handlePetStatusAsync(context: context)
            return
        case "/debug":
            handleDebugAsync(context: context)
            return
        default:
            break
        }

        let (status, responseBody): (HTTPResponseStatus, String)

        switch path {
        case "/status":
            (status, responseBody) = handleStatus(query: query)
        case "/heartbeat":
            (status, responseBody) = handleHeartbeat(query: query)
        case "/session-start":
            (status, responseBody) = handleSessionStart(query: query)
        case "/session-end":
            (status, responseBody) = handleSessionEnd(query: query)
        case "/visit":
            (status, responseBody) = handleVisit(body: body)
        case "/visit-end":
            (status, responseBody) = handleVisitEnd(body: body)
        case "/mcp/say":
            (status, responseBody) = handleMCPSay(body: body)
        case "/mcp/react":
            (status, responseBody) = handleMCPReact(body: body)
        case "/peer/message":
            (status, responseBody) = handlePeerMessage(body: body)
        default:
            (status, responseBody) = (.notFound, "not found")
        }

        respond(context: context, status: status, body: responseBody, isJSON: false)
    }

    // MARK: - Route Handlers

    private func handleStatus(query: [String: String]) -> (HTTPResponseStatus, String) {
        guard let pidStr = query["pid"], let pid = UInt32(pidStr),
              let state = query["state"] else {
            return (.badRequest, "missing pid or state")
        }
        let type = query["type"]
        let cwd = query["cwd"]?.removingPercentEncoding

        DispatchQueue.main.async {
            self.sessionManager.handleStatus(pid: pid, state: state, type: type, cwd: cwd)
        }
        return (.ok, "ok")
    }

    private func handleHeartbeat(query: [String: String]) -> (HTTPResponseStatus, String) {
        guard let pidStr = query["pid"], let pid = UInt32(pidStr) else {
            return (.badRequest, "missing pid")
        }
        let cwd = query["cwd"]?.removingPercentEncoding

        DispatchQueue.main.async {
            self.sessionManager.handleHeartbeat(pid: pid, cwd: cwd)
        }
        return (.ok, "ok")
    }

    /// GET `/session-start?pid=X&cwd=...&kind=shell|claude&started_at=...`
    /// Registers a session explicitly. Sent once by shell rc / Claude
    /// SessionStart hook. Query-string form (not POST body) so shell
    /// scripts can emit it with a plain `curl`.
    private func handleSessionStart(query: [String: String]) -> (HTTPResponseStatus, String) {
        guard let pidStr = query["pid"], let pid = UInt32(pidStr) else {
            return (.badRequest, "missing pid")
        }
        let cwd = query["cwd"]?.removingPercentEncoding
        let kind = query["kind"]?.removingPercentEncoding
        let startedAt = query["started_at"]?.removingPercentEncoding

        DispatchQueue.main.async {
            self.sessionManager.handleSessionStart(
                pid: pid, cwd: cwd, kind: kind, startedAt: startedAt
            )
        }
        return (.ok, "ok")
    }

    /// GET `/session-end?pid=X` — deletes the session immediately. Sent by
    /// shell EXIT trap / Claude SessionEnd hook. Missing sessions are a no-op.
    private func handleSessionEnd(query: [String: String]) -> (HTTPResponseStatus, String) {
        guard let pidStr = query["pid"], let pid = UInt32(pidStr) else {
            return (.badRequest, "missing pid")
        }
        DispatchQueue.main.async {
            self.sessionManager.handleSessionEnd(pid: pid)
        }
        return (.ok, "ok")
    }

    private func handleVisit(body: ByteBuffer) -> (HTTPResponseStatus, String) {
        guard let data = body.getBytes(at: body.readerIndex, length: body.readableBytes).flatMap({ Data($0) }),
              let payload = try? JSONDecoder().decode(VisitPayload.self, from: data) else {
            return (.badRequest, "invalid json")
        }
        let visitor = VisitingDog(
            instanceName: payload.instanceName,
            pet: payload.pet,
            nickname: payload.nickname,
            arrivedAt: nowSecs(),
            durationSecs: payload.durationSecs ?? 15
        )
        DispatchQueue.main.async {
            self.sessionManager.addVisitor(visitor)
        }
        return (.ok, "ok")
    }

    private func handleVisitEnd(body: ByteBuffer) -> (HTTPResponseStatus, String) {
        guard let data = body.getBytes(at: body.readerIndex, length: body.readableBytes).flatMap({ Data($0) }),
              let payload = try? JSONDecoder().decode(VisitEndPayload.self, from: data) else {
            return (.badRequest, "invalid json")
        }
        DispatchQueue.main.async {
            self.sessionManager.removeVisitor(instanceName: payload.instanceName, nickname: payload.nickname)
        }
        return (.ok, "ok")
    }

    private func handlePeerMessage(body: ByteBuffer) -> (HTTPResponseStatus, String) {
        guard let data = body.getBytes(at: body.readerIndex, length: body.readableBytes).flatMap({ Data($0) }),
              let payload = try? JSONDecoder().decode(PeerMessagePayload.self, from: data) else {
            return (.badRequest, "invalid json")
        }
        let bubbleMessage = "\(payload.sender): \(payload.message)"
        DispatchQueue.main.async {
            self.sessionManager.handleMCPSay(message: bubbleMessage, durationMs: 8000)
        }
        return (.ok, "ok")
    }

    private func handleMCPSay(body: ByteBuffer) -> (HTTPResponseStatus, String) {
        guard let data = body.getBytes(at: body.readerIndex, length: body.readableBytes).flatMap({ Data($0) }),
              let payload = try? JSONDecoder().decode(MCPSayPayload.self, from: data) else {
            return (.badRequest, "invalid json")
        }
        let durationMs = (payload.durationSecs ?? 7) * 1000
        DispatchQueue.main.async {
            self.sessionManager.handleMCPSay(message: payload.message, durationMs: durationMs)
        }
        return (.ok, "ok")
    }

    private func handleMCPReact(body: ByteBuffer) -> (HTTPResponseStatus, String) {
        guard let data = body.getBytes(at: body.readerIndex, length: body.readableBytes).flatMap({ Data($0) }),
              let payload = try? JSONDecoder().decode(MCPReactPayload.self, from: data) else {
            return (.badRequest, "invalid json")
        }
        let durationMs = (payload.durationSecs ?? 3) * 1000
        DispatchQueue.main.async {
            self.sessionManager.handleMCPReact(reaction: payload.reaction, durationMs: durationMs)
        }
        return (.ok, "ok")
    }

    /// Read @Observable state on main thread, respond via NIO event loop (avoids deadlock).
    private func handlePetStatusAsync(context: ChannelHandlerContext) {
        let eventLoop = context.eventLoop
        DispatchQueue.main.async { [self] in
            let response = self.sessionManager.petStatusJSON()
            let json: String
            if let data = try? JSONEncoder().encode(response) {
                json = String(data: data, encoding: .utf8) ?? "{}"
            } else {
                json = "{}"
            }
            eventLoop.execute {
                self.respond(context: context, status: .ok, body: json, isJSON: true)
            }
        }
    }

    /// Read @Observable state on main thread, respond via NIO event loop (avoids deadlock).
    private func handleDebugAsync(context: ChannelHandlerContext) {
        let eventLoop = context.eventLoop
        DispatchQueue.main.async { [self] in
            let sm = self.sessionManager
            var lines: [String] = []
            lines.append("=== snor-oh Swift Debug ===")
            lines.append("UI: \(sm.currentUI.rawValue) | sleeping: \(sm.sleeping)")
            lines.append("Pet: \(sm.pet) | Nickname: \(sm.nickname)")
            lines.append("Uptime: \(nowSecs() - sm.startedAt)s")
            lines.append("")
            lines.append("Sessions (\(sm.sessions.count)):")
            for (pid, s) in sm.sessions.sorted(by: { $0.key < $1.key }) {
                lines.append("  pid=\(pid) state=\(s.uiState.rawValue) type=\(s.busyType) seen=\(s.lastSeen) cwd=\(s.cwd ?? "?")")
            }
            lines.append("")
            lines.append("Projects (\(sm.projects.count)):")
            for p in sm.projects {
                lines.append("  \(p.name) [\(p.status.rawValue)] pids=\(p.sessions) files=\(p.modifiedFiles)")
            }
            lines.append("")
            lines.append("Peers (\(sm.peers.count)):")
            for (_, p) in sm.peers {
                lines.append("  \(p.nickname) (\(p.pet)) @ \(p.host):\(p.port)")
            }
            lines.append("")
            lines.append("Visitors (\(sm.visitors.count)):")
            for v in sm.visitors {
                lines.append("  \(v.nickname) (\(v.pet)) since=\(v.arrivedAt) dur=\(v.durationSecs)s")
            }
            lines.append("")
            lines.append("Usage today: tasks=\(sm.usage.tasksCompleted) busy=\(sm.usage.totalBusySecs)s longest=\(sm.usage.longestTaskSecs)s")
            let text = lines.joined(separator: "\n")
            eventLoop.execute {
                self.respond(context: context, status: .ok, body: text)
            }
        }
    }

    // MARK: - Response Helper

    private func respond(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String, isJSON: Bool = false) {
        var headers = HTTPHeaders()
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS")
        headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type")
        headers.add(name: "Content-Type", value: isJSON ? "application/json" : "text/plain")
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")

        let responseHead = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    // MARK: - URI Parser

    private func parseURI(_ uri: String) -> (path: String, query: [String: String]) {
        let parts = uri.split(separator: "?", maxSplits: 1)
        let path = String(parts[0])
        var query: [String: String] = [:]
        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    query[String(kv[0])] = String(kv[1])
                }
            }
        }
        return (path, query)
    }
}
