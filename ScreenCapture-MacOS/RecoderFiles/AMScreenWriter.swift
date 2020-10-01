//
//  AMScreenWriter.swift
//  MyNew
//
//  Created by AnimakerPC167 on 21/09/20.
//  Copyright © 2020 AnimakerPC167. All rights reserved.
//

import AVFoundation

enum AMScreenWriterError: Error {
  case couldNotInitAssetWriter
  case couldNotFindEncoderPreset
  case couldNotApplyAudioOutputSettings
  case couldNotApplyVideoOutputSettings
}

class AMScreenWriter {
  // writers
  var currentAssetWriter: AVAssetWriter? = nil
  private var videoInputWriter: AVAssetWriterInput? = nil
  private var audioInputWriter: AVAssetWriterInput? = nil

  var queuedAssetWriter: AVAssetWriter? = nil
  private var queuedVideoInputWriter: AVAssetWriterInput? = nil
  private var queuedAudioInputWriter: AVAssetWriterInput? = nil

  private var currentUrl: URL?
  private var queuedUrl: URL?
    private var lastVideoEndTime: CMTime = kCMTimeZero
  var swapWriters = false

  // encoding state
  var hasStarted = false
  private var startTime: CMTime? = nil
  var hasEnded = false
  var stopping = false
  var tempStopping = false

  // settings
  private var videoOutputSettings: [String: Any]
  private let audioOutputSettings: [String: Any]

  var onStart: (() -> Void)?
  var onFinish: ((URL) -> Void)?
  var onWrite: ((URL) -> Void)?

