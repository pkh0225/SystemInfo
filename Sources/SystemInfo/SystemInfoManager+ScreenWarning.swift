//
//  SystemInfoManager+ScreenWarning.swift
//
//  CPU / Thermal 경고 발생 시 화면 전체에 표시되는
//  딤(dim) + 배지 깜빡임 오버레이의 공통 로직입니다.
//

import UIKit

extension SystemInfoManager {
    enum ScreenWarningKind: CaseIterable {
        case cpu
        case thermal
    }

    private static let thermalWarningDisplayDuration: TimeInterval = 2.0
    private static let thermalWarningCooldown: TimeInterval = 6.0

    private struct ScreenWarningPresentation {
        let dimColor: UIColor
        let badgeBackground: UIColor
        let title: String
        let iconName: String
    }

    @MainActor
    func setSustainedScreenWarning(_ kind: ScreenWarningKind, isActive: Bool, value: String = "") {
        if isActive {
            screenWarningValues[kind] = value
            screenWarningSustained.insert(kind)
            refreshScreenWarningOverlay()
        }
        else {
            screenWarningSustained.remove(kind)
            screenWarningValues.removeValue(forKey: kind)
            refreshScreenWarningOverlay()
        }
    }

    @MainActor
    func setScreenWarning(_ kind: ScreenWarningKind, isActive: Bool, value: String = "") {
        if isActive {
            screenWarningValues[kind] = value
            screenWarningConditionActive.insert(kind)

            if screenWarningPulsing.contains(kind) {
                refreshScreenWarningOverlay()
            }
            else if canRetriggerScreenWarning(kind) {
                beginScreenWarningPulse(kind)
            }
        }
        else {
            screenWarningConditionActive.remove(kind)
            screenWarningValues.removeValue(forKey: kind)
            screenWarningLastPulseEndedAt.removeValue(forKey: kind)
            endScreenWarningPulse(kind)
        }
    }

    @MainActor
    private func canRetriggerScreenWarning(_ kind: ScreenWarningKind) -> Bool {
        guard let lastEnded = screenWarningLastPulseEndedAt[kind] else { return true }
        return CACurrentMediaTime() - lastEnded >= Self.screenWarningCooldown(for: kind)
    }

