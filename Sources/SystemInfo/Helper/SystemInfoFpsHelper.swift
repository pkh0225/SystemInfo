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
    private static let fpsLabelUpdateInterval: TimeInterval = 0.25
    private static let minFpsSampleInterval: TimeInterval = 0.1
    private static let minFpsTrackingDuration: TimeInterval = 10.0
    private static let minFpsWarmupDuration: TimeInterval = 2.0

    private(set) var isMonitoring = false

    private var currentFps: Int = 0
    private var displayedFps: Double = 0
    private var minFpsSamples: [(timestamp: CFTimeInterval, fps: Double)] = []
    private var lastFpsLabelUpdateTimestamp: CFTimeInterval = 0
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var windowFrameCount: Int = 0
    private var minFpsWindowStartTimestamp: CFTimeInterval = 0
    private var fpsTrackingStartTimestamp: CFTimeInterval = 0
    private var lifecycleObservers: [NSObjectProtocol] = []
    private weak var displayLink: CADisplayLink?

    @MainActor
    private var trackedMinFps: Double {
        minFpsSamples.min(by: { $0.fps < $1.fps })?.fps ?? 0
    }

    // MARK: - Monitoring

    @MainActor
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        startObservingAppLifecycle()
        startDisplayLink()
    }

    @MainActor
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        stopObservingAppLifecycle()
        stopDisplayLink()
        resetTracking()
    }

    // MARK: - Private

    @MainActor
    private func startDisplayLink() {
        stopDisplayLink()
        resetTracking()

        let link = CADisplayLink(target: self, selector: #selector(step(displayLink:)))
        link.add(to: .main, forMode: RunLoop.Mode.common)
        displayLink = link
    }

    @MainActor
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// 측정 창을 비우고 warmup을 다시 시작합니다. 기준점은 다음 콜백이 잡습니다.
    @MainActor
    private func resetTracking() {
        currentFps = 0
        displayedFps = 0
        lastFrameTimestamp = 0
        lastFpsLabelUpdateTimestamp = 0
        windowFrameCount = 0
        minFpsWindowStartTimestamp = 0
        minFpsSamples.removeAll()
        fpsTrackingStartTimestamp = CACurrentMediaTime()
    }

    /// 백그라운드 구간에는 프레임이 없으므로, 그 공백이 min FPS로 기록되지 않도록 창을 비웁니다.
    @MainActor
    private func startObservingAppLifecycle() {
        guard lifecycleObservers.isEmpty else { return }

        nonisolated(unsafe) weak let helper = self
        let names: [Notification.Name] = [
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willEnterForegroundNotification
        ]

        lifecycleObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                guard let helper else { return }
                MainActor.assumeIsolated {
                    helper.resetTracking()
                }
            }
        }
    }

    @MainActor
    private func stopObservingAppLifecycle() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers.removeAll()
    }

    @MainActor
    @objc private func step(displayLink: CADisplayLink) {
        let timestamp = displayLink.timestamp

        updateCurrentFps(at: timestamp)
        updateMinFpsWindow(at: timestamp)
        publishSnapshotIfNeeded(at: timestamp)
    }

    /// 실제 프레임 간격으로 계산합니다. 콜백이 건너뛰어지면 간격이 늘어나 값이 떨어집니다.
    @MainActor
    private func updateCurrentFps(at timestamp: CFTimeInterval) {
        defer { lastFrameTimestamp = timestamp }

        guard lastFrameTimestamp > 0 else { return }

        let frameInterval = timestamp - lastFrameTimestamp
        guard frameInterval > 0 else { return }

        let instantFps = 1.0 / frameInterval
        if displayedFps <= 0 {
            displayedFps = instantFps
        }
        else {
            displayedFps += (instantFps - displayedFps) * Self.currentFpsSmoothingFactor
        }
        currentFps = Int(displayedFps.rounded())
    }

    @MainActor
    private func updateMinFpsWindow(at timestamp: CFTimeInterval) {
        if minFpsWindowStartTimestamp == 0 {
            minFpsWindowStartTimestamp = timestamp
        }

        windowFrameCount += 1

        let windowDuration = timestamp - minFpsWindowStartTimestamp
        guard windowDuration >= Self.minFpsSampleInterval else { return }

        if timestamp - fpsTrackingStartTimestamp >= Self.minFpsWarmupDuration {
            recordMinFpsSample(Double(windowFrameCount) / windowDuration, at: timestamp)
        }

        windowFrameCount = 0
        minFpsWindowStartTimestamp = timestamp
    }

    @MainActor
    private func publishSnapshotIfNeeded(at timestamp: CFTimeInterval) {
        guard timestamp - lastFpsLabelUpdateTimestamp >= Self.fpsLabelUpdateInterval else { return }
        lastFpsLabelUpdateTimestamp = timestamp

        onUpdate?(Snapshot(currentFps: currentFps, minFps: trackedMinFps))
    }

    @MainActor
    private func recordMinFpsSample(_ fps: Double, at timestamp: CFTimeInterval) {
        minFpsSamples.append((timestamp, fps))

        // 시간순으로 쌓이므로 만료된 샘플은 항상 앞쪽에 모여 있습니다.
        let cutoff = timestamp - Self.minFpsTrackingDuration
        guard let firstAliveIndex = minFpsSamples.firstIndex(where: { $0.timestamp >= cutoff }) else {
            minFpsSamples.removeAll()
            return
        }
        if firstAliveIndex > 0 {
            minFpsSamples.removeFirst(firstAliveIndex)
        }
    }
}
