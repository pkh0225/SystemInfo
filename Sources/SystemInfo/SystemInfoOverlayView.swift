//
//  SystemInfoOverlayView.swift
//
//

import UIKit
import DragAbleView

public class SystemInfoOverlayView: DragAbleView {
    enum Row: Int, CaseIterable {
        case cpu
        case memory
        case fps
        case thermal
    }

    private final class RowView: UIView {
        let iconView = UIImageView()
        let valueLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = UIColor.white.withAlphaComponent(0.95)
            iconView.layer.shadowColor = UIColor.black.cgColor
            iconView.layer.shadowOffset = .zero
            iconView.layer.shadowRadius = 1.5
            iconView.layer.shadowOpacity = 0.75

            valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            valueLabel.textColor = .yellow
            valueLabel.layer.shadowColor = UIColor.black.cgColor
            valueLabel.layer.shadowOffset = .zero
            valueLabel.layer.shadowRadius = 1.5
            valueLabel.layer.shadowOpacity = 0.85
            addSubview(iconView)
            addSubview(valueLabel)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func applyValueAppearance(textColor: UIColor) {
            let isWarning = textColor == .red

            if isWarning {
                let warningColor = UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 1)
                valueLabel.textColor = warningColor
                valueLabel.layer.shadowOpacity = 0
                iconView.tintColor = warningColor
                iconView.layer.shadowOpacity = 0
            }
            else {
                valueLabel.textColor = UIColor.systemYellow
                valueLabel.layer.shadowColor = UIColor.black.cgColor
                valueLabel.layer.shadowOffset = .zero
                valueLabel.layer.shadowRadius = 1.5
                valueLabel.layer.shadowOpacity = 0.85
                iconView.tintColor = UIColor.white.withAlphaComponent(0.95)
                iconView.layer.shadowColor = UIColor.black.cgColor
                iconView.layer.shadowOffset = .zero
                iconView.layer.shadowRadius = 1.5
                iconView.layer.shadowOpacity = 0.75
            }
        }

        func layoutContent(iconSize: CGFloat, spacing: CGFloat) {
            iconView.frame = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
            valueLabel.sizeToFit()
            let rowHeight = max(iconSize, valueLabel.frame.height)
            iconView.frame.origin.y = (rowHeight - iconSize) / 2
            valueLabel.frame = CGRect(
                x: iconSize + spacing,
                y: (rowHeight - valueLabel.frame.height) / 2,
                width: valueLabel.frame.width,
                height: valueLabel.frame.height
            )
            frame.size = CGSize(width: valueLabel.frame.maxX, height: rowHeight)
        }
    }

    var onLongPressDisable: (() -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private var rowViews: [Row: RowView] = [:]
    private var isDragConfigured = false

    private static let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)

    override public init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hasVisibleRows: Bool {
        Row.allCases.contains { rowViews[$0]?.isHidden == false }
    }

    func attachToWindowIfNeeded() {
        guard let window = keyWindow() else { return }

        if superview !== window {
            window.addSubview(self)
        }

        if isDragConfigured == false {
            setContainerView(
                containerView: window,
                setBoundsIntoBoundary: UIEdgeInsets(
                    top: window.safeAreaInsets.top,
                    left: 0,
                    bottom: window.safeAreaInsets.bottom,
                    right: 0
                )
            )
            isDragConfigured = true
        }

        window.bringSubviewToFront(self)
    }

    public override func removeFromSuperview() {
        super.removeFromSuperview()
        isDragConfigured = false
    }

    func setRowVisible(_ row: Row, visible: Bool) {
        rowView(for: row).isHidden = !visible
        relayoutContent()
    }

    func updateMemory(text: String, textColor: UIColor) {
        updateRow(.memory, text: text, textColor: textColor)
    }

    func updateCpu(text: String, textColor: UIColor) {
        updateRow(.cpu, text: text, textColor: textColor)
    }

    func updateFps(text: String, textColor: UIColor) {
        updateRow(.fps, text: text, textColor: textColor)
    }

    func updateThermal(text: String, textColor: UIColor) {
        updateRow(.thermal, text: text, textColor: textColor)
    }

    private func setupUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.18)
        cornerRadius = 8
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.26).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)

        blurView.isUserInteractionEnabled = false
        blurView.alpha = 0.65
        blurView.layer.cornerRadius = 8
        blurView.clipsToBounds = true
        addSubview(blurView)

        Row.allCases.forEach { row in
            let rowView = RowView(frame: .zero)
            rowView.iconView.image = Self.icon(for: row)
            rowView.isHidden = true
            rowView.isAccessibilityElement = true
            rowView.accessibilityLabel = Self.accessibilityTitle(for: row)
            addSubview(rowView)
            rowViews[row] = rowView
        }

        addLongPressGesture { [weak self] _ in
            self?.onLongPressDisable?()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        relayoutContent()
    }

    private func rowView(for row: Row) -> RowView {
        guard let rowView = rowViews[row] else {
            fatalError("Missing row view for row: \(row)")
        }
        return rowView
    }

    private func updateRow(_ row: Row, text: String, textColor: UIColor) {
        let rowView = rowView(for: row)
        rowView.valueLabel.text = text
        rowView.applyValueAppearance(textColor: textColor)
        rowView.accessibilityValue = text
        relayoutContent()
    }

    private func relayoutContent() {
        let padding: CGFloat = 8
        let lineSpacing: CGFloat = 4
        let iconSize: CGFloat = 14
        let iconSpacing: CGFloat = 6
        var y = padding
        var maxWidth: CGFloat = 0

        for row in Row.allCases {
            guard let rowView = rowViews[row], rowView.isHidden == false else { continue }

            rowView.layoutContent(iconSize: iconSize, spacing: iconSpacing)
            rowView.frame.origin = CGPoint(x: padding, y: y)
            maxWidth = max(maxWidth, rowView.frame.width)
            y += rowView.frame.height + lineSpacing
        }

        let contentHeight = max(y + padding - lineSpacing, padding * 2)
        frame.size = CGSize(width: max(maxWidth + padding * 2, 96), height: contentHeight)
    }

    private static func icon(for row: Row) -> UIImage? {
        let symbolName: String
        switch row {
        case .memory:
            symbolName = "memorychip"
        case .cpu:
            symbolName = "cpu"
        case .fps:
            symbolName = "gauge.with.needle"
        case .thermal:
            symbolName = "thermometer.medium"
        }

        return UIImage(systemName: symbolName, withConfiguration: iconConfiguration)
    }

    private static func accessibilityTitle(for row: Row) -> String {
        switch row {
        case .memory:
            return "Memory"
        case .cpu:
            return "CPU"
        case .fps:
            return "FPS"
        case .thermal:
            return "Thermal"
        }
    }
}
