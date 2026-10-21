//
//  SettingsView.swift
//  CarCast
//
//  Complete vehicle, display, cluster, and network settings matching authentic CarCast specifications.
//

import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var config = CarCastConfig.shared
    @State private var showingBrandPicker: Bool = false
    @State private var showingResetAlert: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Car Profile
                Section(header: Text("Car Profile").foregroundColor(.cyan)) {
                    HStack {
                        Text("Car Name")
                        Spacer()
                        TextField("Car Name", text: $config.carName)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.gray)
                    }

                    // Selected Car Brand & Logo Preview
                    Button {
                        showingBrandPicker = true
                    } label: {
                        HStack {
                            Text("Car Logo")
                                .foregroundColor(.primary)
                            Spacer()
                            if let brand = CarBrandCatalog.shared.brand(for: config.selectedBrandId) {
                                Text(brand.title)
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                    }

                    HStack {
                        Text("Logo Label")
                        Spacer()
                        TextField("Optional custom label", text: $config.customLogoLabel)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.gray)
                    }

                    Picker("Driving Position", selection: $config.drivingPosition) {
                        ForEach(DrivingPosition.allCases, id: \.self) { pos in
                            Text(pos.title).tag(pos)
                        }
                    }
                }

                // Section 2: Display & Screen
                Section(header: Text("Display").foregroundColor(.cyan)) {
                    Picker("Resolution Preset", selection: $config.displayPreset) {
                        ForEach(DisplayPreset.allCases, id: \.self) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }

                    Toggle("Portrait Mode (iPhone/iPad Upright)", isOn: $config.isPortraitAllowed)

                    Toggle("Avoid Notch / Dynamic Island", isOn: $config.avoidNotch)

                    Toggle("Show Touches (Recording)", isOn: $config.showTouches)

                    Toggle("Video Playback in Car", isOn: $config.videoPlaybackAllowed)

                    Picker("Night Mode", selection: $config.nightMode) {
                        ForEach(NightModeSetting.allCases, id: \.self) { nm in
                            Text(nm.title).tag(nm)
                        }
                    }
                }

                // Section 3: Audio Routing
                Section(header: Text("Audio").foregroundColor(.cyan)) {
                    Toggle("Play Sound Here", isOn: $config.playSoundLocally)
                    Text("When off, the iPhone keeps CarPlay audio so it plays through the vehicle's Bluetooth.")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                // Section 4: Instrument Cluster & CarPlay Ultra
                Section(header: Text("Instrument Cluster & CarPlay Ultra").foregroundColor(.cyan)) {
                    Toggle("CarPlay Ultra Instrument Cluster", isOn: $config.carPlayUltraEnabled)

                    Picker("Cluster Content", selection: $config.instrumentClusterMode) {
                        ForEach(ClusterContentMode.allCases, id: \.self) { cm in
                            Text(cm.title).tag(cm)
                        }
                    }

                    Picker("Cluster Size", selection: $config.instrumentClusterSize) {
                        ForEach(ClusterSize.allCases, id: \.self) { cs in
                            Text(cs.title).tag(cs)
                        }
                    }

                    Toggle("Show ETA on Cluster", isOn: $config.showClusterETA)
                }

                // Section 5: Wi-Fi for CarPlay
                Section(header: Text("Wi-Fi for CarPlay").foregroundColor(.cyan)) {
                    HStack {
                        Text("SSID")
                        Spacer()
                        TextField("SSID", text: $config.wifiSSID)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.gray)
                    }

                    HStack {
                        Text("Password")
                        Spacer()
                        SecureField("WPA2 Passphrase", text: $config.wifiPassphrase)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.gray)
                    }

                    Stepper("Wi-Fi Channel: \(config.wifiChannel)", value: $config.wifiChannel, in: 1...165)
                }

                // Section 6: Maintenance & Reset
                Section {
                    Button(role: .destructive) {
                        showingResetAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Settings")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
            .navigationTitle("CarCast Settings")
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
            .sheet(isPresented: $showingBrandPicker) {
                CarBrandPickerView(selectedBrandId: $config.selectedBrandId)
            }
            .alert("Reset All Settings?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    config.resetToDefaults()
                }
            } message: {
                Text("This will restore default vehicle identity, car logo, display presets, and network values.")
            }
        }
    }
}

struct CarBrandPickerView: View {
    @Binding var selectedBrandId: String
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""

    private var filteredBrands: [CarBrand] {
        let all = CarBrandCatalog.shared.brands
        if searchText.isEmpty {
            return all
        }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.label?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            ($0.zh?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredBrands) { brand in
                Button {
                    selectedBrandId = brand.id
                    dismiss()
                } label: {
                    HStack(spacing: 16) {
                        // Brand Logo
                        ZStack {
                            Color.white.opacity(0.08)
                            #if canImport(UIKit)
                            if let uiImg = CarBrandCatalog.shared.logoImage(for: brand.id, size: 120) {
                                Image(uiImage: uiImg)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "car.side.fill")
                                    .foregroundColor(.cyan)
                            }
                            #else
                            Image(systemName: "car.side.fill")
                                .foregroundColor(.cyan)
                            #endif
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(brand.title)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            if let zh = brand.zh {
                                Text(zh)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }

                        Spacer()

                        if brand.id == selectedBrandId {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.cyan)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color(red: 0.06, green: 0.08, blue: 0.12))
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search 114+ car brands…")
            .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
            .navigationTitle("Select Car Brand")
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
