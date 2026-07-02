//
//  SystemInfoFpsHelper.swift
//
//  CADisplayLink 기반 FPS 측정만 담당합니다. UI는 SystemInfoManager가 처리합니다.
//

import UIKit

final class SystemInfoFpsHelper: NSObject {
    struct Snapshot {
        let currentFps: Int
        let minFps: Double
    }

    var onUpdate: (@MainActor (Snapshot) -> Void)?

    private static let currentFpsSmoothingFactor: Double = 0.2
    private static let fpsLabelUpdateInterval: TimeInterval = 0.1
    private static let minFpsSampleInterval: TimeInterval = 0.1
    private static let minFpsTrackingDuration: TimeInterval = 10.0
    private static let minFpsWarmupDuration: TimeInterval = 2.0
    private static let minFpsMinimumFramesPerWindow = 3

    private(set) var isMonitoring = false

    private var currentFps: Int = 0
    private var displayedFps: Double = 0
    private var minFpsSamples: [(timestamp: CFTimeInterval, fps: Double)] = []
    private var lastFpsLabelUpdateTimestamp: CFTimeInterval = 0
    private var firstFrameCount: Int = 0
    private var minFpsWindowStartTimestamp: CFTimeInterval = 0
    private var fpsTrackingStartTimestamp: CFTimeInterval = 0
    private weak var displayLink: CADisplayLink?

    private var trackedMinFps: Double {
        guard minFpsSamples.isEmpty == false else { return 0 }
        return minFpsSamples.map(\.fps).min() ?? 0
    }

    // MARK: - Monitoring

    @MainActor
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        startDisplayLink()
    }

    @MainActor
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        stopDisplayLink()
        currentFps = 0
        displayedFps = 0
        minFpsSamples.removeAll()
        firstFrameCount = 0
        minFpsWindowStartTimestamp = 0
        fpsTrackingStartTimestamp = 0
        lastFpsLabelUpdateTimestamp = 0
    }

    // MARK: - Private

    @MainActor
    private func startDisplayLink() {
        stopDisplayLink()

        let link = CADisplayLink(target: self, selector: #selector(step(displayLink:)))
        let maxFPS = Float(UIScreen.main.maximumFramesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: maxFPS, preferred: maxFPS)
        displayedFps = 0
        minFpsWindowStartTimestamp = 0
        fpsTrackingStartTimestamp = CACurrentMediaTime()
        lastFpsLabelUpdateTimestamp = 0
        link.add(to: .main, forMode: RunLoop.Mode.common)
        displayLink = link
    }

    @MainActor
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(displayLink: CADisplayLink) {
        let timestamp = displayLink.timestamp

        if minFpsWindowStartTimestamp == 0 {
            minFpsWindowStartTimestamp = timestamp
        }

        if displayLink.duration > 0 {
            let instantFps = 1.0 / displayLink.duration
            if displayedFps <= 0 {
                displayedFps = instantFps
            }
            else {
                displayedFps += (instantFps - displayedFps) * Self.currentFpsSmoothingFactor
            }
            currentFps = Int(displayedFps.rounded())
        }

        firstFrameCount += 1

        let minFpsWindowDuration = timestamp - minFpsWindowStartTimestamp
        if minFpsWindowDuration >= Self.minFpsSampleInterval {
            let trackingElapsed = timestamp - fpsTrackingStartTimestamp
            if trackingElapsed >= Self.minFpsWarmupDuration,
               firstFrameCount >= Self.minFpsMinimumFramesPerWindow {
                let windowFps = Double(firstFrameCount) / minFpsWindowDuration
                recordMinFpsSample(windowFps, at: timestamp)
            }
            firstFrameCount = 0
            minFpsWindowStartTimestamp = timestamp
        }

        scheduleUpdate(at: timestamp)
    }

    private func scheduleUpdate(at timestamp: CFTimeInterval) {
        guard timestamp - lastFpsLabelUpdateTimestamp >= Self.fpsLabelUpdateInterval else { return }
        lastFpsLabelUpdateTimestamp = timestamp
        Task { @MainActor [weak self] in
            self?.publishSnapshot()
        }
    }

    @MainActor
    private func publishSnapshot() {
        onUpdate?(Snapshot(currentFps: currentFps, minFps: trackedMinFps))
    }

    private func recordMinFpsSample(_ fps: Double, at timestamp: CFTimeInterval) {
        minFpsSamples.append((timestamp, fps))
        let cutoff = timestamp - Self.minFpsTrackingDuration
        minFpsSamples.removeAll { $0.timestamp < cutoff }
    }
}
