import AppKit
import CoreGraphics

/// Decides when to move the mouse pointer onto a note window shown on a
/// different display, and when to put it back afterwards.
///
/// All points and rects are in Cocoa global coordinates (origin at the
/// bottom-left of the primary display, y grows upward), the same space as
/// `NSEvent.mouseLocation` and `NSScreen.frame`.
enum PointerWarp {
    /// How far (in points) the pointer may drift from where it was warped to
    /// and still count as "the user did not move it".
    static let movementTolerance: CGFloat = 2

    /// Index of the display frame containing `point`, or nil when the point is
    /// off every display.
    static func displayIndex(containing point: CGPoint, in displayFrames: [CGRect]) -> Int? {
        displayFrames.firstIndex { NSMouseInRect(point, $0, false) }
    }

    /// Index of the display frame that overlaps `windowFrame` the most, or nil
    /// when the window overlaps no display.
    static func displayIndex(for windowFrame: CGRect, in displayFrames: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in displayFrames.enumerated() {
            let overlap = frame.intersection(windowFrame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > 0, area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        return best?.index
    }

    /// The point to warp the pointer to (the window centre), or nil when the
    /// pointer already sits on the window's display or either display is unknown.
    static func warpTarget(pointer: CGPoint, windowFrame: CGRect, displayFrames: [CGRect]) -> CGPoint? {
        guard let windowDisplay = displayIndex(for: windowFrame, in: displayFrames) else { return nil }
        if let pointerDisplay = displayIndex(containing: pointer, in: displayFrames),
           pointerDisplay == windowDisplay {
            return nil
        }
        return CGPoint(x: windowFrame.midX, y: windowFrame.midY)
    }

    /// Whether the pointer should go back to `origin` on hide: only when the
    /// user has not moved it since the warp and `origin` is still on a display.
    static func shouldRestore(current: CGPoint, warpedTo: CGPoint, origin: CGPoint, displayFrames: [CGRect]) -> Bool {
        guard abs(current.x - warpedTo.x) <= movementTolerance,
              abs(current.y - warpedTo.y) <= movementTolerance else { return false }
        return displayIndex(containing: origin, in: displayFrames) != nil
    }

    /// Converts a Cocoa global point into the Quartz global space used by
    /// `CGWarpMouseCursorPosition` (origin at the top-left of the primary display).
    static func quartzPoint(fromCocoa point: CGPoint, primaryDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
    }

    // MARK: - Side effects

    /// Moves the pointer to `cocoaPoint`. Returns false when the warp failed.
    @MainActor
    @discardableResult
    static func warp(toCocoa cocoaPoint: CGPoint) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let target = quartzPoint(fromCocoa: cocoaPoint, primaryDisplayHeight: primary.frame.maxY)
        guard CGWarpMouseCursorPosition(target) == .success else { return false }
        // CGWarpMouseCursorPosition suppresses mouse movement events for a short
        // while; re-associating makes the pointer respond to the mouse at once.
        CGAssociateMouseAndMouseCursorPosition(1)
        return true
    }
}
