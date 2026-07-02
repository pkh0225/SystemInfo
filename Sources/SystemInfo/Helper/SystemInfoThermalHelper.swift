//
//  SystemInfoThermalHelper.swift
//
//  기기 발열 상태(ThermalState) 관측만 담당합니다. UI는 SystemInfoManager가 처리합니다.
//

import UIKit

final class SystemInfoThermalHelper {
    struct Snapshot {
        let state: ProcessInfo.ThermalState
        let previousState: ProcessInfo.ThermalState
    }

    var onUpdate: (@MainActor (Snapshot) -> Void)?

    private(set) var isMonitoring = false
    private(set) var currentState: ProcessInfo.ThermalState = .nominal

    private var thermalStateObserver: NSObjectProtocol?

    // MARK: - Monitoring

    @MainActor
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        currentState = ProcessInfo.processInfo.thermalState
        publishSnapshot(previousState: currentState)

        if thermalStateObserver == nil {
            thermalStateObserver = NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleThermalStateDidChange()
                }
            }
        }
    }

    @MainActor
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let thermalStateObserver {
            NotificationCenter.default.removeObserver(thermalStateObserver)
            self.thermalStateObserver = nil
        }

        currentState = .nominal
    }

    // MARK: - Display Utilities

    static func isSeriousOrAbove(_ state: ProcessInfo.ThermalState) -> Bool {
        state == .serious || state == .critical
    }

    static func displayText(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            return "정상"
        case .fair:
            return "보통"
        case .serious:
            return "심각"
        case .critical:
            return "위험"
        @unknown default:
            return "알 수 없음"
        }
    }

    // MARK: - Private

    @MainActor
    private func handleThermalStateDidChange() {
        let previous = currentState
        let current = ProcessInfo.processInfo.thermalState
        guard current != previous else { return }

        currentState = current
        publishSnapshot(previousState: previous)
    }

    @MainActor
    private func publishSnapshot(previousState: ProcessInfo.ThermalState) {
        onUpdate?(Snapshot(state: currentState, previousState: previousState))
    }
}
