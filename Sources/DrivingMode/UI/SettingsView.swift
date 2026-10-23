//
//  SettingsView.swift
//  DrivingMode
//
//  Complete vehicle, display, cluster, and network settings matching 1:1 authentic layout.
//

import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var config = DrivingModeConfig.shared

    @State private var showingBrandPicker: Bool = false
    @State private var showingNameEditor: Bool = false
    @State private var showingResolutionPicker: Bool = false
    @State private var showingContentPicker: Bool = false
    @State private var showingSizePicker: Bool = false
    @State private var showPassword: Bool = false
    @State private var androidAutoEnabled: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Section 1: Car
                Section {
                    // Car name
                    Button {
                        showingNameEditor = true
                    } label: {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "car.fill", color: .blue)
                            Text("Car name")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(config.carName)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }

                    // Car logo
                    Button {
                        showingBrandPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "photo.fill", color: .green)
                            Text("Car logo")
                                .foregroundColor(.primary)
                            Spacer()
                            if let brand = CarBrandCatalog.shared.brand(for: config.selectedBrandId) {
                                Text(brand.title)
                                    .foregroundColor(.secondary)
                            }

                            // OEM Logo Preview Image
                            brandLogoThumbnail
                                .frame(width: 28, height: 28)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }

                    // Driving Position
                    HStack(spacing: 12) {
                        settingsIcon(systemName: "steeringwheel", color: .purple)
                        Text("Driving position")
                            .foregroundColor(.primary)
                        Spacer()
                        Picker("", selection: $config.drivingPosition) {
                            ForEach(DrivingPosition.allCases, id: \.self) { pos in
                                Text(pos.title).tag(pos)
                            }
                        }
                        .labelsHidden()
                    }
                } header: {
                    Text("Car")
                } footer: {
                    Text("The name the iPhone shows for this car. The logo is the car's app on the CarPlay home screen (\(CarBrandCatalog.shared.brand(for: config.selectedBrandId)?.title ?? "Lexus") until you pick one); tap it there to open this screen. Use a square image.")
                }

                // MARK: - Section 2: Wi-Fi for CarPlay
                Section {
                    HStack(spacing: 12) {
                        settingsIcon(systemName: "wifi", color: .blue)
                        Text("Network")
                            .foregroundColor(.primary)
                        Spacer()
                        TextField("Network name", text: $config.wifiSSID)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        settingsIcon(systemName: "key.fill", color: .orange)
                        Text("Password")
                            .foregroundColor(.primary)
                        Spacer()
                        if showPassword {
                            TextField("Password", text: $config.wifiPassphrase)
                                .font(.system(size: 15, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.secondary)
                        } else {
                            SecureField("Password", text: $config.wifiPassphrase)
                                .font(.system(size: 15))
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.secondary)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                        }
                    }

                    Button {
                        WiFiNetworkService.shared.requestAuthorizationAndFetchSSID { ssid in
                            if let ssid = ssid, !ssid.isEmpty {
                                config.wifiSSID = ssid
                            }
                        }
                    } label: {
                        Text("Use current Wi-Fi")
                            .foregroundColor(.blue)
                    }

                    Button {
                        if !config.wifiSSID.isEmpty {
                            WiFiNetworkService.shared.forgetPassword(for: config.wifiSSID)
                        }
                        config.wifiPassphrase = ""
                    } label: {
                        Text("Forget this network")
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Wi-Fi for CarPlay")
                } footer: {
                    Text("The Wi-Fi network This iPhone and Connect give CarPlay. iOS saves this network in the iPhone's Wi-Fi settings with exactly this password.")
                }

                // MARK: - Section 3: Display
                Section {
                    Button {
                        showingResolutionPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "display", color: Color(red: 0.85, green: 0.15, blue: 0.65))
                            Text("Resolution")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(config.displayPreset.title)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }

                    Toggle(isOn: $config.videoPlaybackAllowed) {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "play.rectangle.fill", color: .red)
                            Text("Video playback")
                        }
                    }

                    Toggle(isOn: $config.showTouches) {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "hand.point.up.fill", color: .green)
                            Text("Show touches")
                        }
                    }

                    Toggle(isOn: $config.isPortraitAllowed) {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "iphone.gen3", color: .blue)
                            Text("Portrait")
                        }
                    }

                    Toggle(isOn: $config.avoidNotch) {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "arrow.up.and.down.and.sparkles", color: .orange)
                            Text("Avoid notch")
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { config.nightMode == .on },
                        set: { config.nightMode = $0 ? .on : .off }
                    )) {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "moon.fill", color: .indigo)
                            Text("Night mode")
                        }
                    }

                    Toggle(isOn: $config.playSoundLocally) {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "speaker.wave.2.fill", color: .purple)
                            Text("Play sound here")
                        }
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Fit this screen uses this device's own screen size. Video playback lets apps show video while parked. Show touches marks each tap, for screen recordings.")
                }

                // MARK: - Section: Audio Routing
                Section {
                    Picker("Audio Output", selection: $config.audioRoutingMode) {
                        ForEach(AudioRoutingMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Audio Routing")
                } footer: {
                    Text(config.audioRoutingMode.subtitle)
                }

                // MARK: - Section 4: Instrument Cluster
                Section {
                    Toggle(isOn: $config.carPlayUltraEnabled) {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "gauge.medium", color: .orange)
                            Text("Instrument cluster")
                        }
                    }

                    if config.carPlayUltraEnabled {
                        Button {
                            showingContentPicker = true
                        } label: {
                            HStack(spacing: 12) {
                                settingsIcon(systemName: "map.fill", color: .cyan)
                                Text("Content")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(config.instrumentClusterMode.title)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        }

                        Toggle(isOn: $config.showClusterETA) {
                            HStack(spacing: 12) {
                                settingsIcon(systemName: "clock.fill", color: .purple)
                                Text("Show ETA")
                            }
                        }

                        Button {
                            showingSizePicker = true
                        } label: {
                            HStack(spacing: 12) {
                                settingsIcon(systemName: "arrow.up.left.and.arrow.down.right", color: .red)
                                Text("Size")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(config.instrumentClusterSize.title)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        }
                    }
                } header: {
                    Text("Instrument cluster")
                } footer: {
                    Text("A second CarPlay screen for maps and turn-by-turn directions, with its content, ETA and size.")
                }

                // MARK: - Section 5: Modes
                Section {
                    Toggle(isOn: $androidAutoEnabled) {
                        HStack(spacing: 12) {
                            settingsIcon(systemName: "bolt.horizontal.fill", color: .green)
                            Text("Android Auto (experimental)")
                        }
                    }
                } header: {
                    Text("Modes")
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.blue)
                    }
                }
            }
            .sheet(isPresented: $showingBrandPicker) {
                CarBrandPickerSheet(selectedBrandId: $config.selectedBrandId)
            }
            .alert("Car Name", isPresented: $showingNameEditor) {
                TextField("Car Name", text: $config.carName)
                Button("Done") {}
            }
            .confirmationDialog("Resolution Preset", isPresented: $showingResolutionPicker, titleVisibility: .visible) {
                ForEach(DisplayPreset.allCases, id: \.self) { preset in
                    Button(preset.title) {
                        config.displayPreset = preset
                    }
                }
            }
            .confirmationDialog("Cluster Content", isPresented: $showingContentPicker, titleVisibility: .visible) {
                ForEach(ClusterContentMode.allCases, id: \.self) { mode in
                    Button(mode.title) {
                        config.instrumentClusterMode = mode
                    }
                }
            }
            .confirmationDialog("Cluster Size", isPresented: $showingSizePicker, titleVisibility: .visible) {
                ForEach(ClusterSize.allCases, id: \.self) { size in
                    Button(size.title) {
                        config.instrumentClusterSize = size
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsIcon(systemName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 28)
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var brandLogoThumbnail: some View {
        #if canImport(UIKit)
        if let image = CarBrandCatalog.shared.logoImage(for: config.selectedBrandId, size: 180) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black)
                .overlay(
                    Text(config.selectedBrandId.prefix(2).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                )
        }
        #else
        Color.black
        #endif
    }
}

// MARK: - Brand Picker Sheet

public struct CarBrandPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedBrandId: String
    @State private var searchText: String = ""

    private var filteredBrands: [CarBrand] {
        if searchText.isEmpty {
            return CarBrandCatalog.shared.brands
        } else {
            return CarBrandCatalog.shared.brands.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    public var body: some View {
        NavigationStack {
            List(filteredBrands) { brand in
                Button {
                    selectedBrandId = brand.id
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        #if canImport(UIKit)
                        if let img = CarBrandCatalog.shared.logoImage(for: brand.id, size: 180) {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(brand.id.prefix(2).uppercased())
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                        #endif

                        VStack(alignment: .leading, spacing: 2) {
                            Text(brand.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                            if let oem = brand.label {
                                Text(oem)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if selectedBrandId == brand.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search 114 Car Brands")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("Car Logo")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
