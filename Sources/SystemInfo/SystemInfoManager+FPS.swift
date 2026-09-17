//
//  SystemInfoManager+FPS.swift
//
//  FPS Helper 측정 결과를 오버레이 UI에 반영합니다.
//

import UIKit

extension SystemInfoManager {
    /// 기기 주사율의 이 비율보다 낮으면 경고색으로 표시합니다. (120Hz → 60, 60Hz → 30)
    private static let minFpsWarningRatio: Double = 0.33

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
            textColor: isMinFpsWarning(snapshot.minFps) ? .red : .yellow
        )
    }

    // MARK: - UI

    /// 순간값(currentFps)은 스크롤 시작 등에서 자연히 흔들리므로 10초 창의 최저값으로만 판정합니다.
    @MainActor
    private func isMinFpsWarning(_ minFps: Double) -> Bool {
        guard minFps > 0 else { return false }

        let maximumFramesPerSecond = keyWindow()?.screen.maximumFramesPerSecond ?? 60
        return minFps < Double(maximumFramesPerSecond) * Self.minFpsWarningRatio
    }

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
