import XCTest
import CoreGraphics
@testable import SnorOhSwift

/// Regression test for the `createStripFromFrames` vertical-flip bug.
///
/// Before the fix, the strip context had a `scaleBy(1, -1)` transform meant
/// to give top-left drawing coords. But `CGContext.draw(CGImage, in:)`
/// respects the CTM — under that y-flip, the image itself was mirrored
/// vertically. Every Smart-Imported sprite (and, post-v2, every imported
/// `.snoroh`) came out upside-down. Fix: drop the outer flip, compute the
/// draw rect directly in bottom-up CG coords.
final class SmartImportOrientationTests: XCTestCase {

    /// 80×80 RGBA with an 8-px transparent border and a 64×64 content region:
    /// red top half, blue bottom half. Transparent corners keep the bg
    /// detector from treating red as background.
    private func redTopBlueBottomImage() -> CGImage {
        let w = 80, h = 80, pad = 8
        let ctx = SmartImport.createRGBAContext(width: w, height: h)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: pad, y: pad, width: w - 2*pad, height: (h - 2*pad) / 2))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: pad, y: pad + (h - 2*pad) / 2, width: w - 2*pad, height: (h - 2*pad) / 2))
        return ctx.makeImage()!
    }

    /// Read a pixel from a CGImage via a scratch unflipped context.
    /// Memory row 0 = visually top.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let w = image.width, h = image.height
        let ctx = SmartImport.createRGBAContext(width: w, height: h)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let off = y * ctx.bytesPerRow + x * 4
        return (px[off], px[off + 1], px[off + 2], px[off + 3])
    }

    func testStripPreservesImageOrientation() throws {
        let img = redTopBlueBottomImage()
        let processed = SmartImport.processSheet(image: img)!
        XCTAssertEqual(processed.frames.count, 1, "synth image is one content region → one frame")

        let strip = SmartImport.createStripFromFrames(
            context: processed.context,
            frames: processed.frames,
            indices: [0]
        )!
        let stripImg = SmartImport.loadImage(from: strip.pngData)!

        // Strip is a 4096×128 grid with frame 0 packed into the first 128×128
        // cell. Probe the vertical midline at x=64 — find first red from top,
        // first blue from bottom.
        let probeX = 64
        var firstRedY: Int?
        var firstBlueY: Int?
        for y in 0..<stripImg.height {
            let p = pixel(stripImg, x: probeX, y: y)
            if p.a > 128 {
                if p.r > 200 && firstRedY == nil { firstRedY = y }
                if p.b > 200 { firstBlueY = y }
            }
        }

        let r = try XCTUnwrap(firstRedY, "strip missing RED pixels")
        let b = try XCTUnwrap(firstBlueY, "strip missing BLUE pixels")
        XCTAssertLessThan(r, b,
                          "RED (source top) must appear above BLUE (source bottom) in the strip. If reversed, createStripFromFrames is flipping vertically again.")
    }

    /// Full v2 round-trip: encode → base64 → decode → re-run pipeline, check
    /// the regenerated strip has the same top/bottom ordering as the input.
    /// This is what `.snoroh` v2 import executes end-to-end.
    func testV2RoundTripKeepsOrientation() throws {
        let img = redTopBlueBottomImage()

        // Export side: the sheet is stored on disk as pngData(from: sourceImage).
        let sheetPng = SmartImport.pngData(from: img)!

        // Import side: base64 (we skip actual base64 round-trip — Data(base64Encoded:)
        // is a no-op orientation-wise — and directly decode the bytes).
        let reloaded = SmartImport.loadImage(from: sheetPng)!
        let processed = SmartImport.processSheet(image: reloaded)!
        let strip = SmartImport.createStripFromFrames(
            context: processed.context,
            frames: processed.frames,
            indices: [0]
        )!
        let stripImg = SmartImport.loadImage(from: strip.pngData)!

        // Top of the first 128×128 cell should hold the RED source pixels.
        var sawRed = false
        for y in 0..<(stripImg.height / 2) {
            let p = pixel(stripImg, x: 64, y: y)
            if p.a > 128, p.r > 200 { sawRed = true; break }
        }
        XCTAssertTrue(sawRed, "top half of v2-regenerated strip should contain RED (source top)")
    }
}
