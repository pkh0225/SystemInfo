//
//  SystemInfoManager+Resource.swift
//
//  Resource Helper 측정 결과를 오버레이 UI에 반영합니다.
//

import UIKit

extension SystemInfoManager {
    private static let cpuHighThreshold: Double = 100.0
    private static let cpuWarningSustainedDuration: TimeInterval = 5.0
    private static let memoryHighThreshold: UInt64 = 1_052_872_704

    private static let memoryByteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter
    }()

    // MARK: - Resource (Memory + CPU)

    @MainActor
    func startResourceReportOnMainActor() {
        guard let overlay = ensureOverlayView() else { return }

        cpuHighStartedAt = nil

        overlay.setRowVisible(.memory, visible: true)
        overlay.setRowVisible(.cpu, visible: true)

        resourceHelper.startMonitoring()
    }

    @MainActor
    func stopResourceReportOnMainActor() {
        resourceHelper.stopMonitoring()

        cpuHighStartedAt = nil
        setSustainedScreenWarning(.cpu, isActive: false)
        overlayView?.setRowVisible(.memory, visible: false)
        overlayView?.setRowVisible(.cpu, visible: false)
        removeOverlayViewIfNeeded()
    }

    @MainActor
    func handleMemorySample(_ memoryBytes: UInt64) {
        guard isResourceReport else { return }

        updateMemoryLabel(byteCount: memoryBytes)
    }

    @MainActor
    func handleCpuSample(_ cpuPercent: Double) {
        guard isResourceReport else { return }

        updateCpuLabel(cpuPercent)
        updateCpuWarning(cpuPercent: cpuPercent)
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
        let string = Self.memoryByteCountFormatter.string(fromByteCount: Int64(byteCount))
        overlayView?.updateMemory(
            text: string,
            textColor: byteCount > Self.memoryHighThreshold ? .red : .yellow
        )
    }

    @MainActor
    private func updateCpuLabel(_ cpuPercent: Double) {
        overlayView?.updateCpu(
            text: String(format: "%.1f%%", cpuPercent),
            textColor: cpuPercent >= Self.cpuHighThreshold ? .red : .yellow
        )
    }

    /// 임계값 이상이 `cpuWarningSustainedDuration` 이상 이어질 때만 화면 경고를 띄웁니다.
    @MainActor
    private func updateCpuWarning(cpuPercent: Double) {
        guard cpuPercent >= Self.cpuHighThreshold else {
            cpuHighStartedAt = nil
            if screenWarningSustained.contains(.cpu) {
                setSustainedScreenWarning(.cpu, isActive: false)
            }
            return
        }

        let now = CACurrentMediaTime()
        let startedAt = cpuHighStartedAt ?? now
        cpuHighStartedAt = startedAt

        guard now - startedAt >= Self.cpuWarningSustainedDuration else { return }

        setSustainedScreenWarning(.cpu, isActive: true, value: String(format: "%.0f%%", cpuPercent))
    }
}
