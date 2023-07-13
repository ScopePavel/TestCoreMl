import Foundation
import AVFoundation
import UIKit

typealias CXEMovieMakerCompletion = (URL) -> Void
typealias CXEMovieMakerUIImageExtractor = (AnyObject) -> UIImage?


public class CXEImagesToVideo: NSObject {
    var assetWriter: AVAssetWriter!
    var writeInput: AVAssetWriterInput!
    var bufferAdapter: AVAssetWriterInputPixelBufferAdaptor!
    var videoSettings: [String : Any]!
    var frameTime: CMTime!
    var fileURL: URL!

    var completionBlock: CXEMovieMakerCompletion?
    var movieMakerUIImageExtractor:CXEMovieMakerUIImageExtractor?


    public class func videoSettings(codec:String, width:Int, height:Int) -> [String: Any]{
        if(Int(width) % 16 != 0){
            print("warning: video settings width must be divisible by 16")
        }

        let videoSettings:[String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                           AVVideoWidthKey: width,
                                          AVVideoHeightKey: height]

        return videoSettings
    }

    public init(videoSettings: [String: Any]) {
        super.init()

        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let tempPath = paths[0] + "/exprotvideo.mp4"
        if(FileManager.default.fileExists(atPath: tempPath)){
            guard (try? FileManager.default.removeItem(atPath: tempPath)) != nil else {
                print("remove path failed")
                return
            }
        }

        self.fileURL = URL(fileURLWithPath: tempPath)
        self.assetWriter = try! AVAssetWriter(url: self.fileURL, fileType: AVFileType.mov)

        self.videoSettings = videoSettings
        self.writeInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
        assert(self.assetWriter.canAdd(self.writeInput), "add failed")

        self.assetWriter.add(self.writeInput)
        let bufferAttributes:[String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
        self.bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.writeInput, sourcePixelBufferAttributes: bufferAttributes)
        self.frameTime = CMTimeMake(value: 4, timescale: 1)
    }

    func createMovieFrom(urls: [URL], withCompletion: @escaping CXEMovieMakerCompletion){
        self.createMovieFromSource(images: urls as [AnyObject], extractor:{(inputObject:AnyObject) ->UIImage? in
            return UIImage(data: try! Data(contentsOf: inputObject as! URL))}, withCompletion: withCompletion)
    }

    func createMovieFrom(images: [UIImage], withCompletion: @escaping CXEMovieMakerCompletion){
        self.createMovieFromSource(images: images, extractor: {(inputObject:AnyObject) -> UIImage? in
            return inputObject as? UIImage}, withCompletion: withCompletion)
    }

    func mergeVideoAndAudio(videoUrl: URL,
                            audioUrl: URL,
                            shouldFlipHorizontally: Bool = false,
                            completion: @escaping (_ error: Error?, _ url: URL?) -> Void) {

        let mixComposition = AVMutableComposition()
        var mutableCompositionVideoTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioOfVideoTrack = [AVMutableCompositionTrack]()

//        start merge

        let aVideoAsset = AVAsset(url: videoUrl)
        let aAudioAsset = AVAsset(url: audioUrl)

        let compositionAddVideo = mixComposition.addMutableTrack(withMediaType: AVMediaType.video,
                                                                       preferredTrackID: kCMPersistentTrackID_Invalid)

        let compositionAddAudio = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                     preferredTrackID: kCMPersistentTrackID_Invalid)

        let compositionAddAudioOfVideo = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                            preferredTrackID: kCMPersistentTrackID_Invalid)

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
            try mutableCompositionVideoTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                duration: aVideoAssetTrack.timeRange.duration),
                                                                of: aVideoAssetTrack,
                                                                at: CMTime.zero)

            //In my case my audio file is longer then video file so i took videoAsset duration
            //instead of audioAsset duration
            try mutableCompositionAudioTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                duration: aVideoAssetTrack.timeRange.duration),
                                                                of: aAudioAssetTrack,
                                                                at: CMTime.zero)

            // adding audio (of the video if exists) asset to the final composition
            if let aAudioOfVideoAssetTrack = aAudioOfVideoAssetTrack {
                try mutableCompositionAudioOfVideoTrack[0].insertTimeRange(CMTimeRangeMake(start: CMTime.zero,
                                                                                           duration: aVideoAssetTrack.timeRange.duration),
                                                                           of: aAudioOfVideoAssetTrack,
                                                                           at: CMTime.zero)
            }
        } catch {
            print(error.localizedDescription)
        }

        // Exporting
        let savePathUrl: URL = URL(fileURLWithPath: NSHomeDirectory() + "/Documents/newVideo.mp4")
        do { // delete old video
            try FileManager.default.removeItem(at: savePathUrl)
        } catch { print(error.localizedDescription) }

        let assetExport: AVAssetExportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)!
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

    private func createMovieFromSource(images: [AnyObject], extractor: @escaping CXEMovieMakerUIImageExtractor, withCompletion: @escaping CXEMovieMakerCompletion){
            self.completionBlock = withCompletion

            self.assetWriter.startWriting()
        self.assetWriter.startSession(atSourceTime: CMTime.zero)

            let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
            var i = 0
            let frameNumber = images.count
            self.writeInput.requestMediaDataWhenReady(on: mediaInputQueue){
                while(true){
                    if(i >= frameNumber){
                        break
                    }

                    if (self.writeInput.isReadyForMoreMediaData){
                        var sampleBuffer:CVPixelBuffer?
                        autoreleasepool{
                            let img = extractor(images[i])
                            if img == nil{
                                i += 1
                                print("Warning: counld not extract one of the frames")
    //                            continue
                            }
                            sampleBuffer = self.newPixelBufferFrom(cgImage: img!.cgImage!)
                        }
                        if (sampleBuffer != nil){
                            if(i == 0){
                                self.bufferAdapter.append(sampleBuffer!, withPresentationTime: CMTime.zero)
                            }else{
                                let value = i - 1
                                let lastTime = CMTimeMake(value: Int64(value), timescale: self.frameTime.timescale)
                                let presentTime = CMTimeAdd(lastTime, self.frameTime)
                                self.bufferAdapter.append(sampleBuffer!, withPresentationTime: presentTime)
                            }
                            i = i + 1
                        }
                    }
                }
                self.writeInput.markAsFinished()
                self.assetWriter.finishWriting {
                    DispatchQueue.main.sync {
                        let url = Bundle.main.url(forResource: "music", withExtension: "aac")!
                        self.mergeVideoAndAudio(videoUrl: self.fileURL, audioUrl: url) { error, url in
                            if let url = url {
                                self.completionBlock!(url)
                            }
                        }
                    }
                }
            }
        }

    func newPixelBufferFrom(cgImage:CGImage) -> CVPixelBuffer?{
        let options:[String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        var pxbuffer:CVPixelBuffer?
        let frameWidth = self.videoSettings[AVVideoWidthKey] as! Int
        let frameHeight = self.videoSettings[AVVideoHeightKey] as! Int

        let status = CVPixelBufferCreate(kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32ARGB, options as CFDictionary?, &pxbuffer)
        assert(status == kCVReturnSuccess && pxbuffer != nil, "newPixelBuffer failed")

        CVPixelBufferLockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pxdata = CVPixelBufferGetBaseAddress(pxbuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pxdata, width: frameWidth, height: frameHeight, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pxbuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        assert(context != nil, "context is nil")

        context!.concatenate(CGAffineTransform.identity)
        context!.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        CVPixelBufferUnlockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
        return pxbuffer
    }
}
