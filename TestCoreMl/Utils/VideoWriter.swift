import Foundation
import AVFoundation
import UIKit

typealias MovieMakerCompletion = (URL) -> Void
typealias MovieMakerUIImageExtractor = (AnyObject) -> UIImage?

class VideoWriter: NSObject {
    private var assetWriter: AVAssetWriter?
    private var writeInput: AVAssetWriterInput?
    private var bufferAdapter: AVAssetWriterInputPixelBufferAdaptor?
    private var videoSettings: [String: Any]?
    private var frameTime: CMTime?
    private var fileURL: URL?

    private var completionBlock: MovieMakerCompletion?
    private var movieMakerUIImageExtractor: MovieMakerUIImageExtractor?

    static func videoSettings(codec: String, width: Int, height: Int) -> [String: Any] {
        if Int(width) % 16 != 0 {
            print("warning: video settings width must be divisible by 16")
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        return videoSettings
    }

    init(videoSettings: [String: Any]) {
        super.init()
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let tempPath = paths[0] + "/exprotvideo.mp4"

        if FileManager.default.fileExists(atPath: tempPath) {
            guard (try? FileManager.default.removeItem(atPath: tempPath)) != nil else {
                print("remove path failed")
                return
            }
        }

        let fileURL = URL(fileURLWithPath: tempPath)
        self.assetWriter = try? AVAssetWriter(url: fileURL, fileType: AVFileType.mov)

        self.videoSettings = videoSettings
        let writeInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)

        assert(self.assetWriter?.canAdd(writeInput) ?? false, "add failed")
        self.assetWriter?.add(writeInput)

        let bufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
        self.bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writeInput,
            sourcePixelBufferAttributes: bufferAttributes
        )
        self.frameTime = CMTimeMake(value: 4, timescale: 1)
        self.writeInput = writeInput
        self.fileURL = fileURL
    }

    func createMovieFrom(images: [UIImage], withCompletion: @escaping MovieMakerCompletion) {
        self.createMovieFromSource(
            images: images,
            extractor: {(inputObject: AnyObject) -> UIImage? in
                return inputObject as? UIImage}, withCompletion: withCompletion
        )
    }
}

private extension VideoWriter {

