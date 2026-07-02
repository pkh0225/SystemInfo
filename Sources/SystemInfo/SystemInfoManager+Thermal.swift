//
//  SystemInfoManager+Thermal.swift
//
//  Thermal Helper 관측 결과를 오버레이 UI에 반영합니다.
//

import UIKit

extension SystemInfoManager {
    // MARK: - Thermal

    @MainActor
    func startThermalReportOnMainActor() {
        guard ensureOverlayView() != nil else { return }

        overlayView?.setRowVisible(.thermal, visible: true)
        thermalHelper.startMonitoring()

        let state = thermalHelper.currentState
        if SystemInfoThermalHelper.isSeriousOrAbove(state) {
            showThermalAlert(for: state)
        }
    }

    @MainActor
    func stopThermalReportOnMainActor() {
        thermalHelper.stopMonitoring()

        setScreenWarning(.thermal, isActive: false)
        overlayView?.setRowVisible(.thermal, visible: false)
        removeOverlayViewIfNeeded()
    }

    @MainActor
    func handleThermalSnapshot(_ snapshot: SystemInfoThermalHelper.Snapshot) {
        guard isThermalReport else { return }

        updateThermalLabel(for: snapshot.state)
        guard snapshot.previousState != snapshot.state else { return }

        let current = snapshot.state
        let previous = snapshot.previousState
        guard SystemInfoThermalHelper.isSeriousOrAbove(current) else { return }
        guard !SystemInfoThermalHelper.isSeriousOrAbove(previous)
            || (previous == .serious && current == .critical) else { return }

        showThermalAlert(for: current)
    }

    // MARK: - UI

    @MainActor
    private func updateThermalLabel(for state: ProcessInfo.ThermalState) {
        overlayView?.updateThermal(
            text: SystemInfoThermalHelper.displayText(for: state),
            textColor: SystemInfoThermalHelper.isSeriousOrAbove(state) ? .red : .yellow
        )
        updateThermalWarningOverlay(for: state)
    }

    @MainActor
    private func updateThermalWarningOverlay(for state: ProcessInfo.ThermalState) {
        setScreenWarning(
            .thermal,
            isActive: SystemInfoThermalHelper.isSeriousOrAbove(state),
            value: SystemInfoThermalHelper.displayText(for: state)
        )
    }

    @MainActor
    private func showThermalAlert(for state: ProcessInfo.ThermalState) {
        let message: String
        switch state {
        case .serious:
            message = "기기 발열 상태가 심각합니다.\n성능 제한이 발생할 수 있습니다."
        case .critical:
            message = "기기 발열 상태가 위험합니다.\n앱 성능이 크게 제한될 수 있습니다."
        default:
            return
        }

        UIAlertController.alert(title: "발열 경고", message: message)
    }
}
