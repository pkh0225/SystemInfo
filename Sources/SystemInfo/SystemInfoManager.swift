//
//  SystemInfoManager.swift
//
//  리포트 on/off 진입점과 오버레이·경고 UI를 담당합니다.
//  실제 측정은 Helper가 수행하고, SystemInfoManager가 결과를 받아 UI를 갱신합니다.
//
//  - SystemInfoManager+Common.swift        : 오버레이 뷰 공통 관리
//  - SystemInfoManager+ScreenWarning.swift : 화면 경고 배지(깜빡임) UI 공통 로직
//  - SystemInfoManager+Resource.swift      : Resource Helper → 오버레이 UI
//  - SystemInfoManager+FPS.swift           : FPS Helper → 오버레이 UI
//  - SystemInfoManager+Thermal.swift       : Thermal Helper → 오버레이 UI
//

import UIKit

public class SystemInfoManager {
    public static let shared = SystemInfoManager()

    // MARK: - Measurement Helpers

    let resourceHelper = SystemInfoResourceHelper()
    let fpsHelper = SystemInfoFpsHelper()
    let thermalHelper = SystemInfoThermalHelper()

    // MARK: - Public Report Toggles

    public var isResourceReport: Bool = false {
        didSet {
            guard isResourceReport != oldValue else { return }
            let enabled = isResourceReport
            Task { @MainActor in
                if enabled {
                    self.startResourceReportOnMainActor()
                }
                else {
                    self.stopResourceReportOnMainActor()
                }
            }
        }
    }

    public var isFpsReport: Bool = false {
        didSet {
            guard isFpsReport != oldValue else { return }
            let enabled = isFpsReport
            Task { @MainActor in
                if enabled {
                    self.startFpsReportOnMainActor()
                }
                else {
                    self.stopFpsReportOnMainActor()
                }
            }
        }
    }

    public var isThermalReport: Bool = false {
        didSet {
            guard isThermalReport != oldValue else { return }
            let enabled = isThermalReport
            Task { @MainActor in
                if enabled {
                    self.startThermalReportOnMainActor()
                }
                else {
                    self.stopThermalReportOnMainActor()
                }
            }
        }
    }

    // MARK: - Overlay State (Common)

    var overlayView: SystemInfoOverlayView?

    // MARK: - Screen Warning Badge State

    var screenWarningOverlay: UIView?
    var screenWarningDimView: UIView?
    var screenWarningBadgeView: UIView?
    var screenWarningBadgeTitleLabel: UILabel?
    var screenWarningBadgeValueLabel: UILabel?
    var screenWarningIconView: UIImageView?
    var screenWarningBlinkToken: UInt = 0
    var screenWarningConditionActive: Set<ScreenWarningKind> = []
    var screenWarningPulsing: Set<ScreenWarningKind> = []
    var screenWarningSustained: Set<ScreenWarningKind> = []
    var screenWarningValues: [ScreenWarningKind: String] = [:]
    var screenWarningLastPulseEndedAt: [ScreenWarningKind: CFTimeInterval] = [:]
    var screenWarningPulseTasks: [ScreenWarningKind: Task<Void, Never>] = [:]

    // MARK: - Resource Warning State

    var consecutiveCpuHighSamples = 0
    var consecutiveCpuLowSamples = 0

    private init() {
        resourceHelper.onUpdate = { [weak self] snapshot in
            self?.handleResourceSnapshot(snapshot)
        }
        fpsHelper.onUpdate = { [weak self] snapshot in
            self?.handleFpsSnapshot(snapshot)
        }
        thermalHelper.onUpdate = { [weak self] snapshot in
            self?.handleThermalSnapshot(snapshot)
        }
    }
}
