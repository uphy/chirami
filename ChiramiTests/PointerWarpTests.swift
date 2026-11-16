import CoreGraphics
import Testing
@testable import Chirami

@Suite("PointerWarp")
struct PointerWarpTests {
    // Primary 1920x1080 at the origin, secondary 2560x1440 to its right.
    let displays = [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: 1920, y: 0, width: 2560, height: 1440),
    ]

    @Test("warps to the window centre when the pointer is on another display")
    func warpsAcrossDisplays() {
        let window = CGRect(x: 2000, y: 100, width: 300, height: 400)
        let target = PointerWarp.warpTarget(pointer: CGPoint(x: 500, y: 500), windowFrame: window, displayFrames: displays)
        #expect(target == CGPoint(x: 2150, y: 300))
    }

    @Test("does not warp when the pointer is on the window's display")
    func noWarpOnSameDisplay() {
        let window = CGRect(x: 100, y: 100, width: 300, height: 400)
        let target = PointerWarp.warpTarget(pointer: CGPoint(x: 1800, y: 1000), windowFrame: window, displayFrames: displays)
        #expect(target == nil)
    }

    @Test("uses the display with the largest overlap for a window spanning two displays")
    func spanningWindowUsesLargestOverlap() {
        // 50pt on the primary, 250pt on the secondary.
        let window = CGRect(x: 1870, y: 100, width: 300, height: 400)
        #expect(PointerWarp.displayIndex(for: window, in: displays) == 1)
        let target = PointerWarp.warpTarget(pointer: CGPoint(x: 1900, y: 300), windowFrame: window, displayFrames: displays)
        #expect(target == CGPoint(x: 2020, y: 300))
    }

    @Test("does not warp when the window is on no display")
    func noWarpForOffscreenWindow() {
        let window = CGRect(x: -5000, y: -5000, width: 300, height: 400)
        #expect(PointerWarp.warpTarget(pointer: CGPoint(x: 10, y: 10), windowFrame: window, displayFrames: displays) == nil)
    }

    @Test("restores only while the pointer stays where it was warped to")
    func restoreDependsOnUserMovement() {
        let warpedTo = CGPoint(x: 2150, y: 300)
        let origin = CGPoint(x: 500, y: 500)
        #expect(PointerWarp.shouldRestore(current: warpedTo, warpedTo: warpedTo, origin: origin, displayFrames: displays))
        #expect(PointerWarp.shouldRestore(current: CGPoint(x: 2151, y: 299), warpedTo: warpedTo, origin: origin, displayFrames: displays))
        #expect(!PointerWarp.shouldRestore(current: CGPoint(x: 2200, y: 300), warpedTo: warpedTo, origin: origin, displayFrames: displays))
    }

    @Test("does not restore to a display that has gone away")
    func noRestoreToMissingDisplay() {
        let warpedTo = CGPoint(x: 500, y: 500)
        let origin = CGPoint(x: 3000, y: 300)
        #expect(!PointerWarp.shouldRestore(current: warpedTo, warpedTo: warpedTo, origin: origin, displayFrames: [displays[0]]))
    }

    @Test("converts Cocoa points to Quartz points by flipping against the primary display")
    func quartzConversion() {
        #expect(PointerWarp.quartzPoint(fromCocoa: CGPoint(x: 100, y: 1000), primaryDisplayHeight: 1080) == CGPoint(x: 100, y: 80))
    }
}
