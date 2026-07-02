//
//  SystemInfoManager+FPS.swift
//  WiggleSDK
//
//  FPS Helper 측정 결과를 오버레이 UI에 반영합니다.
//

import UIKit

extension SystemInfoManager {
    // MARK: - FPS

    @MainActor
    func startFpsReportOnMainActor() {
        guard let overlay = ensureOverlayView() else { return }

        overlay.setRowVisible(.fps, visible: true)
        fpsHelper.startMonitoring()
    }

    @MainActor
    func stopFpsReportOnMainActor() {
        fpsHelper.stopMonitoring()

        overlayView?.setRowVisible(.fps, visible: false)
        removeOverlayViewIfNeeded()
    }

    @MainActor
    func handleFpsSnapshot(_ snapshot: SystemInfoFpsHelper.Snapshot) {
        guard isFpsReport else { return }

        overlayView?.updateFps(
            text: fpsDisplayText(currentFps: snapshot.currentFps, minFps: snapshot.minFps),
            textColor: .yellow
        )
    }

    // MARK: - UI

    private func fpsDisplayText(currentFps: Int, minFps: Double) -> String {
        if currentFps > 0, minFps > 0 {
            return String(format: "%.0f (min %.0f)", Double(currentFps), minFps)
        }
        if currentFps > 0 {
            return String(format: "%.0f", Double(currentFps))
        }
        if minFps > 0 {
            return String(format: "min %.0f", minFps)
        }
        return "-"
    }
}