    private func mergeVideoAndAudio(
        videoUrl: URL,
        audioUrl: URL,
        shouldFlipHorizontally: Bool = false,
        completion: @escaping (_ error: Error?, _ url: URL?) -> Void
    ) {

        let mixComposition = AVMutableComposition()
        var mutableCompositionVideoTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioOfVideoTrack = [AVMutableCompositionTrack]()

        // start merge

        let aVideoAsset = AVAsset(url: videoUrl)
        let aAudioAsset = AVAsset(url: audioUrl)

        let compositionAddVideo = mixComposition.addMutableTrack(
            withMediaType: AVMediaType.video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        let compositionAddAudio = mixComposition.addMutableTrack(
            withMediaType: AVMediaType.audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        let compositionAddAudioOfVideo = mixComposition.addMutableTrack(
            withMediaType: AVMediaType.audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        let aVideoAssetTrack: AVAssetTrack = aVideoAsset.tracks(withMediaType: AVMediaType.video)[0]
        let aAudioOfVideoAssetTrack: AVAssetTrack? = aVideoAsset.tracks(withMediaType: AVMediaType.audio).first
        let aAudioAssetTrack: AVAssetTrack = aAudioAsset.tracks(withMediaType: AVMediaType.audio)[0]

        // Default must have tranformation
        compositionAddVideo?.preferredTransform = aVideoAssetTrack.preferredTransform

        if shouldFlipHorizontally {
            // Flip video horizontally
            var frontalTransform: CGAffineTransform = CGAffineTransform(scaleX: -1.0, y: 1.0)
            frontalTransform = frontalTransform.translatedBy(x: -aVideoAssetTrack.naturalSize.width, y: 0.0)
            frontalTransform = frontalTransform.translatedBy(x: 0.0, y: -aVideoAssetTrack.naturalSize.width)
            compositionAddVideo!.preferredTransform = frontalTransform
        }

        mutableCompositionVideoTrack.append(compositionAddVideo!)
        mutableCompositionAudioTrack.append(compositionAddAudio!)
        mutableCompositionAudioOfVideoTrack.append(compositionAddAudioOfVideo!)

        do {
            try mutableCompositionVideoTrack[0].insertTimeRange(
                CMTimeRangeMake(
                    start: CMTime.zero,
                    duration: aVideoAssetTrack.timeRange.duration
                ),
                of: aVideoAssetTrack,
                at: CMTime.zero
            )

            //In my case my audio file is longer then video file so i took videoAsset duration
            //instead of audioAsset duration
            try mutableCompositionAudioTrack[0].insertTimeRange(
                CMTimeRangeMake(
                    start: CMTime.zero,
                    duration: aVideoAssetTrack.timeRange.duration
                ),
                of: aAudioAssetTrack,
                at: CMTime.zero
            )

            // adding audio (of the video if exists) asset to the final composition
            if let aAudioOfVideoAssetTrack = aAudioOfVideoAssetTrack {
                try mutableCompositionAudioOfVideoTrack[0].insertTimeRange(
                    CMTimeRangeMake(
                        start: CMTime.zero,
                        duration: aVideoAssetTrack.timeRange.duration
                    ),
                    of: aAudioOfVideoAssetTrack,
                    at: CMTime.zero
                )
            }
        } catch {
            print(error.localizedDescription)
        }

        // Exporting
        let savePathUrl = URL(fileURLWithPath: NSHomeDirectory() + "/Documents/newVideo.mp4")
        do { // delete old video
            try FileManager.default.removeItem(at: savePathUrl)
        } catch {
            print(error.localizedDescription)
        }

        let assetExport: AVAssetExportSession = AVAssetExportSession(
            asset: mixComposition,
            presetName: AVAssetExportPresetHighestQuality
        )!

        assetExport.outputFileType = AVFileType.mp4
        assetExport.outputURL = savePathUrl
        assetExport.shouldOptimizeForNetworkUse = true

        assetExport.exportAsynchronously { () -> Void in
            switch assetExport.status {
            case AVAssetExportSession.Status.completed:
                print("success")
                completion(nil, savePathUrl)
            case AVAssetExportSession.Status.failed:
                print("failed \(assetExport.error?.localizedDescription ?? "error nil")")
                completion(assetExport.error, nil)
            case AVAssetExportSession.Status.cancelled:
                print("cancelled \(assetExport.error?.localizedDescription ?? "error nil")")
                completion(assetExport.error, nil)
            default:
                print("complete")
                completion(assetExport.error, nil)
            }
        }

    }

    func newPixelBufferFrom(cgImage: CGImage) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pxbuffer: CVPixelBuffer?
        guard
            let frameWidth = self.videoSettings?[AVVideoWidthKey] as? Int,
            let frameHeight = self.videoSettings![AVVideoHeightKey] as? Int
        else { return nil }

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, frameWidth,
            frameHeight, kCVPixelFormatType_32ARGB,
            options as CFDictionary?,
            &pxbuffer
        )
        assert(status == kCVReturnSuccess && pxbuffer != nil, "newPixelBuffer failed")

        CVPixelBufferLockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pxdata = CVPixelBufferGetBaseAddress(pxbuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: pxdata,
            width: frameWidth,
            height: frameHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pxbuffer!),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        assert(context != nil, "context is nil")

        context!.concatenate(CGAffineTransform.identity)
        context!.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        CVPixelBufferUnlockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
        return pxbuffer
    }

    func createMovieFrom(urls: [URL], withCompletion: @escaping MovieMakerCompletion) {
        self.createMovieFromSource(
            images: urls as [AnyObject],
            extractor: {(inputObject: AnyObject) -> UIImage? in
                return UIImage(data: try! Data(contentsOf: inputObject as! URL))},
            withCompletion: withCompletion
        )
    }

    func createMovieFromSource(
        images: [AnyObject],
        extractor: @escaping MovieMakerUIImageExtractor,
        withCompletion: @escaping MovieMakerCompletion
    ) {
        self.completionBlock = withCompletion

        self.assetWriter?.startWriting()
        self.assetWriter?.startSession(atSourceTime: CMTime.zero)

        let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
        var i = 0
        let frameNumber = images.count
        self.writeInput?.requestMediaDataWhenReady(on: mediaInputQueue) {
            while true {
                if i >= frameNumber {
                    break
                }

                if let isReadyForMoreMediaData = self.writeInput?.isReadyForMoreMediaData,
                   isReadyForMoreMediaData
                {
                    var sampleBuffer: CVPixelBuffer?
                    autoreleasepool{
                        let img = extractor(images[i])
                        if img == nil{
                            i += 1
                            print("Warning: counld not extract one of the frames")
                            // continue
                        }
                        sampleBuffer = self.newPixelBufferFrom(cgImage: img!.cgImage!)
                    }
                    if let sampleBuffer = sampleBuffer {
                        if i == 0 {
                            self.bufferAdapter?.append(sampleBuffer, withPresentationTime: CMTime.zero)
                        } else {
                            if let frameTime = self.frameTime {
                                let value = i - 1
                                let lastTime = CMTimeMake(value: Int64(value), timescale: frameTime.timescale)
                                let presentTime = CMTimeAdd(lastTime, frameTime)
                                self.bufferAdapter?.append(sampleBuffer, withPresentationTime: presentTime)
                            }
                        }
                        i = i + 1
                    }
                }
            }
            self.writeInput?.markAsFinished()
            self.assetWriter?.finishWriting {
                DispatchQueue.main.sync {
                    if let url = Bundle.main.url(forResource: "music", withExtension: "aac"),
                       let fileURL = self.fileURL
                    {
                        self.mergeVideoAndAudio(videoUrl: fileURL, audioUrl: url) { error, url in
                            if let url = url {
                                self.completionBlock!(url)
                            }
                        }
                    }
                }
            }

        }
    }
}
