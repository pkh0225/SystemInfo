import SystemInfo
import UIKit

final class ViewController: UIViewController {
    private let manager = SystemInfoManager.shared

    private let resourceSwitch = UISwitch()
    private let fpsSwitch = UISwitch()
    private let thermalSwitch = UISwitch()
    private let memoryLabel = UILabel()
    private let cpuLabel = UILabel()
    private let thermalLabel = UILabel()
    private let hintLabel = UILabel()

    private var refreshTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SystemInfo Demo"
        view.backgroundColor = .systemBackground
        setupUI()
        bindSwitches()
        manager.loadUserDefaults()
        syncSwitchesFromManager()
        startRefreshTimer()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func setupUI() {
        memoryLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        cpuLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        thermalLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)

        hintLabel.numberOfLines = 0
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textColor = .secondaryLabel
        hintLabel.text = "토글을 켜면 화면 상단에 드래그 가능한 오버레이가 표시됩니다.\n오버레이를 길게 누르면 모든 리포트를 끌 수 있습니다."

        let stack = UIStackView(arrangedSubviews: [
            makeRow(title: "Resource (CPU / Memory)", control: resourceSwitch),
            makeRow(title: "FPS", control: fpsSwitch),
            makeRow(title: "Thermal", control: thermalSwitch),
            makeMetricRow(title: "Memory", valueLabel: memoryLabel),
            makeMetricRow(title: "CPU", valueLabel: cpuLabel),
            makeMetricRow(title: "Thermal State", valueLabel: thermalLabel),
            hintLabel,
        ])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])
    }

    private func makeRow(title: String, control: UIControl) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)

        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        return row
    }

    private func makeMetricRow(title: String, valueLabel: UILabel) -> UIStackView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel

        valueLabel.text = "-"
        valueLabel.textAlignment = .right

        let row = UIStackView(arrangedSubviews: [label, valueLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        return row
    }

    private func bindSwitches() {
        resourceSwitch.addAction(UIAction { [weak self] _ in
            self?.manager.isResourceReport = self?.resourceSwitch.isOn ?? false
        }, for: .valueChanged)

        fpsSwitch.addAction(UIAction { [weak self] _ in
            self?.manager.isFpsReport = self?.fpsSwitch.isOn ?? false
        }, for: .valueChanged)

        thermalSwitch.addAction(UIAction { [weak self] _ in
            self?.manager.isThermalReport = self?.thermalSwitch.isOn ?? false
        }, for: .valueChanged)
    }

    private func syncSwitchesFromManager() {
        resourceSwitch.isOn = manager.isResourceReport
        fpsSwitch.isOn = manager.isFpsReport
        thermalSwitch.isOn = manager.isThermalReport
    }

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshMetrics()
        }
    }

    private func refreshMetrics() {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        memoryLabel.text = formatter.string(fromByteCount: Int64(manager.memoryReport()))

        let cpu = manager.cpuUsage()
        cpuLabel.text = cpu >= 0 ? String(format: "%.1f%%", cpu) : "N/A"

        let state = ProcessInfo.processInfo.thermalState
        thermalLabel.text = thermalDisplayText(for: state)
    }

    private func thermalDisplayText(for state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "정상"
        case .fair: return "보통"
        case .serious: return "심각"
        case .critical: return "위험"
        @unknown default: return "알 수 없음"
        }
    }
}
