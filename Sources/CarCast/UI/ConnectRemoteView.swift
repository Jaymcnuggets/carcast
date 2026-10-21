//
//  ConnectRemoteView.swift
//  CarCast
//
//  Discovers nearby CarCast displays and connects CarPlay.
//

import SwiftUI

public struct ConnectRemoteView: View {
    @ObservedObject var browser = AirPlayBonjourBrowser.shared
    @Environment(\.dismiss) var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Radar / Scanning Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.cyan.opacity(0.15), lineWidth: 2)
                            .frame(width: 90, height: 90)
                        Circle()
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                            .frame(width: 60, height: 60)
                        Circle()
                            .fill(Color.cyan.opacity(0.2))
                            .frame(width: 36, height: 36)
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.cyan)
                    }
                    .padding(.top, 16)

                    Text("Searching for CarCast screens…")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Ensure the iPad or second device has CarCast open and is on the same Wi-Fi network.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Discovered List
                if browser.receivers.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView()
                            .tint(.cyan)
                        Text("Listening on local subnet…")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                } else {
                    List(browser.receivers) { receiver in
                        HStack(spacing: 16) {
                            Image(systemName: "ipad.landscape")
                                .font(.system(size: 24))
                                .foregroundColor(.cyan)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(receiver.name)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("CarPlay Receiver Ready")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            }

                            Spacer()

                            Button {
                                // Connect logic
                                dismiss()
                            } label: {
                                Text("Connect")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.cyan)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Color(red: 0.06, green: 0.08, blue: 0.12))
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
            .navigationTitle("Connect to Screen")
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
            .onAppear {
                browser.startScanning()
            }
            .onDisappear {
                browser.stopScanning()
            }
        }
    }
}
