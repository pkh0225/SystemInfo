//
//  SystemInfoManager+Resource.swift
//
//  Resource Helper 측정 결과를 오버레이 UI에 반영합니다.
//

import UIKit

extension SystemInfoManager {
    private static let cpuWarningThreshold: Double = 100.0
    private static let cpuWarningTriggerConsecutiveSamples = 3
    private static let cpuWarningReleaseConsecutiveSamples = 2
    private static let memoryWarningThreshold: UInt64 = 1_052_872_704

    // MARK: - Resource (Memory + CPU)

    @MainActor
    func startResourceReportOnMainActor() {
        guard let overlay = ensureOverlayView() else { return }

        consecutiveCpuHighSamples = 0
        consecutiveCpuLowSamples = 0

        overlay.setRowVisible(.memory, visible: true)
        overlay.setRowVisible(.cpu, visible: true)

        resourceHelper.startMonitoring()
    }

    @MainActor
    func stopResourceReportOnMainActor() {
        resourceHelper.stopMonitoring()

        setSustainedScreenWarning(.cpu, isActive: false)
        overlayView?.setRowVisible(.memory, visible: false)
        overlayView?.setRowVisible(.cpu, visible: false)
        removeOverlayViewIfNeeded()

        consecutiveCpuHighSamples = 0
        consecutiveCpuLowSamples = 0
    }

    @MainActor
    func handleResourceSnapshot(_ snapshot: SystemInfoResourceHelper.Snapshot) {
        guard isResourceReport else { return }

        updateMemoryLabel(byteCount: snapshot.memoryBytes)
        updateCpuLabel(snapshot.cpuPercent)
        updateCpuWarningOverlay(
            cpuPercent: snapshot.cpuPercent,
            isBaselineSample: snapshot.isBaselineCpuSample
        )
    }

    public func memoryReport() -> UInt64 {
        resourceHelper.memoryBytes()
    }

    public func cpuUsage() -> Double {
        resourceHelper.cpuUsage()
    }

    // MARK: - UI

    @MainActor
    private func updateMemoryLabel(byteCount: UInt64) {
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useMB, .useGB]
        bcf.countStyle = .memory
        let string = bcf.string(fromByteCount: Int64(byteCount))
        overlayView?.updateMemory(
            text: string,
            textColor: byteCount > Self.memoryWarningThreshold ? .red : .yellow
        )
    }

    @MainActor
    private func updateCpuLabel(_ cpuPercent: Double) {
        overlayView?.updateCpu(
            text: String(format: "%.1f%%", cpuPercent),
            textColor: cpuPercent >= Self.cpuWarningThreshold ? .red : .yellow
        )
    }

    @MainActor
    private func updateCpuWarningOverlay(cpuPercent: Double, isBaselineSample: Bool) {
        guard !isBaselineSample else { return }

        let value = String(format: "%.0f%%", cpuPercent)

        if cpuPercent >= Self.cpuWarningThreshold {
            consecutiveCpuLowSamples = 0
            consecutiveCpuHighSamples += 1

            if consecutiveCpuHighSamples >= Self.cpuWarningTriggerConsecutiveSamples {
                setSustainedScreenWarning(.cpu, isActive: true, value: value)
            }
            else if screenWarningSustained.contains(.cpu) {
                screenWarningValues[.cpu] = value
                refreshScreenWarningOverlay()
            }
        }
        else {
            consecutiveCpuHighSamples = 0
            consecutiveCpuLowSamples += 1

            if consecutiveCpuLowSamples >= Self.cpuWarningReleaseConsecutiveSamples {
                setSustainedScreenWarning(.cpu, isActive: false)
            }
            else if screenWarningSustained.contains(.cpu) {
                screenWarningValues[.cpu] = value
                refreshScreenWarningOverlay()
            }
        }
    }
}
