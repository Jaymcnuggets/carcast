//
//  PairingGuideView.swift
//  CarCast
//
//  Step-by-step wireless CarPlay and AirPlay pairing guide with troubleshooting diagnostics.
//

import SwiftUI

public struct PairingGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var config = DrivingModeConfig.shared
    @ObservedObject var manager = CarPlayManager.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Banner
                    headerCard

                    // Quick Steps
                    VStack(spacing: 16) {
                        StepCard(
                            stepNumber: 1,
                            title: "Enable Wi-Fi and Bluetooth",
                            description: "Turn on both Wi-Fi and Bluetooth in your iPhone Control Center or Settings. Keep both active throughout the connection.",
                            icon: "antenna.radiowaves.left.and.right",
                            accent: .blue
                        )

                        StepCard(
                            stepNumber: 2,
                            title: "Open iOS CarPlay Settings",
                            description: "On your iPhone, navigate to Settings → General → CarPlay. Your phone will begin scanning for available wireless CarPlay vehicles.",
                            icon: "gearshape.fill",
                            accent: .orange
                        )

                        StepCard(
                            stepNumber: 3,
                            title: "Select \(config.carName)",
                            description: "Tap \"\(config.carName)\" under Available Cars. If prompted, confirm Bluetooth pairing and allow CarPlay access while phone is locked.",
                            icon: "car.fill",
                            accent: .cyan
                        )

                        StepCard(
                            stepNumber: 4,
                            title: "Enjoy Wireless CarPlay",
                            description: "CarCast will automatically authenticate the iAP2 handshake, negotiate video transport over port 7100, and display your CarPlay dashboard.",
                            icon: "checkmark.circle.fill",
                            accent: .green
                        )
                    }
                    .padding(.horizontal, 20)

                    // Alternative: Control Center AirPlay Mirroring
                    airPlayAlternativeCard

                    // Troubleshooting FAQ
                    troubleshootingSection

                    Spacer(minLength: 32)
                }
                .padding(.top, 16)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
            .navigationTitle("How to Connect")
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

    private var headerCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: 70, height: 70)
                Image(systemName: "car.side.front.open.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.cyan)
            }

            Text("Wireless CarPlay Setup")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Broadcasting as \"\(config.carName)\" on local network")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }

    private var airPlayAlternativeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "airplayvideo")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.purple)
                Text("Direct Screen Mirroring")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text("If you want to mirror your iPhone or Mac screen directly without full CarPlay:\n1. Swipe down Control Center on your Apple device.\n2. Tap the Screen Mirroring icon.\n3. Choose \"\(config.carName)\".")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.07, green: 0.09, blue: 0.14))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.purple.opacity(0.3), lineWidth: 1))
        )
        .padding(.horizontal, 20)
    }

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Troubleshooting & Tips")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                TroubleRow(
                    question: "Not showing up in CarPlay settings?",
                    answer: "Make sure Siri is enabled on your iPhone (Settings → Siri & Search). iOS requires Siri for CarPlay to function."
                )

                TroubleRow(
                    question: "Wi-Fi channel interference?",
                    answer: "In CarCast Settings, set Wi-Fi Channel to 36 or 40 (5 GHz) to avoid 2.4 GHz congestion with Bluetooth."
                )

                TroubleRow(
                    question: "Prompted for Local Network?",
                    answer: "Ensure you tapped 'Allow' when iOS prompted for Local Network permissions. You can verify this in iPhone Settings → Privacy → Local Network."
                )

                TroubleRow(
                    question: "Testing on a single device?",
                    answer: "Tap 'This iPhone' on the CarCast dashboard to launch local loopback simulation without needing a second phone."
                )
            }
            .padding(.horizontal, 20)
        }
    }
}

private struct StepCard: View {
    let stepNumber: Int
    let title: String
    let description: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.2))
                    .frame(width: 42, height: 42)
                Text("\(stepNumber)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(accent)
                }

                Text(description)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.gray)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.06, green: 0.08, blue: 0.12))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}

private struct TroubleRow: View {
    let question: String
    let answer: String
    @State private var isExpanded: Bool = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(question)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                }

                if isExpanded {
                    Text(answer)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.gray.opacity(0.9))
                        .lineSpacing(2)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.06, green: 0.08, blue: 0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
            )
        }
    }
}
