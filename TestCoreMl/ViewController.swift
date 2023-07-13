import CoreML
import AVFoundation
import Vision
import UIKit
import VideoToolbox
import CoreImage

class ViewController: UIViewController {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var button: UIButton!
    @IBOutlet weak var imageView2: UIImageView!
    let imageStorage = ImageStorage()
    var imageModels: [ImageModel] = []
    let group = DispatchGroup()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .green
        button.addTarget(self, action: #selector(createVideo), for: .touchUpInside)
        for img in imageStorage.images3 {
            excecuteRequest(image: img)
        }

        group.notify(queue: .main) {
            self.createVideo()
        }
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
                    self?.imageModels.append(imageModel)
                }
            })
        } catch {
            print("Unable to create a request")
        }
        myrequest?.imageCropAndScaleOption = .scaleFill
        return myrequest
    }

    func createImageArrayForVideo() -> [UIImage] {
        var images: [UIImage] = []
        for (index, model) in imageModels.enumerated() {
            if index == 0 {
                images.append(model.originalImage)
            }
            if index != 0 {
                if let newImage = createNewImage(image: model.originalImage,
                                                 mask: model.mask,
                                                 background: imageModels[safe: index - 1]?.originalImage)
                {
                    images.append(newImage)
                    images.append(model.originalImage)
                } else {
                    images.append(model.originalImage)
                }
            }
        }
        return images
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
    let audioEngine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    func playSaveSound() {
        let url = Bundle.main.url(forResource: "music", withExtension: "aac")!
        do {
            let audioFile = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: .init(audioFile.length)) else { return }
            try audioFile.read(into: buffer)
            audioEngine.attach(player)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: buffer.format)
            try audioEngine.start()
            player.play()
            player.scheduleBuffer(buffer, at: nil, options: .loops)

        } catch {
            print(error)
        }
    }

    @objc func createVideo() {
        let uiImages = createImageArrayForVideo()
        let settings = CXEImagesToVideo.videoSettings(
            codec: AVVideoCodecType.h264.rawValue,
            width: (uiImages[0].cgImage?.width)!,
            height: (uiImages[0].cgImage?.height)!)
        let movieMaker = CXEImagesToVideo(videoSettings: settings)
        movieMaker.createMovieFrom(images: uiImages){ (fileURL:URL) in
            let video = AVAsset(url: fileURL)
            print("fileURL", fileURL)
            let playerItem = AVPlayerItem(asset: video)
            let avPlayer = AVPlayer(playerItem: playerItem)
            let playerLayer = AVPlayerLayer(player: avPlayer)
            playerLayer.frame = CGRect(
                x: 0,
                y: 0,
                width: UIScreen.main.bounds.width,
                height: UIScreen.main.bounds.width * 3.0 / 4.0
            )
            self.view.layer.addSublayer(playerLayer)
            avPlayer.play()
        }
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
                    DispatchQueue.main.async {
                        self.imageView2.image = originalImage
                        self.imageView.image = self.createMask(
                            of: CIImage(cgImage: cgImage1),
                            fromMask: CIImage(cgImage: newMask)
                        )
                    }
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


extension CIImage {

    private func getBrightness(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGFloat {
         let color = UIColor(red: red, green: green, blue: blue, alpha: 1)
         var brightness: CGFloat = 0
         color.getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
         return brightness
     }

    private func chromaKeyFilter() -> CIFilter? {
         let size = 64
         var cubeRGB = [Float]()

         for z in 0 ..< size {
             let blue = CGFloat(z) / CGFloat(size - 1)
             for y in 0 ..< size {
                 let green = CGFloat(y) / CGFloat(size - 1)
                 for x in 0 ..< size {
                     let red = CGFloat(x) / CGFloat(size - 1)
                     let brightness = getBrightness(red: red, green: green, blue: blue)
                     let alpha: CGFloat = brightness == 1 ? 0 : 1
                     cubeRGB.append(Float(red * alpha))
                     cubeRGB.append(Float(green * alpha))
                     cubeRGB.append(Float(blue * alpha))
                     cubeRGB.append(Float(alpha))
                 }
             }
         }

         let data = Data(buffer: UnsafeBufferPointer(start: &cubeRGB, count: cubeRGB.count))

         let colorCubeFilter = CIFilter(
             name: "CIColorCube",
             parameters: [
                 "inputCubeDimension": size,
                 "inputCubeData": data
             ]
         )
         return colorCubeFilter
     }

    func removeWhitePixels() -> CIImage? {
        let chromaCIFilter = chromaKeyFilter()
        chromaCIFilter?.setValue(self, forKey: kCIInputImageKey)
        return chromaCIFilter?.outputImage
    }
}
