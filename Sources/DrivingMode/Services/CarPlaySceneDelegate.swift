//
//  CarPlaySceneDelegate.swift
//  DrivingMode
//
//  Native Apple CarPlay framework integration, conforming to:
//  - CPTemplateApplicationSceneDelegate (Main Head Unit)
//  - CPTemplateApplicationDashboardSceneDelegate (CarPlay Dashboard)
//  - CPTemplateApplicationInstrumentClusterSceneDelegate (Next-Gen Instrument Cluster)
//

import Foundation

#if canImport(CarPlay) && os(iOS)
import CarPlay
import UIKit

@available(iOS 14.0, *)
public class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPTemplateApplicationDashboardSceneDelegate, CPTemplateApplicationInstrumentClusterSceneDelegate {

    public var interfaceController: CPInterfaceController?
    public var dashboardController: CPDashboardController?
    public var instrumentClusterController: CPInstrumentClusterController?

    // MARK: - CPTemplateApplicationSceneDelegate (Main In-Dash Screen)

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController

        // Configure Native Map Template as Root
        let mapTemplate = CPMapTemplate()

        // Search Button
        let searchButton = CPBarButton(type: .image) { _ in
            // Present Native Search
        }
        searchButton.image = UIImage(systemName: "magnifyingglass")

        // Settings Button
        let settingsButton = CPBarButton(type: .image) { _ in
            // Present Settings
        }
        settingsButton.image = UIImage(systemName: "gearshape.fill")

        mapTemplate.trailingNavigationBarButtons = [searchButton, settingsButton]

        // Trip Estimates & Route Guidance
        let trip = CPTrip(
            origin: MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0311))),
            destination: MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))),
            routeChoices: []
        )
        let estimate = CPTravelEstimates(distanceRemaining: Measurement(value: 5.2, unit: .miles), timeRemaining: 18 * 60)
        mapTemplate.updateEstimates(estimate, for: trip)

        // Set Root
        interfaceController.setRootTemplate(mapTemplate, animated: false, completion: nil)

        ProtocolLogger.shared.log(
            category: .system,
            title: "Native CarPlay Connected",
            detail: "CPTemplateApplicationScene connected"
        )
    }

    public func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        self.interfaceController = nil
        ProtocolLogger.shared.log(
            category: .system,
            title: "Native CarPlay Disconnected",
            detail: "CPTemplateApplicationScene disconnected"
        )
    }

    // MARK: - CPTemplateApplicationDashboardSceneDelegate (Dashboard Multi-Widget)

    public func dashboardController(_ dashboardController: CPDashboardController, didConnect dashboardScene: CPTemplateApplicationDashboardScene) {
        self.dashboardController = dashboardController

        let navShortcut = CPDashboardButton(
            titleVariants: ["Navigate", "Nav"],
            subtitleVariants: ["Work", "Route"],
            image: UIImage(systemName: "location.fill")!
        ) { _ in
            // Shortcut trigger
        }

        dashboardController.shortcutButtons = [navShortcut]

        ProtocolLogger.shared.log(
            category: .system,
            title: "CarPlay Dashboard Active",
            detail: "CPDashboardController connected"
        )
    }

    // MARK: - CPTemplateApplicationInstrumentClusterSceneDelegate (Cluster Screen)

    public func instrumentClusterController(_ instrumentClusterController: CPInstrumentClusterController, didConnect instrumentClusterScene: CPTemplateApplicationInstrumentClusterScene) {
        self.instrumentClusterController = instrumentClusterController

        ProtocolLogger.shared.log(
            category: .system,
            title: "CarPlay Cluster Active",
            detail: "CPInstrumentClusterController connected"
        )
    }
}
#endif
