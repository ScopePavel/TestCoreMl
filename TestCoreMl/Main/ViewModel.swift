import CoreML
import AVFoundation
import Vision
import UIKit
import VideoToolbox
import CoreImage

protocol MainViewModelProtocol {
    func start()
    var onUpdate: ((String) -> Void)? { get set }
    var onShow: ((URL) -> Void)? { get set }
}

final class MainViewModel {
    var onUpdate: ((String) -> Void)?
    var onShow: ((URL) -> Void)?

    private var imagesCreator: ImagesCreatorProtocol = ImagesCreator()
    private let audioEngine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
}

extension MainViewModel: MainViewModelProtocol {
    func start() {
        imagesCreator.start()

        imagesCreator.onUpdate = { status in
            self.onUpdate?(status)
        }

        imagesCreator.onSucces = { [weak self] uiImages in
            self?.createVideo(uiImages: uiImages)
        }
    }
}

private extension MainViewModel {
    func createVideo(uiImages: [UIImage]) {
        let settings = VideoWriter.videoSettings(
            codec: AVVideoCodecType.h264.rawValue,
            width: (uiImages[0].cgImage?.width)!,
            height: (uiImages[0].cgImage?.height)!)
        let movieMaker = VideoWriter(videoSettings: settings)
        movieMaker.createMovieFrom(images: uiImages) { [weak self] fileURL in
//            let video = AVAsset(url: fileURL)
            self?.onShow?(fileURL)
//            let playerItem = AVPlayerItem(asset: video)
//            let avPlayer = AVPlayer(playerItem: playerItem)
//            let playerLayer = AVPlayerLayer(player: avPlayer)
//            playerLayer.frame = CGRect(
//                x: 0,
//                y: 0,
//                width: UIScreen.main.bounds.width,
//                height: UIScreen.main.bounds.width * 3.0 / 4.0
//            )
//            //            self.view.layer.addSublayer(playerLayer)
//            //            avPlayer.play()
        }
    }

}
