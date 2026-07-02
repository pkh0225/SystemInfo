import XCTest
@testable import SystemInfo

@MainActor
final class SystemInfoManagerTests: XCTestCase {
    private var manager: SystemInfoManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = SystemInfoManager.shared
        manager.isResourceReport = false
        manager.isFpsReport = false
        manager.isThermalReport = false
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    override func tearDown() async throws {
        manager.isResourceReport = false
        manager.isFpsReport = false
        manager.isThermalReport = false
        try await Task.sleep(nanoseconds: 200_000_000)
        try await super.tearDown()
    }

    func testSharedInstanceExists() {
        XCTAssertNotNil(SystemInfoManager.shared)
    }

    func testMemoryReportReturnsPositiveValue() {
        let bytes = manager.memoryReport()
        XCTAssertGreaterThan(bytes, 0)
    }

    func testCpuUsageWhenNotMonitoring() {
        XCTAssertFalse(manager.resourceHelper.isMonitoring)
        let usage = manager.cpuUsage()
        XCTAssertTrue(usage >= 0 || usage == -1)
    }

    func testResourceReportToggleStartsAndStopsMonitoring() async throws {
        manager.isResourceReport = true
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(manager.resourceHelper.isMonitoring)

        manager.isResourceReport = false
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(manager.resourceHelper.isMonitoring)
    }

    func testFpsReportToggleStartsAndStopsMonitoring() async throws {
        manager.isFpsReport = true
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(manager.fpsHelper.isMonitoring)

        manager.isFpsReport = false
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(manager.fpsHelper.isMonitoring)
    }

    func testThermalReportToggleStartsAndStopsMonitoring() async throws {
        manager.isThermalReport = true
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(manager.thermalHelper.isMonitoring)

        manager.isThermalReport = false
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(manager.thermalHelper.isMonitoring)
    }

    func testLoadUserDefaultsDoesNotCrash() {
        manager.loadUserDefaults()
    }
}

final class SystemInfoThermalHelperTests: XCTestCase {
    func testDisplayText() {
        XCTAssertEqual(SystemInfoThermalHelper.displayText(for: .nominal), "정상")
        XCTAssertEqual(SystemInfoThermalHelper.displayText(for: .fair), "보통")
        XCTAssertEqual(SystemInfoThermalHelper.displayText(for: .serious), "심각")
        XCTAssertEqual(SystemInfoThermalHelper.displayText(for: .critical), "위험")
    }

    func testIsSeriousOrAbove() {
        XCTAssertFalse(SystemInfoThermalHelper.isSeriousOrAbove(.nominal))
        XCTAssertFalse(SystemInfoThermalHelper.isSeriousOrAbove(.fair))
        XCTAssertTrue(SystemInfoThermalHelper.isSeriousOrAbove(.serious))
        XCTAssertTrue(SystemInfoThermalHelper.isSeriousOrAbove(.critical))
    }
}
