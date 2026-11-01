import SwiftUI
#if canImport(CoreImage)
import CoreImage
#endif

/// Extracts a vivid accent colour from album art; drives the pulsing backgrounds.
enum ArtColor {
    static func accent(_ url: URL?) async -> Color? {
        #if canImport(CoreImage)
        guard let url, let (d, _) = try? await URLSession.shared.data(from: url), let ci = CIImage(data: d),
              let f = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        let r = Double(px[0]) / 255.0
        let g = Double(px[1]) / 255.0
        let b = Double(px[2]) / 255.0
        
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal
        
        var h: Double = 0
        if delta > 0.0001 {
            if maxVal == r {
                h = (g - b) / delta
                if h < 0 { h += 6.0 }
            } else if maxVal == g {
                h = 2.0 + (b - r) / delta
            } else {
                h = 4.0 + (r - g) / delta
            }
            h /= 6.0
        }
        let s = maxVal > 0 ? (delta / maxVal) : 0
        let br = maxVal
        return Color(hue: h, saturation: max(s, 0.5), brightness: max(br, 0.7))
        #else
        return nil
        #endif
    }
}
