//
//  SystemInfoUIKitHelpers.swift
//

import UIKit

@MainActor
func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first(where: \.isKeyWindow)
}

extension UIAlertController {
    static func alert(
        title: String?,
        message: String?,
        cancelButtonTitle: String? = nil,
        otherButtonTitles: String? = nil,
        closure: ((UIAlertController, Int) -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        if let cancelButtonTitle {
            alert.addAction(UIAlertAction(title: cancelButtonTitle, style: .cancel) { _ in
                closure?(alert, 0)
            })
        }

        if let otherButtonTitles {
            alert.addAction(UIAlertAction(title: otherButtonTitles, style: .default) { _ in
                closure?(alert, 1)
            })
        }

        keyWindow()?.rootViewController?.present(alert, animated: true)
    }
}

private class ClosureSleeve {
    let closure: (_ recognizer: UIGestureRecognizer) -> Void

    init (_ closure: @escaping (_ recognizer: UIGestureRecognizer) -> Void) {
        self.closure = closure
    }

    @objc func invoke (recognizer: UIGestureRecognizer) {
        switch recognizer {
        case let recognizer as UITapGestureRecognizer:
            if recognizer.state == .ended {
                closure(recognizer)
            }
        case let recognizer as UILongPressGestureRecognizer:
            if recognizer.state == .began {
                closure(recognizer)
            }
        default:
            closure(recognizer)
        }
    }
}

private var LongPressGesture_Key: UInt8 = 0
extension UIView {
    var cornerRadius: CGFloat {
        get { layer.cornerRadius }
        set {
            layer.cornerRadius = newValue
            clipsToBounds = newValue > 0
        }
    }

    @discardableResult
    public func addLongPressGesture(_ closure: @escaping (_ recognizer: UIGestureRecognizer) -> Void) -> UILongPressGestureRecognizer {
        let sleeve = ClosureSleeve(closure)
        let longPress: UILongPressGestureRecognizer = UILongPressGestureRecognizer(target: sleeve, action: #selector(ClosureSleeve.invoke))
        addGestureRecognizer(longPress)
        isUserInteractionEnabled = true
        objc_setAssociatedObject(self, &LongPressGesture_Key, sleeve, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return longPress
    }
}

extension  Timer {
    ///   Runs every x seconds, to cancel use: timer.invalidate()
    @discardableResult
    static func schedule(repeatInterval: TimeInterval, delayStart: Bool = true, _ handler: @escaping (Timer?) -> Void) -> Timer {
        var fireDate: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        if delayStart {
            fireDate += repeatInterval
        }
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, fireDate, repeatInterval, 0, 0, handler)
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, CFRunLoopMode.commonModes)
        return timer!
    }
}
