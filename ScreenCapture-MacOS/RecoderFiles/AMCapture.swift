//
//  AMCapture.swift
//
//  Copyright © 2020 AnimakerPC167. All rights reserved.
//

import Foundation
import AVFoundation

//struct URLIterator  {
//  private var directory: URL
//
//  init(directory: URL) {
//    self.directory = directory
//  }
//
//    mutating func next(count:Int) -> Element? {
//    let component = "\(count).mp4"
//    return directory.appendingPathComponent(component)
//  }
//}

final class AMCapture : NSObject {
  let duration: Double
  var hasStarted = false
  var isRecording = false

  private var segmentTimer: Timer?

  // pause/resume state
  var paused = false
  private var _discontinuedTimeOnResume = false
    var _timeOffset = CMTimeMake(0, 0)
    var _lastVideo = CMTimeMake(0, 0)
    var _lastAudio = CMTimeMake(0, 0)
    // used for determining when to split files
    // calculated by keeping sum of durations of incoming CMSampleBuffers
    private var _durationForSplitting: Double = 0

  // let the capturer know we should call onStop when the last
  // file comes through
  var stopping = false
  var mute = false
  fileprivate let session: AVCaptureSession

  // assign the highest qos to these queues to ensure power is funneled
  // to the tasks (handling sample buffers)
  // https://developer.apple.com/documentation/dispatch/dispatchqos
  fileprivate let captureQueue = DispatchQueue(label: "capture.capture-queue",
                                                    qos: .userInteractive)

  fileprivate let audioOutput: AVCaptureAudioDataOutput?
  fileprivate let videoOutput: AVCaptureVideoDataOutput
  let videoEncoder: AMScreenWriter
//  var urlIterator : URLIterator
  var counter: Int
  var urlIterator: URL
    
  fileprivate let width: Int
  fileprivate let height: Int

  var onStart: (() -> Void)?
  var onStop: ((URL) -> Void)?
  var onError: ((Error) -> Void)?
  var onWrite: ((URL) -> Void)?

  public init(audioInput: AVCaptureInput?,
              videoInput: AVCaptureInput,
              avgBitRate: Int,
              recordInMono: Bool,
              isFlip:Bool,
              fps: Int,
              width: Int,
              height: Int,
              directory: URL,
              duration: Double) throws {
    self.duration = duration
    self.width = width
    self.height = height

    self.urlIterator = directory
    counter = 0
    self._durationForSplitting = 0

    session = AVCaptureSession()

    if session.canAddInput(videoInput) {
      session.addInput(videoInput)
    } else {
      throw AMRecorderError.couldNotAddVideoInput
    }

    if let pulledAudioInput = audioInput {
      if session.canAddInput(pulledAudioInput) {
        session.addInput(pulledAudioInput)
      } else {
        throw AMRecorderError.couldNotAddMic
      }

      audioOutput = AVCaptureAudioDataOutput()

      if session.canAddOutput(audioOutput!) {
        session.addOutput(audioOutput!)
      } else {
        throw AMRecorderError.couldNotAddOutput
      }
    } else {
      audioOutput = nil
    }

    videoOutput = AVCaptureVideoDataOutput()

    // setting the buffer width/height
    videoOutput.videoSettings = [
      kCVPixelBufferWidthKey: width,
      kCVPixelBufferHeightKey: height
    ] as [String: Any]

    // We're recording, so we don't want to drop frames.
    // By setting alwaysDiscardsLateVideoFrames to false we ensure that
    // minor fluctuations in system load or in our processing time for a
    // given frame won't cause framedrops.
    //
    // TODO: we might want to play with turning this on/off under high load
    videoOutput.alwaysDiscardsLateVideoFrames = false

    if session.canAddOutput(videoOutput) {
      session.addOutput(videoOutput)
    } else {
      throw AMRecorderError.couldNotAddOutput
    }

    videoEncoder = AMScreenWriter(width, height, avgBitRate, fps: fps,recordInMono: recordInMono,isFlip: isFlip)

    defer {
      audioOutput?.setSampleBufferDelegate(self, queue: captureQueue)
      videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
    }

    session.commitConfiguration()

    super.init()

    self.initStart()
  }

  private func createSegmentTimer() {
    if isRecording {
      segmentTimer = Timer.scheduledTimer(timeInterval: duration,
                                          target: self,
                                          selector: #selector(startRecordingToNext),
                                          userInfo: nil,
                                          repeats: false)
    }
  }
  func next(count:Int) -> URL{
    let component = "\(count).mp4"
    return self.urlIterator.appendingPathComponent(component)
  }

  @objc private func startRecordingToNext() {
//    let url = self.next(count: counter)
//    counter += 1
//    do {
//      try videoEncoder.startWriting(url: url)
//    } catch {
//      self.onError?(AMRecorderError.recordToNewEncoder)
//    }
    // protect against this function potentially getting called multiple times
    // from different threads
    objc_sync_enter(self)
    defer { objc_sync_exit(self) }
    

    do {
        try self.initNextVideoEncoder()
    } catch {
        self.onError?(AMRecorderError.recordToNewEncoder)
    }

//    createSegmentTimer()
  }