    @MainActor
    private func beginScreenWarningPulse(_ kind: ScreenWarningKind) {
        screenWarningPulseTasks[kind]?.cancel()
        screenWarningPulsing.insert(kind)
        refreshScreenWarningOverlay()

        let duration = Self.screenWarningDisplayDuration(for: kind)
        screenWarningPulseTasks[kind] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.endScreenWarningPulse(kind)
        }
    }

    @MainActor
    private func endScreenWarningPulse(_ kind: ScreenWarningKind) {
        screenWarningPulseTasks[kind]?.cancel()
        screenWarningPulseTasks.removeValue(forKey: kind)
        screenWarningPulsing.remove(kind)
        screenWarningLastPulseEndedAt[kind] = CACurrentMediaTime()
        refreshScreenWarningOverlay()

        guard screenWarningConditionActive.contains(kind) else { return }

        let cooldown = Self.screenWarningCooldown(for: kind)
        screenWarningPulseTasks[kind] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(cooldown * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.screenWarningConditionActive.contains(kind) else { return }
            self.beginScreenWarningPulse(kind)
        }
    }

    private static func screenWarningPriority(_ kind: ScreenWarningKind) -> Int {
        switch kind {
        case .thermal:
            return 2
        case .cpu:
            return 1
        }
    }

    private static func screenWarningDisplayDuration(for kind: ScreenWarningKind) -> TimeInterval {
        switch kind {
        case .cpu:
            return 0
        case .thermal:
            return thermalWarningDisplayDuration
        }
    }

    private static func screenWarningCooldown(for kind: ScreenWarningKind) -> TimeInterval {
        switch kind {
        case .cpu:
            return 0
        case .thermal:
            return thermalWarningCooldown
        }
    }

    private static func presentation(for kind: ScreenWarningKind) -> ScreenWarningPresentation {
        switch kind {
        case .cpu:
            return ScreenWarningPresentation(
                dimColor: UIColor(red: 1, green: 0, blue: 0, alpha: 1),
                badgeBackground: UIColor(red: 0.55, green: 0, blue: 0, alpha: 0.38),
                title: "CPU 과부하",
                iconName: "cpu"
            )
        case .thermal:
            return ScreenWarningPresentation(
                dimColor: UIColor(red: 1, green: 0.2, blue: 0, alpha: 1),
                badgeBackground: UIColor(red: 0.55, green: 0.15, blue: 0, alpha: 0.38),
                title: "발열 경고",
                iconName: "thermometer.medium"
            )
        }
    }

    @MainActor
    func refreshScreenWarningOverlay() {
        let visibleKinds = ScreenWarningKind.allCases.filter {
            screenWarningSustained.contains($0) || screenWarningPulsing.contains($0)
        }
        guard let kind = visibleKinds.max(by: { Self.screenWarningPriority($0) < Self.screenWarningPriority($1) }),
              let value = screenWarningValues[kind] else {
            hideScreenWarningOverlay()
            return
        }
        showScreenWarningOverlay(kind: kind, value: value)
    }

    @MainActor
    private func showScreenWarningOverlay(kind: ScreenWarningKind, value: String) {
        guard let window = keyWindow() else { return }
        let presentation = Self.presentation(for: kind)

        if screenWarningOverlay == nil {
            let container = UIView(frame: window.bounds)
            container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.isUserInteractionEnabled = false

            let dimView = UIView(frame: container.bounds)
            dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(dimView)

            let badgeView = UIView()
            badgeView.layer.cornerRadius = 10
            badgeView.layer.borderWidth = 1
            badgeView.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor

            let iconView = UIImageView()
            iconView.tintColor = UIColor.white.withAlphaComponent(0.85)
            iconView.contentMode = .scaleAspectFit

            let titleLabel = UILabel()
            titleLabel.font = .boldSystemFont(ofSize: 14)
            titleLabel.textColor = UIColor.white.withAlphaComponent(0.85)
            titleLabel.textAlignment = .center

            let valueLabel = UILabel()
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
            valueLabel.textColor = UIColor.white.withAlphaComponent(0.9)
            valueLabel.textAlignment = .center

            badgeView.addSubview(iconView)
            badgeView.addSubview(titleLabel)
            badgeView.addSubview(valueLabel)
            container.addSubview(badgeView)

            let badgeWidth: CGFloat = 156
            let badgeHeight: CGFloat = 88
            badgeView.frame = CGRect(
                x: (container.bounds.width - badgeWidth) / 2,
                y: (container.bounds.height - badgeHeight) / 2,
                width: badgeWidth,
                height: badgeHeight
            )
            iconView.frame = CGRect(x: (badgeWidth - 24) / 2, y: 10, width: 24, height: 24)
            titleLabel.frame = CGRect(x: 10, y: 36, width: badgeWidth - 20, height: 18)
            valueLabel.frame = CGRect(x: 10, y: 56, width: badgeWidth - 20, height: 22)

            window.addSubview(container)
            screenWarningOverlay = container
            screenWarningDimView = dimView
            screenWarningBadgeView = badgeView
            screenWarningBadgeTitleLabel = titleLabel
            screenWarningBadgeValueLabel = valueLabel
            screenWarningIconView = iconView
            startScreenWarningBlink()
        }
        else if screenWarningOverlay?.superview !== window {
            window.addSubview(screenWarningOverlay!)
        }

        screenWarningDimView?.backgroundColor = presentation.dimColor
        screenWarningBadgeView?.backgroundColor = presentation.badgeBackground
        screenWarningBadgeTitleLabel?.text = presentation.title
        screenWarningIconView?.image = UIImage(
            systemName: presentation.iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        screenWarningBadgeValueLabel?.text = value
        bringOverlayToFront()

        if screenWarningDimView?.layer.animationKeys()?.isEmpty != false {
            startScreenWarningBlink()
        }
    }

    @MainActor
    private func startScreenWarningBlink() {
        guard let dimView = screenWarningDimView, let badgeView = screenWarningBadgeView else { return }

        dimView.layer.removeAllAnimations()
        badgeView.layer.removeAllAnimations()
        screenWarningBlinkToken &+= 1
        let token = screenWarningBlinkToken
        dimView.alpha = 0.25
        badgeView.alpha = 0.45
        runScreenWarningBlinkCycle(dimView: dimView, badgeView: badgeView, token: token)
    }

    @MainActor
    private func runScreenWarningBlinkCycle(dimView: UIView, badgeView: UIView, token: UInt) {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            dimView.alpha = 0.7
            badgeView.alpha = 0.62
        } completion: { [weak self] finished in
            guard let self, finished, token == self.screenWarningBlinkToken else { return }

            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                dimView.alpha = 0.25
                badgeView.alpha = 0.45
            } completion: { [weak self] finished in
                guard let self,
                      finished,
                      token == self.screenWarningBlinkToken,
                      dimView.superview != nil else { return }

                self.runScreenWarningBlinkCycle(dimView: dimView, badgeView: badgeView, token: token)
            }
        }
    }

    @MainActor
    private func hideScreenWarningOverlay() {
        screenWarningBlinkToken &+= 1
        screenWarningDimView?.layer.removeAllAnimations()
        screenWarningBadgeView?.layer.removeAllAnimations()
        screenWarningOverlay?.removeFromSuperview()
        screenWarningOverlay = nil
        screenWarningDimView = nil
        screenWarningBadgeView = nil
        screenWarningBadgeTitleLabel = nil
        screenWarningBadgeValueLabel = nil
        screenWarningIconView = nil
    }

    @MainActor
    func cancelAllScreenWarningPulses() {
        ScreenWarningKind.allCases.forEach { kind in
            screenWarningPulseTasks[kind]?.cancel()
            screenWarningPulseTasks.removeValue(forKey: kind)
            screenWarningPulsing.remove(kind)
        }
        screenWarningSustained.removeAll()
        screenWarningConditionActive.removeAll()
        screenWarningValues.removeAll()
        screenWarningLastPulseEndedAt.removeAll()
        hideScreenWarningOverlay()
    }
}
