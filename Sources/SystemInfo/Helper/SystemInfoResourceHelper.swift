//
//  SystemInfoResourceHelper.swift
//
//  메모리·CPU 사용량 측정만 담당합니다. UI는 SystemInfoManager가 처리합니다.
//

import UIKit

final class SystemInfoResourceHelper {
    struct Snapshot {
        let memoryBytes: UInt64
        let cpuPercent: Double
        let isBaselineCpuSample: Bool
    }

    var onUpdate: (@MainActor (Snapshot) -> Void)?

    private(set) var isMonitoring = false
    private(set) var latestCpuPercent: Double = 0

    private var memoryUpdateTimer: Timer?
    private var cpuCheckTimer: Timer?
    private var lastCpuSampleMachTime: UInt64 = 0
    private var lastCpuTotalMicroseconds: UInt64 = 0
    private var cpuSampleSequence: UInt64 = 0

    private static let minimumCpuSampleInterval: TimeInterval = 0.8

    private static var machTimebase: mach_timebase_info = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return info
    }()

    // MARK: - Monitoring

    @MainActor
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        lastCpuSampleMachTime = 0
        lastCpuTotalMicroseconds = 0
        latestCpuPercent = 0

        publishSnapshot(isBaselineCpuSample: false)

        memoryUpdateTimer?.invalidate()
        memoryUpdateTimer = Timer.schedule(repeatInterval: 0.5, delayStart: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.publishSnapshot(isBaselineCpuSample: false)
            }
        }

        cpuCheckTimer?.invalidate()
        cpuCheckTimer = Timer.schedule(repeatInterval: 1.0, delayStart: false) { [weak self] _ in
            guard let self else { return }
            self.cpuSampleSequence &+= 1
            let sampleSequence = self.cpuSampleSequence
            let lastSampleMachTime = self.lastCpuSampleMachTime
            let lastTotalMicroseconds = self.lastCpuTotalMicroseconds
            Task {
                let result = await Self.measureCpuUsageDelta(
                    lastSampleMachTime: lastSampleMachTime,
                    lastTotalMicroseconds: lastTotalMicroseconds
                )
                await MainActor.run {
                    guard sampleSequence == self.cpuSampleSequence else { return }
                    guard result.isValidSample else { return }

                    self.lastCpuSampleMachTime = result.sampleMachTime
                    self.lastCpuTotalMicroseconds = result.totalMicroseconds
                    self.latestCpuPercent = result.percent
                    self.publishSnapshot(isBaselineCpuSample: result.isBaselineSample)
                }
            }
        }
    }

    @MainActor
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        memoryUpdateTimer?.invalidate()
        memoryUpdateTimer = nil
        cpuCheckTimer?.invalidate()
        cpuCheckTimer = nil

        lastCpuSampleMachTime = 0
        lastCpuTotalMicroseconds = 0
        latestCpuPercent = 0
        cpuSampleSequence = 0
    }

    // MARK: - Instant Read

    func memoryBytes() -> UInt64 {
        var info: mach_task_basic_info = mach_task_basic_info()
        var count: mach_msg_type_number_t = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            return infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { (machPtr: UnsafeMutablePointer<integer_t>) in
                return task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), machPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else {
            return 0
        }

        return info.resident_size
    }

    func cpuUsage() -> Double {
        if isMonitoring {
            return latestCpuPercent
        }
        return instantCpuUsage()
    }

    // MARK: - Private

    @MainActor
    private func publishSnapshot(isBaselineCpuSample: Bool) {
        onUpdate?(Snapshot(
            memoryBytes: memoryBytes(),
            cpuPercent: latestCpuPercent,
            isBaselineCpuSample: isBaselineCpuSample
        ))
    }

    private struct CpuUsageDeltaResult {
        let percent: Double
        let sampleMachTime: UInt64
        let totalMicroseconds: UInt64
        let isValidSample: Bool
        let isBaselineSample: Bool
    }

    @concurrent
    private static func measureCpuUsageDelta(
        lastSampleMachTime: UInt64,
        lastTotalMicroseconds: UInt64
    ) async -> CpuUsageDeltaResult {
        guard let currentTotalMicroseconds = await totalTaskCPUTimeMicroseconds() else {
            return CpuUsageDeltaResult(
                percent: -1,
                sampleMachTime: lastSampleMachTime,
                totalMicroseconds: lastTotalMicroseconds,
                isValidSample: false,
                isBaselineSample: false
            )
        }

        let now = mach_absolute_time()
        guard lastSampleMachTime > 0 else {
            return CpuUsageDeltaResult(
                percent: 0,
                sampleMachTime: now,
                totalMicroseconds: currentTotalMicroseconds,
                isValidSample: true,
                isBaselineSample: true
            )
        }

        let elapsedSeconds = await machTimeToSeconds(now - lastSampleMachTime)
        guard await elapsedSeconds >= minimumCpuSampleInterval else {
            return CpuUsageDeltaResult(
                percent: 0,
                sampleMachTime: lastSampleMachTime,
                totalMicroseconds: lastTotalMicroseconds,
                isValidSample: false,
                isBaselineSample: false
            )
        }

        guard currentTotalMicroseconds >= lastTotalMicroseconds else {
            return CpuUsageDeltaResult(
                percent: 0,
                sampleMachTime: now,
                totalMicroseconds: currentTotalMicroseconds,
                isValidSample: true,
                isBaselineSample: false
            )
        }

        let deltaMicroseconds = currentTotalMicroseconds - lastTotalMicroseconds
        let elapsedMicroseconds = elapsedSeconds * 1_000_000.0
        let rawPercent = Double(deltaMicroseconds) / elapsedMicroseconds * 100.0
        let percent = await sanitizedCpuPercent(rawPercent)
        return CpuUsageDeltaResult(
            percent: percent,
            sampleMachTime: now,
            totalMicroseconds: currentTotalMicroseconds,
            isValidSample: true,
            isBaselineSample: false
        )
    }

    private static func sanitizedCpuPercent(_ percent: Double) -> Double {
        guard percent.isFinite, percent >= 0 else { return 0 }

        let maxReasonablePercent = Double(ProcessInfo.processInfo.activeProcessorCount) * 100.0 * 2.0
        guard percent <= maxReasonablePercent else { return 0 }

        return percent
    }

    @concurrent
    private static func totalTaskCPUTimeMicroseconds() async -> UInt64? {
        var threadTimes = task_thread_times_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: threadTimes) / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &threadTimes) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { machPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), machPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return nil
        }

        return await threadTimeMicroseconds(threadTimes.user_time) &+ threadTimeMicroseconds(threadTimes.system_time)
    }

    private func instantCpuUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        defer {
            if let threadList {
                vm_deallocate(mach_task_self_, vm_address_t(UnsafePointer(threadList).pointee), vm_size_t(threadCount))
            }
        }

        let kr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard kr == KERN_SUCCESS, let threadList else {
            return -1
        }

        var totalCpu: Double = 0
        for index in 0 ..< Int(threadCount) {
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            var threadInfo = [integer_t](repeating: 0, count: Int(threadInfoCount))
            let threadKr = thread_info(
                threadList[index],
                thread_flavor_t(THREAD_BASIC_INFO),
                &threadInfo,
                &threadInfoCount
            )
            guard threadKr == KERN_SUCCESS else {
                return -1
            }

            let basicInfo = Self.convertThreadInfoToThreadBasicInfo(threadInfo)
            guard basicInfo.flags != TH_FLAGS_IDLE else { continue }

            totalCpu += (Double(basicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
        }

        return totalCpu
    }

    private static func threadTimeMicroseconds(_ time: time_value_t) -> UInt64 {
        UInt64(time.seconds) * 1_000_000 + UInt64(time.microseconds)
    }

    private static func machTimeToSeconds(_ machTime: UInt64) -> Double {
        let nanos = Double(machTime) * Double(machTimebase.numer) / Double(machTimebase.denom)
        return nanos / 1_000_000_000.0
    }

    private static func convertThreadInfoToThreadBasicInfo(_ threadInfo: [integer_t]) -> thread_basic_info {
        var result = thread_basic_info()

        result.user_time = time_value_t(seconds: threadInfo[0], microseconds: threadInfo[1])
        result.system_time = time_value_t(seconds: threadInfo[2], microseconds: threadInfo[3])
        result.cpu_usage = threadInfo[4]
        result.policy = threadInfo[5]
        result.run_state = threadInfo[6]
        result.flags = threadInfo[7]
        result.suspend_count = threadInfo[8]
        result.sleep_time = threadInfo[9]

        return result
    }
}
