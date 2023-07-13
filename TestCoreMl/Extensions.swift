import UIKit
import CoreVideo
import VideoToolbox

extension UIImage {
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        guard let cgImage = cgImage else {
            return nil
        }

        self.init(cgImage: cgImage)
    }

    func imageWith(newSize: CGSize) -> UIImage {
        let image = UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }

        return image.withRenderingMode(renderingMode)
    }

    func resize(size: CGSize? = nil, insets: UIEdgeInsets = .zero, fill: UIColor = .white) -> UIImage? {
        var size: CGSize = size ?? self.size
        let widthRatio  = size.width / self.size.width
        let heightRatio = size.height / self.size.height

        if widthRatio > heightRatio {
            size = CGSize(width: floor(self.size.width * heightRatio), height: floor(self.size.height * heightRatio))
        } else if heightRatio > widthRatio {
            size = CGSize(width: floor(self.size.width * widthRatio), height: floor(self.size.height * widthRatio))
        }

        let rect = CGRect(x: 0,
                          y: 0,
                          width: size.width + insets.left + insets.right,
                          height: size.height + insets.top + insets.bottom)

        UIGraphicsBeginImageContextWithOptions(rect.size, false, scale)

        fill.setFill()
        UIGraphicsGetCurrentContext()?.fill(rect)

        draw(in: CGRect(x: insets.left,
                        y: insets.top,
                        width: size.width,
                        height: size.height))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()

        UIGraphicsEndImageContext()

        return newImage
    }
}


extension UIImage {
    func image(alpha: CGFloat) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(at: .zero, blendMode: .normal, alpha: alpha)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }

    func scalePreservingAspectRatio(targetSize: CGSize) -> UIImage {
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height

        let scaleFactor = min(widthRatio, heightRatio)

        let scaledImageSize = CGSize(
            width: size.width * scaleFactor,
            height: size.height * scaleFactor
        )

        let renderer = UIGraphicsImageRenderer(
            size: scaledImageSize
        )

        let scaledImage = renderer.image { _ in
            self.draw(in: CGRect(
                origin: .zero,
                size: scaledImageSize
            ))
        }

        return scaledImage
    }
}

extension CGImage {
    func resize(size:CGSize) -> CGImage? {
        let width: Int = Int(size.width)
        let height: Int = Int(size.height)

        let bytesPerPixel = self.bitsPerPixel / self.bitsPerComponent
        let destBytesPerRow = width * bytesPerPixel


        guard let colorSpace = self.colorSpace else { return nil }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: self.bitsPerComponent, bytesPerRow: destBytesPerRow, space: colorSpace, bitmapInfo: self.alphaInfo.rawValue) else { return nil }

        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }
}

extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
