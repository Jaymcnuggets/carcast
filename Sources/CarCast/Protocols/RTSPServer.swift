//
//  RTSPServer.swift
//  CarCast
//
//  RTSP 1.0 & HTTP server for AirPlay and CarPlay session signaling and media negotiation.
//

import Foundation
import Network

public protocol RTSPServerDelegate: AnyObject, Sendable {
    func rtspServerDidStartSession(clientName: String?)
    func rtspServerDidEndSession()
    func rtspServerDidUpdateVolume(_ volume: Float)
}

public final class RTSPServer: @unchecked Sendable {
    public weak var delegate: RTSPServerDelegate?

    private var listener: NWListener?
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "dev.unordinarylabs.carcast.rtsp", qos: .userInteractive)
    private var activeConnections: [NWConnection] = []

    public init(port: UInt16 = 7000) {
        self.port = NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 7000)
    }

    public func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: port)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .rtsp, title: "RTSP Server Ready", detail: "Listening on port \(self?.port.rawValue ?? 0)")
                }
            case .failed(let err):
                Task { @MainActor in
                    ProtocolLogger.shared.log(category: .rtsp, title: "RTSP Server Failed", detail: err.localizedDescription)
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)
    }

    public func stop() {
        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        activeConnections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if state == .failed(NWError.posix(.ECONNABORTED)) || state == .cancelled {
                if let conn = connection {
                    self?.activeConnections.removeAll(where: { $0 === conn })
                }
            }
        }

        connection.start(queue: queue)
        readRequest(from: connection)
    }

    private func readRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            if let data = content, !data.isEmpty {
                self.processRequestData(data, connection: connection)
            }
            if !isComplete && error == nil {
                self.readRequest(from: connection)
            }
        }
    }

    private func processRequestData(_ data: Data, connection: NWConnection) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        let tokens = requestLine.components(separatedBy: " ")
        guard tokens.count >= 2 else { return }

        let method = tokens[0]
        let uri = tokens[1]

        // Extract CSeq
        var cseq = "1"
        for line in lines {
            if line.lowercased().hasPrefix("cseq:") {
                cseq = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            }
        }

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .rtsp,
                direction: .rx,
                title: "RTSP \(method)",
                detail: "\(uri) (CSeq: \(cseq))",
                rawData: data
            )
        }

        switch method {
        case "OPTIONS":
            handleOptions(cseq: cseq, connection: connection)
        case "ANNOUNCE":
            handleAnnounce(cseq: cseq, lines: lines, connection: connection)
        case "SETUP":
            handleSetup(cseq: cseq, lines: lines, connection: connection)
        case "RECORD":
            handleRecord(cseq: cseq, connection: connection)
        case "TEARDOWN":
            handleTeardown(cseq: cseq, connection: connection)
        case "GET_PARAMETER", "SET_PARAMETER":
            handleParameter(cseq: cseq, connection: connection)
        case "POST":
            handlePost(cseq: cseq, uri: uri, data: data, connection: connection)
        default:
            sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
        }
    }

    private func handleOptions(cseq: String, connection: NWConnection) {
        let headers = [
            "Public": "ANNOUNCE, SETUP, RECORD, PAUSE, FLUSH, TEARDOWN, OPTIONS, POST, GET, PUT, GET_PARAMETER, SET_PARAMETER"
        ]
        sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: nil, connection: connection)
    }

    private func handleAnnounce(cseq: String, lines: [String], connection: NWConnection) {
        // Extract client name if available
        var clientName: String?
        for line in lines {
            if line.lowercased().hasPrefix("x-apple-client-name:") {
                clientName = line.dropFirst(20).trimmingCharacters(in: .whitespaces)
            }
        }

        delegate?.rtspServerDidStartSession(clientName: clientName)
        sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
    }

    private func handleSetup(cseq: String, lines: [String], connection: NWConnection) {
        // Negotiate screen mirroring and audio ports
        let headers = [
            "Transport": "RTP/AVP/TCP;unicast;interleaved=0-1;mode=record;server_port=7100",
            "Session": "1"
        ]
        sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: nil, connection: connection)
    }

    private func handleRecord(cseq: String, connection: NWConnection) {
        let headers = [
            "Session": "1",
            "Audio-Latency": "11025"
        ]
        sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: nil, connection: connection)
    }

    private func handleTeardown(cseq: String, connection: NWConnection) {
        delegate?.rtspServerDidEndSession()
        sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
    }

    private func handleParameter(cseq: String, connection: NWConnection) {
        sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
    }

    private func handlePost(cseq: String, uri: String, data: Data, connection: NWConnection) {
        if uri.contains("/pair-setup") || uri.contains("/pair-verify") || uri.contains("/fp-setup") {
            // Pairing success response stub
            let headers = [
                "Content-Type": "application/octet-stream"
            ]
            sendResponse(status: "200 OK", cseq: cseq, headers: headers, body: Data([0x01, 0x00]), connection: connection)
        } else {
            sendResponse(status: "200 OK", cseq: cseq, headers: [:], body: nil, connection: connection)
        }
    }

    private func sendResponse(
        status: String,
        cseq: String,
        headers: [String: String],
        body: Data?,
        connection: NWConnection
    ) {
        var resp = "RTSP/1.0 \(status)\r\n"
        resp += "Server: AirPlay/377.17.24.6 (CarCast)\r\n"
        resp += "CSeq: \(cseq)\r\n"

        for (k, v) in headers {
            resp += "\(k): \(v)\r\n"
        }

        if let body = body, !body.isEmpty {
            resp += "Content-Length: \(body.count)\r\n\r\n"
            var respData = resp.data(using: .utf8) ?? Data()
            respData.append(body)
            connection.send(content: respData, completion: .idempotent)
        } else {
            resp += "Content-Length: 0\r\n\r\n"
            let respData = resp.data(using: .utf8) ?? Data()
            connection.send(content: respData, completion: .idempotent)
        }

        Task { @MainActor in
            ProtocolLogger.shared.log(
                category: .rtsp,
                direction: .tx,
                title: "RTSP \(status)",
                detail: "CSeq: \(cseq)"
            )
        }
    }
}