  init(_ width: Int,_ height: Int,_ avgBitRate: Int, fps: Int,recordInMono: Bool) {
    hasStarted = false

    videoOutputSettings = [
      AVVideoCodecKey: AVVideoCodecH264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: avgBitRate,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
      ]
    ]
    audioOutputSettings = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 44100,
      AVNumberOfChannelsKey: recordInMono ? 1 : 2
    ]


    // We use the average bit rate for 2160p in the Electron layer to
    // calculate capabilities based on network speeds, but we don't actually
    // apply it at the swift layer since monitors may go up in resolution quite
    // a bit and we might produce a low-quality video. Just let Apple decide
    // what the bit rate should be. If someone wants to record 4k videos, they
    // want a high-quality recording.
    let numPixels = width * height
    if numPixels >= numPixels2160p {
      videoOutputSettings[AVVideoCompressionPropertiesKey] = [
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
      ]
    } else {
      videoOutputSettings[AVVideoCompressionPropertiesKey] = [
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
        AVVideoAverageBitRateKey: avgBitRate
      ]
    }

    videoInputWriter = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoOutputSettings)
    videoInputWriter!.expectsMediaDataInRealTime = true
    audioInputWriter = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettings)
    audioInputWriter!.expectsMediaDataInRealTime = true
  }

  func startWriting(url: URL) throws {
    if stopping {
      return
    }
    self.tempStopping = false
    if currentAssetWriter != nil && queuedAssetWriter == nil {
      queuedUrl = url
      queuedAssetWriter = try AVAssetWriter(url: queuedUrl!, fileType: AVFileType.mp4)
      queuedAssetWriter!.shouldOptimizeForNetworkUse = true
      queuedVideoInputWriter = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoOutputSettings)
      queuedVideoInputWriter!.expectsMediaDataInRealTime = true
      queuedAudioInputWriter = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettings)
      queuedAudioInputWriter!.expectsMediaDataInRealTime = true
      queuedAssetWriter!.add(queuedVideoInputWriter!)
      queuedAssetWriter!.add(queuedAudioInputWriter!)
      queuedAssetWriter!.startWriting()
      queuedAssetWriter!.startSession(atSourceTime: startTime!)
      swapWriters = true
      return
    }

    currentUrl = url


    do {
      currentAssetWriter = try AVAssetWriter(url: currentUrl!, fileType: AVFileType.mp4)
      currentAssetWriter!.shouldOptimizeForNetworkUse = true
    } catch {
      throw AMScreenWriterError.couldNotInitAssetWriter
    }

    if videoInputWriter == nil{
        videoInputWriter = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoOutputSettings)
        videoInputWriter!.expectsMediaDataInRealTime = true
        currentAssetWriter!.add(videoInputWriter!)
    }
    else if currentAssetWriter!.canAdd(videoInputWriter!) {
      currentAssetWriter!.add(videoInputWriter!)
    } else {
      throw AMScreenWriterError.couldNotInitAssetWriter
    }
    
    if audioInputWriter == nil{
        audioInputWriter = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettings)
        audioInputWriter!.expectsMediaDataInRealTime = true
        currentAssetWriter!.add(audioInputWriter!)
    }
    else if currentAssetWriter!.canAdd(audioInputWriter!) {
      currentAssetWriter!.add(audioInputWriter!)
    } else {
      throw AMScreenWriterError.couldNotInitAssetWriter
    }

    guard currentAssetWriter!.canApply(outputSettings: videoOutputSettings, forMediaType: AVMediaType.video) else {
      throw AMScreenWriterError.couldNotApplyVideoOutputSettings
    }
    guard currentAssetWriter!.canApply(outputSettings: audioOutputSettings, forMediaType: AVMediaType.audio) else {
      throw AMScreenWriterError.couldNotApplyAudioOutputSettings
    }

  }
    
  func tempStopWriting()
  {
    tempStopping = true
    let tmpUrl = self.currentUrl!
    currentAssetWriter!.endSession(atSourceTime: lastVideoEndTime)
    currentAssetWriter!.finishWriting { () -> Void in
      self.onWrite?(tmpUrl)
    }
    currentAssetWriter = nil
    videoInputWriter = nil
    audioInputWriter = nil

    if swapWriters{
        queuedAssetWriter = nil
        queuedVideoInputWriter = nil
        queuedAudioInputWriter = nil
        queuedUrl = nil
        swapWriters = false
    }
  }
  func stopWriting() {
    stopping = true
    if !tempStopping
    {
        videoInputWriter!.markAsFinished()
        audioInputWriter!.markAsFinished()
        currentAssetWriter!.endSession(atSourceTime: lastVideoEndTime)
        currentAssetWriter!.finishWriting { () -> Void in
          self.hasEnded = true
//          self.onWrite?(self.currentUrl!)
          self.onFinish?(self.currentUrl!)
        }
    }
    else{
        self.hasEnded = true
        self.onFinish?(self.currentUrl!)
    }
    currentAssetWriter = nil
    videoInputWriter = nil
    audioInputWriter = nil
    if swapWriters{
        queuedAssetWriter = nil
        queuedVideoInputWriter = nil
        queuedAudioInputWriter = nil
        queuedUrl = nil
        swapWriters = false
    }

  }

  func appendBuffer(_ sampleBuffer: CMSampleBuffer!, isVideo: Bool) {
    if hasEnded || currentAssetWriter == nil || videoInputWriter == nil{
      return
    }

    if !isVideo && !hasStarted {
      return
    } else if !hasStarted {
      hasStarted = true
      onStart?()
    }

    if sampleBuffer.ready {
      let samplePts = sampleBuffer.presentation
      let sampleDuration = sampleBuffer.duration
      let sampleEndTime = CMTimeAdd(samplePts, sampleDuration)

      if swapWriters && !isVideo {
        // only append to the next file if this sample extends past
        // the last video end time
        if CMTimeCompare(sampleEndTime, lastVideoEndTime) > 0 {
          queuedAudioInputWriter!.append(sampleBuffer)
        }
      } else if swapWriters && isVideo {
        let tmpUrl = self.currentUrl!
        currentAssetWriter!.endSession(atSourceTime: lastVideoEndTime)
        currentAssetWriter!.finishWriting { () -> Void in
          self.onWrite?(tmpUrl)
        }

        currentAssetWriter = queuedAssetWriter
        currentUrl = queuedUrl
        videoInputWriter = queuedVideoInputWriter
        audioInputWriter = queuedAudioInputWriter
        queuedAssetWriter = nil
        queuedVideoInputWriter = nil
        queuedAudioInputWriter = nil
        queuedUrl = nil
        swapWriters = false
      }

      if currentAssetWriter!.status == AVAssetWriter.Status.unknown {
        if startTime == nil {
          startTime = samplePts
        }

        currentAssetWriter!.startWriting()
        currentAssetWriter!.startSession(atSourceTime: startTime!)
      }

      if isVideo {
        if videoInputWriter!.isReadyForMoreMediaData {
          videoInputWriter!.append(sampleBuffer)
          lastVideoEndTime = sampleEndTime
        }
      } else {
        if self.audioInputWriter!.isReadyForMoreMediaData {
          audioInputWriter!.append(sampleBuffer)
        }
      }
    }
  }
}
