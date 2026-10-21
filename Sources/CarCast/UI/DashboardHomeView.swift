//
//  DashboardHomeView.swift
//  CarCast
//
//  Main automotive cockpit dashboard for CarCast.
//

import SwiftUI

public struct DashboardHomeView: View {
    @ObservedObject var manager = CarPlayManager.shared
    @ObservedObject var config = CarCastConfig.shared

    @State private var showingSettings: Bool = false
    @State private var showingConnectSheet: Bool = false
    @State private var showingInspector: Bool = false
    @State private var showingUltraCluster: Bool = false
    @State private var activeTab: String = "carplay"

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // Background dark gradient
                Color(red: 0.04, green: 0.05, blue: 0.08)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Top Header Bar
                        headerBar

                        // Mode Selector (CarPlay, Mirroring, AirPlay)
                        modeSelector

                        // Central Vehicle Identity Card
                        vehicleCard

                        // Main Action Button (Start / Stop)
                        mainActionButton

                        // Feature Grid: This iPhone, Connect, CarPlay Ultra, Inspector
                        featureGrid

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                // If currently streaming and user returns, show floating banner to jump back into CarPlay
                if manager.state == .streaming {
                    VStack {
                        Spacer()
                        NavigationLink {
                            CarPlayActiveScreenView()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "play.tv.fill")
                                    .font(.system(size: 18))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("CarPlay is Active")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                    Text("Tap to return to fullscreen")
                                        .font(.system(size: 12, design: .rounded))
                                        .opacity(0.8)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color.cyan)
                            .clipShape(Capsule())
                            .shadow(color: Color.cyan.opacity(0.4), radius: 12, x: 0, y: 6)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                    }
                }
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingConnectSheet) {
                ConnectRemoteView()
            }
            .sheet(isPresented: $showingInspector) {
                ProtocolInspectorView()
            }
            .sheet(isPresented: $showingUltraCluster) {
                NavigationStack {
                    CarPlayUltraClusterView()
                        .navigationTitle("CarPlay Ultra Instrument Cluster")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showingUltraCluster = false
                                }
                                .foregroundColor(.cyan)
                            }
                        }
                }
            }
        }
    }

    private var headerBar: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.cyan)

                Text("CarCast")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            // Status Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(manager.state.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())

            // Settings Cog
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
        }
    }

    private var statusColor: Color {
        switch manager.state {
        case .idle: return .gray
        case .starting, .waitingForPhone, .connecting: return .yellow
        case .streaming: return .green
        case .error: return .red
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 6) {
            ModeTab(title: "CarPlay", icon: "car.fill", isSelected: activeTab == "carplay") {
                activeTab = "carplay"
            }
            ModeTab(title: "Mirror", icon: "rectangle.on.rectangle", isSelected: activeTab == "mirror") {
                activeTab = "mirror"
            }
            ModeTab(title: "AirPlay", icon: "airplayvideo", isSelected: activeTab == "airplay") {
                activeTab = "airplay"
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.05))
        .clipShape(Capsule())
    }

    private var vehicleCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Brand Avatar
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 56, height: 56)

                    Image(systemName: "car.side.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.cyan)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(config.carName)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    let brandTitle = CarBrandCatalog.shared.brand(for: config.selectedBrandId)?.title ?? "Vehicle"
                    Text("\(brandTitle) • \(config.drivingPosition.title)")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.gray)
                }

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Sub-info: Wi-Fi & Link-Local IPv6
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WI-FI NETWORK")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray)
                    Text(config.wifiSSID)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("CHANNEL")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("Ch \(config.wifiChannel) (5 GHz)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.07, green: 0.09, blue: 0.14))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    private var mainActionButton: some View {
        Button {
            if manager.state == .idle || manager.state == .error {
                manager.startReceiver()
            } else {
                manager.stopReceiver()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: manager.state == .idle ? "power" : "stop.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(manager.state == .idle ? "Start Receiver" : "Stop Receiver")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundColor(manager.state == .idle ? .black : .white)
            .background(manager.state == .idle ? Color.cyan : Color.red.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: (manager.state == .idle ? Color.cyan : Color.red).opacity(0.3), radius: 10, x: 0, y: 5)
        }
    }

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            // Feature 1: This iPhone
            Button {
                if manager.state == .idle {
                    manager.startReceiver()
                }
            } label: {
                DashboardCard(
                    icon: "iphone.gen3",
                    title: "This iPhone",
                    subtitle: "CarPlay locally",
                    accent: .blue
                )
            }

            // Feature 2: Connect
            Button {
                showingConnectSheet = true
            } label: {
                DashboardCard(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Connect",
                    subtitle: "Cast to iPad/Screen",
                    accent: .orange
                )
            }

            // Feature 3: CarPlay Ultra
            Button {
                showingUltraCluster = true
            } label: {
                DashboardCard(
                    icon: "gauge.with.needle.fill",
                    title: "CarPlay Ultra",
                    subtitle: "Cockpit Cluster",
                    accent: .purple
                )
            }

            // Feature 4: Protocol Inspector
            Button {
                showingInspector = true
            } label: {
                DashboardCard(
                    icon: "waveform.path.ecg",
                    title: "Inspector",
                    subtitle: "Live packet logs",
                    accent: .cyan
                )
            }
        }
    }
}

struct ModeTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white : Color.clear)
            .clipShape(Capsule())
        }
    }
}

struct DashboardCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(accent)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.2))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.07, green: 0.09, blue: 0.14))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}
