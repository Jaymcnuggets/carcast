//
//  ProtocolInspectorView.swift
//  CarCast
//
//  Live Protocol Inspector for real-time iAP2, RTSP, and AirPlay packet inspection.
//

import SwiftUI

public struct ProtocolInspectorView: View {
    @ObservedObject var logger = ProtocolLogger.shared
    @State private var selectedCategory: ProtocolCategory? = nil
    @State private var searchText: String = ""
    @State private var selectedMessage: ProtocolMessage? = nil

    public init() {}

    private var filteredMessages: [ProtocolMessage] {
        return logger.messages.reversed().filter { msg in
            let matchCategory = selectedCategory == nil || msg.category == selectedCategory
            let matchSearch = searchText.isEmpty ||
                msg.title.localizedCaseInsensitiveContains(searchText) ||
                msg.detail.localizedCaseInsensitiveContains(searchText)
            return matchCategory && matchSearch
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        FilterPill(title: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(ProtocolCategory.allCases, id: \.self) { cat in
                            FilterPill(title: cat.rawValue, isSelected: selectedCategory == cat) {
                                selectedCategory = cat
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(Color(red: 0.08, green: 0.10, blue: 0.15))

                // Packet List
                if filteredMessages.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 48))
                            .foregroundColor(.gray.opacity(0.4))
                        Text("No Protocol Events")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.gray)
                        Text("Connect a phone or start receiver to inspect packets in real time.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(filteredMessages) { msg in
                            Button {
                                selectedMessage = msg
                            } label: {
                                ProtocolRowView(message: msg)
                            }
                            .listRowBackground(Color(red: 0.05, green: 0.07, blue: 0.11))
                            .listRowSeparatorTint(Color.white.opacity(0.08))
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Search protocol messages…")
            .navigationTitle("Protocol Inspector")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        logger.clear()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
            }
            .sheet(item: $selectedMessage) { msg in
                ProtocolDetailModal(message: msg)
            }
        }
    }
}

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(isSelected ? .black : .white.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? Color.cyan : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}

struct ProtocolRowView: View {
    let message: ProtocolMessage

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: message.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Category Pill
                Text(message.category.rawValue)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.18))
                    .foregroundColor(.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Direction
                Text(message.direction.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(message.direction == .rx ? .green : (message.direction == .tx ? .orange : .gray))

                Spacer()

                // Timestamp
                Text(timeString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }

            Text(message.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            if !message.detail.isEmpty {
                Text(message.detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProtocolDetailModal: View {
    let message: ProtocolMessage
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header metadata
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(message.category.rawValue)
                                .font(.system(size: 12, weight: .heavy))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.cyan.opacity(0.2))
                                .foregroundColor(.cyan)
                                .clipShape(Capsule())

                            Text(message.direction.rawValue)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))

                            Spacer()

                            Text(message.timestamp.formatted())
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }

                        Text(message.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Detail text
                    if !message.detail.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Summary & Decoded Fields")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.gray)
                            Text(message.detail)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Hex Dump
                    if let hex = message.hexDump {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hex & ASCII Payload")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.gray)
                            Text(hex)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.cyan.opacity(0.9))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
            }
            .background(Color(red: 0.05, green: 0.07, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Message Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                }
            }
        }
    }
}
