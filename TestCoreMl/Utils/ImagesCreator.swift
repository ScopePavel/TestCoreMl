import UIKit
import CoreML
import Vision

struct ImageModel {
    let originalImage: UIImage
    let mask: UIImage
}

protocol ImagesCreatorProtocol {
    var onUpdate: ((String) -> Void)? { get set }
    var onSucces: (([UIImage]) -> Void)? { get set }
    func start()
}

class ImagesCreator: ImagesCreatorProtocol {
    var onUpdate: ((String) -> Void)?
    var onSucces: (([UIImage]) -> Void)?

    private let imageStorage = ImageStorage()
    private var imageModels: [ImageModel] = []
    private let group = DispatchGroup()
    private var currentLoading: Int = 0
    private let total: Int

    init() {
        self.total = imageStorage.images.count
    }

    func start() {
        for img in imageStorage.images {
            excecuteRequest(image: img)
        }

        group.notify(queue: .main) {
            self.onSucces?(self.createImageArrayForVideo())
        }
    }

}
private extension ImagesCreator {
    func updateLoadingModel() {
        currentLoading += 1
        let result = currentLoading == total ? "готово" : "\(currentLoading) / \(total)"
        onUpdate?(result)
    }

    func createNewImage(image: UIImage, mask: UIImage, background: UIImage?) -> UIImage? {
        guard
            let background = background,
            let originalImage = image.cgImage,
            let mask = mask.cgImage,
            let newImage = createMask(
                of: CIImage(cgImage: originalImage),
                fromMask: CIImage(cgImage: mask),
                withBackground: background
            )
        else { return nil }
        return newImage
    }

    func createImageArrayForVideo() -> [UIImage] {
        var images: [UIImage] = []
        for (index, model) in imageModels.enumerated() {
            if index == 0 {
                images.append(model.originalImage)
            }
            if index != 0 {
                if let newImage = createNewImage(
                    image: model.originalImage,
                    mask: model.mask,
                    background: imageModels[safe: index - 1]?.originalImage
                ) {
                    images.append(newImage)
                    images.append(model.originalImage)
                } else {
                    images.append(model.originalImage)
                }
            }
        }
        return images
    }

    func mlrequest(image: UIImage) -> VNCoreMLRequest? {
        var myrequest: VNCoreMLRequest?
        let modelobj = try! segmentation_8bit()
        do {
            let fruitmodel = try VNCoreMLModel(
                for: modelobj.model)
            myrequest = VNCoreMLRequest(model: fruitmodel, completionHandler: {
                (request, error) in self.handleResult(
                    request: request,
                    error: error,
                    image: image
                ) { [weak self] imageModel in
                    self?.group.leave()
                    self?.updateLoadingModel()
                    self?.imageModels.append(imageModel)
                }
            })
        } catch {
            print("Unable to create a request")
        }
        myrequest?.imageCropAndScaleOption = .scaleFill
        return myrequest
    }

    func excecuteRequest(image: UIImage) {
        guard
            let mlrequest = self.mlrequest(image: image),
            let ciImage = CIImage(image: image)
        else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            self.group.enter()
            let handler = VNImageRequestHandler(ciImage: ciImage)
            do {
                try handler.perform([mlrequest])
            } catch {
                print("Failed to get the description")
            }
        }
    }

    func handleResult(
        request: VNRequest,
        error: Error?,
        image: UIImage,
        complition: (ImageModel) -> Void
    ) {
        if let res = request.results as? [VNPixelBufferObservation] {
            let pixel = res.first
            if let pixelBuffer = pixel?.pixelBuffer {
                let originalImage = image
                let maskImage = CIImage(cvPixelBuffer: pixelBuffer)
                let image2 = UIImage(ciImage: maskImage).imageWith(newSize: originalImage.size)
                guard
                    let cgImage1 = originalImage.cgImage,
                    let mask = image2.cgImage
                else { return }
                let size = CGSize(width: cgImage1.width, height: cgImage1.height)
                let newMask = mask.resize(size: size)
                if let newMask = newMask {
                    complition(ImageModel(
                        originalImage: originalImage,
                        mask: UIImage(cgImage: newMask))
                    )
                }
            }
        }
    }

    func createMask(
        of image: CIImage,
        fromMask mask: CIImage,
        withBackground background: UIImage? = nil
    ) -> UIImage? {
        guard let filter = CIFilter(name: "CIBlendWithRedMask") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        if let background = background?.cgImage {
            filter.setValue(CIImage(cgImage: background), forKey: kCIInputBackgroundImageKey)
        }
        filter.setValue(mask, forKey: kCIInputMaskImageKey)

        let context = CIContext()

        guard
            let filterOutputImage = filter.outputImage,
            let maskedImage = context.createCGImage(filterOutputImage, from: mask.extent)
        else {
            return nil
        }

        return UIImage(cgImage: maskedImage)
    }
}
