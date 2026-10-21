//
//  ProtocolMessage.swift
//  CarCast
//
//  Structured protocol log message model for Protocol Inspector.
//

import Foundation

public enum ProtocolCategory: String, Codable, CaseIterable, Sendable {
    case iap2 = "iAP2"
    case rtsp = "RTSP"
    case airplay = "AirPlay"
    case screen = "Screen"
    case audio = "Audio"
    case bonjour = "Bonjour"
    case bluetooth = "Bluetooth"
    case system = "System"

    public var badgeColor: String {
        switch self {
        case .iap2: return "cyan"
        case .rtsp: return "purple"
        case .airplay: return "blue"
        case .screen: return "green"
        case .audio: return "yellow"
        case .bonjour: return "orange"
        case .bluetooth: return "indigo"
        case .system: return "gray"
        }
    }
}

public enum MessageDirection: String, Codable, Sendable {
    case rx = "RX ◀"
    case tx = "TX ▶"
    case `internal` = "INT ●"
}

public struct ProtocolMessage: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let category: ProtocolCategory
    public let direction: MessageDirection
    public let title: String
    public let detail: String
    public let rawData: Data?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: ProtocolCategory,
        direction: MessageDirection,
        title: String,
        detail: String,
        rawData: Data? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.direction = direction
        self.title = title
        self.detail = detail
        self.rawData = rawData
    }

    public var hexDump: String? {
        guard let data = rawData, !data.isEmpty else { return nil }
        var result = ""
        let count = data.count
        let bytes = [UInt8](data)
        for i in stride(from: 0, to: min(count, 256), by: 16) {
            let chunk = bytes[i..<min(i + 16, count)]
            let hexStr = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            let padding = String(repeating: "   ", count: max(0, 16 - chunk.count))
            let asciiStr = chunk.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            result += String(format: "%04X:  %@%@  |%@|\n", i, hexStr, padding, asciiStr)
        }
        if count > 256 {
            result += "... (\(count - 256) more bytes)"
        }
        return result
    }
}

@MainActor
public final class ProtocolLogger: ObservableObject {
    public static let shared = ProtocolLogger()

    @Published public private(set) var messages: [ProtocolMessage] = []
    private let maxMessages = 1000

    private init() {}

    public func log(
        category: ProtocolCategory,
        direction: MessageDirection = .internal,
        title: String,
        detail: String = "",
        rawData: Data? = nil
    ) {
        let msg = ProtocolMessage(
            category: category,
            direction: direction,
            title: title,
            detail: detail,
            rawData: rawData
        )
        messages.append(msg)
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }

    public func clear() {
        messages.removeAll()
    }
}
