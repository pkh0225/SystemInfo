//
//  SystemInfoManager+Common.swift
//
//  Resource / FPS / Thermal 3개 기능이 공통으로 사용하는
//  오버레이 뷰 생성·정리, UserDefaults 저장 로직을 담당합니다.
//

import UIKit

extension SystemInfoManager {
    enum UserDefaultsKey {
        static let resourceCheck = "WG_USERDEFAULT_DEBUG_MEMORY_CHECK"
        static let fpsCheck = "WG_USERDEFAULT_DEBUG_FPS_CHECK"
        static let thermalCheck = "WG_USERDEFAULT_DEBUG_THERMAL_CHECK"
    }

    public func loadUserDefaults() {
        let defaults = UserDefaults.standard
        isResourceReport = defaults.object(forKey: UserDefaultsKey.resourceCheck) as? Bool ?? false
        isFpsReport = defaults.object(forKey: UserDefaultsKey.fpsCheck) as? Bool ?? false
        isThermalReport = defaults.object(forKey: UserDefaultsKey.thermalCheck) as? Bool ?? false
    }

    func saveUserDefaults() {
        UserDefaults.standard.set(isResourceReport, forKey: UserDefaultsKey.resourceCheck)
        UserDefaults.standard.set(isFpsReport, forKey: UserDefaultsKey.fpsCheck)
        UserDefaults.standard.set(isThermalReport, forKey: UserDefaultsKey.thermalCheck)
    }

    @MainActor
    func ensureOverlayView() -> SystemInfoOverlayView? {
        
        if overlayView == nil {
            let overlay = SystemInfoOverlayView(frame: CGRect(
                x: 0,
                y: keyWindow()?.safeAreaInsets.top ?? .zero,
                width: 120,
                height: 20
            ))
            overlay.onLongPressDisable = { [weak self] in
                self?.confirmDisableAllReports()
            }
            overlayView = overlay
        }

        overlayView?.attachToWindowIfNeeded()
        bringOverlayToFront()
        return overlayView
    }

    @MainActor
    func bringOverlayToFront() {
        guard let window = keyWindow() else { return }

        if let screenWarningOverlay, screenWarningOverlay.superview === window {
            window.bringSubviewToFront(screenWarningOverlay)
        }
        if let overlayView, overlayView.superview === window {
            window.bringSubviewToFront(overlayView)
        }
    }

    @MainActor
    func removeOverlayViewIfNeeded() {
        guard overlayView?.hasVisibleRows != true else { return }
        overlayView?.removeFromSuperview()
        overlayView = nil
    }

    @MainActor
    private func confirmDisableAllReports() {
        UIAlertController.alert(
            title: "시스템 정보",
            message: "OFF 하시겠습니까?",
            cancelButtonTitle: "취소",
            otherButtonTitles: "확인",
            closure: { [weak self] _, buttonIndex in
                guard buttonIndex == 1 else { return }
                self?.disableAllReportsFromOverlay()
            }
        )
    }

    private func disableAllReportsFromOverlay() {
        isResourceReport = false
        isFpsReport = false
        isThermalReport = false
        saveUserDefaults()
    }
}
