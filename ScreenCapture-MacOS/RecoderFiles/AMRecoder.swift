//
//  AMRecoder.swift
//
//  Copyright © 2020 AnimakerPC167. All rights reserved.
//

import AVFoundation

enum AMRecorderError: Error {
  case invalidAudioDevice
  case invalidVideoDevice
  case couldNotAddMic
  case couldNotAddOutput
  case couldNotAddVideoInput
  case recordToNewEncoder
  case unknownDataOutputType
}


class AMRecorder {
  private var cropRect: CGRect?
  private var displayID: CGDirectDisplayID
  private let fps: Int
  private let highlightClicks: Bool
  private let showCursor: Bool
  let capture: AMCapture

  var onStart: (() -> Void)?
  var onFinish: ((URL) -> Void)?
  var onError: ((Error) -> Void)?
  var onWrite: ((URL) -> Void)?

  var duration: Double {
    return capture.duration
  }

  var stopping = false

  func start() {
    capture.start()
  }

  func pause() {
    capture.pause()
  }

  func resume() {
    capture.resume()
  }
    func mute() {
      capture.mute = true
    }

    func unmute() {
      capture.mute = false
    }

  func stop() {
    stopping = true
    capture.stop()
  }

  init(outputPath: String,
       avgBitRate: Int,
       fps: Int,
       cropRect: CGRect,
       height: Int,
       width: Int,
       showCursor: Bool,
       highlightClicks: Bool,
       recordInMono:Bool,
       displayID: CGDirectDisplayID,
       audioDevice: AVCaptureDevice?,
       videoDevice: AVCaptureDevice?,
       duration: Double) throws {

    self.cropRect = cropRect
    self.displayID = displayID
    self.fps = fps
    self.highlightClicks = highlightClicks
    self.showCursor = showCursor

    let directory = URL(fileURLWithPath: outputPath, isDirectory: true)

    var audioInput: AVCaptureDeviceInput? = nil

    if let pulledAudioInput = audioDevice, pulledAudioInput.isConnected && !pulledAudioInput.isSuspended {
      audioInput = try! AVCaptureDeviceInput.init(device: pulledAudioInput)
    }

    var videoInput: AVCaptureDeviceInput? = nil
    var screenInput: AVCaptureScreenInput? = nil

    if let pulledVideoInput = videoDevice, pulledVideoInput.isConnected && !pulledVideoInput.isSuspended {
      videoInput = try! AVCaptureDeviceInput.init(device: pulledVideoInput)
    } else {
      screenInput = AVCaptureScreenInput(displayID: displayID,
                                         fps: fps, cropRect: cropRect,
                                         showCursor: showCursor,
                                         highlightCursor: highlightClicks)!
    }

    capture = try AMCapture(audioInput: audioInput,
                             videoInput: videoInput ?? screenInput!,
                             avgBitRate: avgBitRate,
                             recordInMono: recordInMono,
                             fps: fps,
                             width: width,
                             height: height,
                             directory: directory,
                             duration: duration)

    capture.onWrite = { (url: URL) -> Void in
      self.onWrite?(url)
    }

    capture.onStart = { () -> Void in
      printWithPrepend("started recorder")
      self.onStart?()
    }

    capture.onStop = { (url: URL) -> Void in
      printWithPrepend("stopped recorder")
        self.onFinish?(url)
    }

    capture.onError = { (error: Error) -> Void in
      self.onError?(error)
    }
  }
}

