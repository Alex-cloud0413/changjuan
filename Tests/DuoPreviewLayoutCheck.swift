import SwiftUI
import UIKit

@main
@MainActor
struct DuoPreviewLayoutCheck {
    final class InsetScrollView: ZoomableLongImage.ResizingScrollView {
        var injectedInsets = UIEdgeInsets.zero
        override var adjustedContentInset: UIEdgeInsets {
            let value = super.adjustedContentInset
            return UIEdgeInsets(top: value.top + injectedInsets.top, left: value.left + injectedInsets.left,
                bottom: value.bottom + injectedInsets.bottom, right: value.right + injectedInsets.right)
        }
    }
    static func main() {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 4000), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 390, height: 4000))
        }
        let scroll = InsetScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4
        let coordinator = ZoomableLongImage(image: image).makeCoordinator()
        scroll.delegate = coordinator; scroll.addSubview(coordinator.imageView)
        let id = URL(fileURLWithPath: "/synthetic-immutable-preview.jpg")
        scroll.onResize = { coordinator.layoutImage(in: scroll, image: image, imageID: id) }
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        scroll.setZoomScale(2, animated: false)
        scroll.contentOffset = CGPoint(x: 150, y: 2300)
        func anchor() -> CGPoint {
            let own = scroll.contentInset, adjusted = scroll.adjustedContentInset
            let left = adjusted.left - own.left, top = adjusted.top - own.top
            let width = scroll.bounds.width - left - (adjusted.right - own.right)
            let height = scroll.bounds.height - top - (adjusted.bottom - own.bottom)
            let p = coordinator.imageView.convert(CGPoint(x: scroll.contentOffset.x + left + width / 2,
                y: scroll.contentOffset.y + top + height / 2), from: scroll)
            return CGPoint(x: p.x / coordinator.imageView.bounds.width, y: p.y / coordinator.imageView.bounds.height)
        }
        func requireAnchor(_ expected: CGPoint, _ reason: String) {
            let actual = anchor()
            precondition(abs(actual.x - expected.x) < 0.002 && abs(actual.y - expected.y) < 0.002,
                "\(reason): \(expected) -> \(actual)")
            precondition(abs(scroll.zoomScale - 2) < 0.001)
        }
        let original = anchor()
        scroll.frame.size = CGSize(width: 700, height: 390)
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        requireAnchor(original, "Opening/rotating must preserve zoom and reading center")
        scroll.frame.size = CGSize(width: 390, height: 700)
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        requireAnchor(original, "Closing round trip")
        scroll.injectedInsets = UIEdgeInsets(top: 0, left: 70, bottom: 20, right: 0)
        scroll.safeAreaInsetsDidChange()
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        requireAnchor(original, "Same-size leading safe-area change")
        precondition(abs(coordinator.imageView.bounds.width - 320) < 0.01, "Fit uses the 320pt usable width")
        scroll.injectedInsets = UIEdgeInsets(top: 40, left: 0, bottom: 0, right: 80)
        scroll.safeAreaInsetsDidChange()
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        requireAnchor(original, "Safe area changes edge at constant bounds")
        let offset = scroll.contentOffset
        let redecoded = UIImage(cgImage: image.cgImage!)
        coordinator.layoutImage(in: scroll, image: redecoded, imageID: id)
        precondition(scroll.contentOffset == offset && scroll.zoomScale == 2, "Same URL survives a SwiftUI image refresh")
        print("Duo preview native checks passed: opening/closing, zoom, reading anchor, asymmetric system insets at unchanged bounds, same URL re-decoding")
    }
}
