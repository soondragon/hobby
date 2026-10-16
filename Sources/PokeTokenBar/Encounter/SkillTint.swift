import AppKit

/// Recolors decoded effect pixels once, keeping alpha and luminance detail intact.
enum SkillTint {
    static let colors: [String: (Double,Double,Double)] = [
        "fire": (1,0.30,0.04),"water": (0.08,0.48,1),"ice": (0.4,0.9,1),
        "electric": (1,0.82,0.05),"grass": (0.2,0.75,0.15),"bug": (0.5,0.7,0.1),
        "poison": (0.7,0.2,0.85),"ghost": (0.45,0.25,0.7),"psychic": (1,0.3,0.6),
        "dragon": (0.45,0.25,1),"dark": (0.32,0.25,0.38),"rock": (0.65,0.5,0.2),
        "ground": (0.8,0.6,0.3),"steel": (0.65,0.7,0.75),"fighting": (0.8,0.25,0.15),
        "flying": (0.65,0.75,0.95),"normal": (0.7,0.65,0.55)
    ]
    static func image(_ image: CGImage, type: String) -> CGImage? {
        guard let rgb = colors[type] else { return image }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0,count: width*height*4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress,width: width,height: height,bitsPerComponent: 8,
                bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image,in: CGRect(x: 0,y: 0,width: width,height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            for offset in stride(from: 0,to: bytes.count,by: 4) {
                let alpha = Double(bytes[offset+3])/255
                guard alpha > 0 else { continue }
                let peak = max(Double(bytes[offset]),Double(bytes[offset+1]),Double(bytes[offset+2]))/(255*alpha)
                let highlight = max(0,(peak-0.88)*3)
                for (channel,color) in [rgb.0,rgb.1,rgb.2].enumerated() {
                    let value = min(1,color*(0.45+0.55*peak)+highlight*(1-color))
                    bytes[offset+channel] = UInt8(min(255,max(0,value*alpha*255)))
                }
            }
            return context.makeImage()
        }
    }
}
