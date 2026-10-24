import Foundation
import SceneKit
import UIKit

/// Owns only rendering policy, never the ARSession or captured project data.
/// Each view releases its observers in dismantleUIView; notifications also
/// adapt an idle viewer, without requiring a new SwiftUI state update.
@MainActor
final class QTOScenePerformanceController {
    private weak var view: SCNView?
    private var profile: SpatialScanPerformanceProfile = .balanced
    private var observers: [NSObjectProtocol] = []
    private var isBackgrounded = false

    func attach(to view: SCNView, profile: SpatialScanPerformanceProfile) {
        stop()
        self.view = view
        self.profile = profile
        isBackgrounded = UIApplication.shared.applicationState != .active
        _ = ProcessInfo.processInfo.thermalState
        let names: [Notification.Name] = [
            ProcessInfo.thermalStateDidChangeNotification,
            .NSProcessInfoPowerStateDidChange,
            UIApplication.willResignActiveNotification,
            UIApplication.didBecomeActiveNotification,
            UIApplication.didReceiveMemoryWarningNotification
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                let name = notification.name
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if name == UIApplication.willResignActiveNotification { self.isBackgrounded = true }
                    if name == UIApplication.didBecomeActiveNotification { self.isBackgrounded = false }
                    if name == UIApplication.didReceiveMemoryWarningNotification { WallPhotoStorage.purgeMemoryCaches() }
                    self.refresh()
                }
            }
        }
        refresh()
    }

    func refresh(profile: SpatialScanPerformanceProfile? = nil) {
        if let profile { self.profile = profile }
        guard let view else { return }
        let budget = QTOFrameBudget.resolve(
            requestedFPS: self.profile.viewerFramesPerSecond,
            antialiasing: self.profile.viewerAntialiasingLevel,
            thermalLevel: ProcessInfo.processInfo.thermalState.rawValue,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        view.preferredFramesPerSecond = budget.framesPerSecond
        switch budget.antialiasing {
        case 4: view.antialiasingMode = .multisampling4X
        case 2: view.antialiasingMode = .multisampling2X
        default: view.antialiasingMode = .none
        }
        view.isPlaying = !isBackgrounded
        view.scene?.rootNode.enumerateChildNodes { node, _ in
            // Only lights owned by the snapshot viewer are managed here.
            if node.name == "qto-snapshot-key-light" {
                node.light?.castsShadow = budget.allowsShadows
            }
        }
    }

    func stop() {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
        view = nil
    }

    deinit {
        for token in observers { NotificationCenter.default.removeObserver(token) }
    }
}