  // it makes more sense for all of this logic to live in start, but
  // we want there to be no delay with the start of a recording and
  // when the start recording sound ends
  private func initStart() {
    videoEncoder.onStart = {
      printWithPrepend("VideoEncoder started...")

      if !self.hasStarted {
        self.hasStarted = true
        self.onStart?()
      }
    }

    videoEncoder.onFinish = { (outputFileURL: URL) -> Void in
      printWithPrepend("VideoEncoder finished...")
        self.onStop?(outputFileURL)
    }

    videoEncoder.onWrite = { (outputFileURL: URL) -> Void in
      printWithPrepend("VideoEncoder wrote \(outputFileURL.path)")
      self.onWrite?(outputFileURL)
    }
    captureQueue.async {
      self.session.startRunning()
    }

//    startRecordingToNext()
    do {
        try self.initNextVideoEncoder()
    } catch {
        self.onError?(AMRecorderError.couldNotInitializeEncoder)
    }

    _timeOffset = CMTimeMake(0, 0)

    // ensure this happens below the first initialization of the
    // video encoder in "startRecordingToNext"
  }
    private func initNextVideoEncoder() throws {
        let url = self.next(count: counter)
        counter += 1

        try videoEncoder.startWriting(url: url)
    }

  public func start() {
    if isRecording {
      return
    }

    isRecording = true

//    createSegmentTimer()
  }

  func stop() {
    if !isRecording {
      return
    }

    if let timer = segmentTimer {
      timer.invalidate()
    }

    isRecording = false
    captureQueue.async { () -> Void in
      self.session.stopRunning()
      self.videoEncoder.stopWriting()
    }
  }

  func pause() {
    if !isRecording || paused {
      return
    }

//    if let timer = segmentTimer {
//      timer.invalidate()
//    }

    paused = true
    _discontinuedTimeOnResume = true
//    captureQueue.async { () -> Void in
////      self.session.stopRunning()
//      self.videoEncoder.tempStopWriting()
//    }

    printWithPrepend("paused recorder")
  }

  func resume() {
    if !paused {
      return
    }
    paused = false

//    startRecordingToNext()

    printWithPrepend("resumed recorder")
  }
}

// complete explanation of pause/resume and data output buffers:
// https://www.useloom.com/share/04a77595aac64b45a23874a467dec327
extension AMCapture: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput,
                     didOutput sampleBuffer: CMSampleBuffer,
                     from connection: AVCaptureConnection) {
    if !sampleBuffer.ready || !isRecording || paused {
      return
    }
    let isVideoBuffer = output == videoOutput;
    var isAudioBuffer = output == audioOutput;
    var videoOnlyOutput = audioOutput == nil
//    if mute{
//        isAudioBuffer = false
//        videoOnlyOutput = true
//    }
    print("Video : \(isVideoBuffer) Audio : \(isAudioBuffer)")

    // pause functionality inspired by:
    // http://www.gdcl.co.uk/2013/02/20/iPhone-Pause.html
    if _discontinuedTimeOnResume {
      if isVideoBuffer {
        return
      }
      _discontinuedTimeOnResume = false

      // calculate adjustment
      var pts = sampleBuffer.presentation
      let last = isVideoBuffer ? _lastVideo : _lastAudio

      if last.flags.contains(CMTimeFlags.valid) {
        if _timeOffset.flags.contains(CMTimeFlags.valid) {
          pts = CMTimeSubtract(pts, _timeOffset)
        }

        let offset = CMTimeSubtract(pts, last)

        // this stops us having to set a scale for _timeOffset before we see the first video time
        if _timeOffset.value == 0 {
          _timeOffset = offset
        } else {
          _timeOffset = CMTimeAdd(_timeOffset, offset)
        }
      }

      _lastVideo.flags = CMTimeFlags.init(rawValue: 0)
      _lastAudio.flags = CMTimeFlags.init(rawValue: 0)
    }

    var bufferToWrite = sampleBuffer

    if _timeOffset.value > 0 {
      bufferToWrite = sampleBuffer.adjustTime(offset: _timeOffset)
    }

    // record most recent time so we know the length of the pause
    var pts = bufferToWrite.presentation
    let dur = bufferToWrite.duration

    if dur.value > 0 {
      pts = CMTimeAdd(pts, dur);
    }

    if isVideoBuffer {
      _lastVideo = pts;
    } else {
      _lastAudio = pts;
    }

    if isVideoBuffer {
        self.videoEncoder.appendBuffer(bufferToWrite, isVideo: true)
            self._lastVideo = pts;
        
        if videoOnlyOutput {
            self.determineToSplitToNextFile(dur: dur)
        }

//      videoEncoder.appendBuffer(bufferToWrite, isVideo: true)
    } else if isAudioBuffer {
        if !mute{
            videoEncoder.appendBuffer(bufferToWrite, isVideo: false)
            self._lastAudio = pts;
            self.determineToSplitToNextFile(dur: dur)

        }
    } else {
      printErr(AMRecorderError.unknownDataOutputType)
    }
  }
    private func determineToSplitToNextFile(dur: CMTime) {
        self._durationForSplitting = self._durationForSplitting + CMTimeGetSeconds(dur)
        
        if self._durationForSplitting > self.duration {
            printWithPrepend("Splitting file from buffer \(self._durationForSplitting)")
            
            self._durationForSplitting = 0
            startRecordingToNext()
        }
    }

  func captureOutput(_ output: AVCaptureOutput,
                     didDrop sampleBuffer: CMSampleBuffer,
                     from connection: AVCaptureConnection) {
    if output == audioOutput {
      printWithPrepend("dropped audio frame")
    } else {
      printWithPrepend("dropped video frame")
    }
  }
}
