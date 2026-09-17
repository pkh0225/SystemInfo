//
//  SystemInfoResourceHelper.swift
//
//  메모리·CPU 사용량 측정만 담당합니다. UI는 SystemInfoManager가 처리합니다.
//

import UIKit

final class SystemInfoResourceHelper {
    /// 메모리와 CPU는 각자 측정해서 각자 전달합니다.
    var onMemoryUpdate: (@MainActor (UInt64) -> Void)?
    var onCpuUpdate: (@MainActor (Double) -> Void)?

    private(set) var isMonitoring = false
    private(set) var latestCpuPercent: Double = 0

    private var sampleTimer: Timer?
    private var lastCpuSampleMachTime: UInt64 = 0
    private var lastCpuTotalMicroseconds: UInt64 = 0
    private var isCpuSampleInFlight = false

    /// 메모리·CPU 공통 측정 주기.
    private static let sampleInterval: TimeInterval = 1.0
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

        resetCpuSampleState()

        sampleTimer?.invalidate()
        sampleTimer = Timer.schedule(repeatInterval: Self.sampleInterval, delayStart: false) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.sampleMemory()
                self.sampleCpu()
            }
        }
    }

    @MainActor
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        sampleTimer?.invalidate()
        sampleTimer = nil
        resetCpuSampleState()
    }

    // MARK: - Instant Read

    func memoryBytes() -> UInt64 {
        Self.readMemoryBytes()
    }

    /// 주기 샘플 중이면 캐시를 반환합니다. 아니면 드문 호출용 동기 측정(폴백)입니다.
    func cpuUsage() -> Double {
        if isMonitoring {
            return latestCpuPercent
        }
        return Self.readInstantCpuUsage()
    }

    // MARK: - Private

    @MainActor
    private func sampleMemory() {
        onMemoryUpdate?(Self.readMemoryBytes())
    }

    @MainActor
    private func sampleCpu() {
        guard !isCpuSampleInFlight else { return }
        isCpuSampleInFlight = true

        let lastSampleMachTime = lastCpuSampleMachTime
        let lastTotalMicroseconds = lastCpuTotalMicroseconds

        Task { @MainActor in
            let result = await Self.measureCpuUsageDelta(
                lastSampleMachTime: lastSampleMachTime,
                lastTotalMicroseconds: lastTotalMicroseconds
            )

            self.isCpuSampleInFlight = false

            guard self.isMonitoring, result.isValidSample else { return }

            self.lastCpuSampleMachTime = result.sampleMachTime
            self.lastCpuTotalMicroseconds = result.totalMicroseconds
            self.latestCpuPercent = result.percent
            self.onCpuUpdate?(result.percent)
        }
    }

    @MainActor
    private func resetCpuSampleState() {
        lastCpuSampleMachTime = 0
        lastCpuTotalMicroseconds = 0
        latestCpuPercent = 0
        isCpuSampleInFlight = false
    }

    private struct CpuUsageDeltaResult {
        let percent: Double
        let sampleMachTime: UInt64
        let totalMicroseconds: UInt64
        let isValidSample: Bool
    }

    @concurrent
    private static func measureCpuUsageDelta(
        lastSampleMachTime: UInt64,
        lastTotalMicroseconds: UInt64
    ) async -> CpuUsageDeltaResult {
        guard let currentTotalMicroseconds = totalTaskCPUTimeMicroseconds() else {
            return CpuUsageDeltaResult(
                percent: -1,
                sampleMachTime: lastSampleMachTime,
                totalMicroseconds: lastTotalMicroseconds,
                isValidSample: false
            )
        }

        let now = mach_absolute_time()
        guard lastSampleMachTime > 0 else {
            return CpuUsageDeltaResult(
                percent: 0,
                sampleMachTime: now,
                totalMicroseconds: currentTotalMicroseconds,
                isValidSample: true
            )
        }

        let elapsedSeconds = machTimeToSeconds(now - lastSampleMachTime)
        guard elapsedSeconds >= minimumCpuSampleInterval else {
            return CpuUsageDeltaResult(
                percent: 0,
                sampleMachTime: lastSampleMachTime,
                totalMicroseconds: lastTotalMicroseconds,
                isValidSample: false
            )
        }

        guard currentTotalMicroseconds >= lastTotalMicroseconds else {
            return CpuUsageDeltaResult(
                percent: 0,
                sampleMachTime: now,
                totalMicroseconds: currentTotalMicroseconds,
                isValidSample: true
            )
        }

        let deltaMicroseconds = currentTotalMicroseconds - lastTotalMicroseconds
        let elapsedMicroseconds = elapsedSeconds * 1_000_000.0
        let rawPercent = Double(deltaMicroseconds) / elapsedMicroseconds * 100.0
        let percent = sanitizedCpuPercent(rawPercent)
        return CpuUsageDeltaResult(
            percent: percent,
            sampleMachTime: now,
            totalMicroseconds: currentTotalMicroseconds,
            isValidSample: true
        )
    }

    /// 코어 수 × 100%가 물리적 상한입니다. 넘는 값은 0으로 버리지 않고 상한으로 자릅니다.
    private static func sanitizedCpuPercent(_ percent: Double) -> Double {
        guard percent.isFinite, percent > 0 else { return 0 }

        let maxPercent = Double(ProcessInfo.processInfo.activeProcessorCount) * 100.0
        return min(percent, maxPercent)
    }

    private struct TaskBasicSample {
        let residentBytes: UInt64
        /// 이미 종료된 스레드들의 누적 CPU 시간.
        let terminatedThreadMicroseconds: UInt64
    }

    private static func readTaskBasicSample() -> TaskBasicSample? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            return infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { (machPtr: UnsafeMutablePointer<integer_t>) in
                return task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), machPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else {
            return nil
        }

        return TaskBasicSample(
            residentBytes: info.resident_size,
            terminatedThreadMicroseconds: threadTimeMicroseconds(info.user_time) &+ threadTimeMicroseconds(info.system_time)
        )
    }

    /// 살아있는 스레드들의 누적 CPU 시간.
    private static func liveThreadCPUTimeMicroseconds() -> UInt64? {
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

        return threadTimeMicroseconds(threadTimes.user_time) &+ threadTimeMicroseconds(threadTimes.system_time)
    }

    /// 프로세스 전체 CPU 시간. 종료된 스레드와 살아있는 스레드를 함께 더하므로
    /// 스레드가 사라져도 값이 뒤로 가지 않습니다.
    private static func totalTaskCPUTimeMicroseconds() -> UInt64? {
        guard let basicSample = readTaskBasicSample(),
              let liveMicroseconds = liveThreadCPUTimeMicroseconds() else {
            return nil
        }

        return basicSample.terminatedThreadMicroseconds &+ liveMicroseconds
    }

    private static func readMemoryBytes() -> UInt64 {
        readTaskBasicSample()?.residentBytes ?? 0
    }

    /// Resource 샘플링이 꺼진 상태에서 FireLog 등 드문 동기 호출용.
    private static func readInstantCpuUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        defer {
            if let threadList {
                let byteSize = vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_act_t>.stride)
                vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)), byteSize)
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

            let basicInfo = convertThreadInfoToThreadBasicInfo(threadInfo)
            guard basicInfo.flags != TH_FLAGS_IDLE else { continue }

            totalCpu += (Double(basicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
        }

        return totalCpu
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

    private static func threadTimeMicroseconds(_ time: time_value_t) -> UInt64 {
        UInt64(time.seconds) * 1_000_000 + UInt64(time.microseconds)
    }

    private static func machTimeToSeconds(_ machTime: UInt64) -> Double {
        let nanos = Double(machTime) * Double(machTimebase.numer) / Double(machTimebase.denom)
        return nanos / 1_000_000_000.0
    }
}
