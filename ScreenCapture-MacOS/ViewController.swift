//
//  ViewController.swift
//  ScreenCapture-MacOS
//
//  Created by AnimakerPC167 on 25/09/20.
//

import Cocoa
import AVFoundation

struct RecordingOptions: Decodable {
  let avgBitRate: Int?
  let fps: Int?
  let camOnly: Bool?
  let cropRect: CGRect?
  let width: Int?
  let height: Int?
  let showCursor: Bool?
  let hdEnabled: Bool?
  let highlightClicks: Bool?
  let displayId: CGDirectDisplayID?
  let audioDeviceId: String?
  let videoDeviceId: String?
  let outputPath: String?
  let duration: CGFloat?
}

class ViewController: NSViewController {
    
    var recorder11: AMRecorder!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        self.clearTempFolder()
        do {

//        {
//          "avgBitRate":      10000000,
//          "fps":             30,
//          "outputPath":      "/path/to/recording.mp4",
//          "camOnly":         false,
//          "cropRect":        { "x": 0, "y": 0, "width": 100, "height": 100 },
//          "width":           100,
//          "height":          100,
//          "showCursor":      true,
//          "highlightClicks": true,
//          "hdEnabled":       false,
//          "displayId":       "main",
//          "audioDeviceId":   "main",
//          "videoDeviceId":   "main",
//          "videoCodec":      "h264"
//        }
        var displayId = CGMainDisplayID()
        var cropRect: CGRect = CGRect.null
        var camOnly = false
        let displayWidth = CGDisplayPixelsWide(displayId)
        let displayHeight = CGDisplayPixelsHigh(displayId)

        printWithPrepend("camOnly: \(camOnly)")

        var width: Int = 0
        var height: Int = 0

        if cropRect != CGRect.null {
          width = Int(cropRect.width)
        } else if !camOnly {
          width = displayWidth
        }

        if cropRect != CGRect.null {
          height = Int(cropRect.height)
        } else if !camOnly {
          height = displayHeight
        }

        // ensure we're not scaling past bounds of screen
        if !camOnly, let modeRef = CGDisplayCopyDisplayMode(displayId) {
          if width > modeRef.pixelWidth {
            width = modeRef.pixelWidth
            printWithPrepend("supplied width > screen bounds \(width) > \(modeRef.pixelWidth) - scaling back")
          }

          if height > modeRef.pixelHeight {
            height = modeRef.pixelHeight
            printWithPrepend("supplied height > screen bounds \(height) > \(modeRef.pixelHeight) - scaling back")
          }
        }

        var showCursor = true

        printWithPrepend("showCursor: \(showCursor)")

        var highlightClicks = false

        printWithPrepend("highlightClicks: \(highlightClicks)")

        let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)

        if audioDevice != nil {
          printWithPrepend("audioDevice: \(audioDevice!.localizedName)")
        }

        var hdEnabled = false

        printWithPrepend("hdEnabled: \(hdEnabled)")

        var avgBitRate = 0

         if width > 0 && height > 0 {
          avgBitRate = getBitRateForNumPixels(width * height)
        }

        var videoDevice = AVCaptureDevice.default(for: AVMediaType.video)
            if !camOnly, let modeRef = CGDisplayCopyDisplayMode(displayId) {
              if width > modeRef.pixelWidth {
                width = modeRef.pixelWidth
                printWithPrepend("supplied width > screen bounds \(width) > \(modeRef.pixelWidth) - scaling back")
              }

              if height > modeRef.pixelHeight {
                height = modeRef.pixelHeight
                printWithPrepend("supplied height > screen bounds \(height) > \(modeRef.pixelHeight) - scaling back")
              }
            }

//        if camOnly, let pulledVideoDeviceId = recordingOptions.videoDeviceId {
//          if let pulledVideoDevice = getCameraCaptureDeviceForElectronId(pulledVideoDeviceId) {
//            videoDevice = pulledVideoDevice
//          }
//        } else {
//          videoDevice = nil
//        }

        if videoDevice != nil {
          printWithPrepend("videoDevice: \(videoDevice!.localizedName)")
        }

        var fps = 60

            
        recorder11 = try AMRecorder(outputPath: tempFile().path,
        avgBitRate: avgBitRate,
        fps: fps,
        cropRect: cropRect,
        height: height,
        width: width,
        showCursor: showCursor,
        highlightClicks: highlightClicks,
        displayID: displayId,
        audioDevice: audioDevice,
        videoDevice: videoDevice,
        duration: 10)
        }catch {
            printErr("Error" as! Error)
        }
        recorder11.onStart = {
          printWithPrepend("Started recording...")

        }

        recorder11.onFinish = {
          printWithPrepend("Finished recording...")
        }

        recorder11.onWrite = { (url: URL) -> Void in
            print(url.path)
        }

        recorder11.onError = {(error:Error) -> Void in
            self.recorder11 = nil
        }

        // Do any additional setup after loading the view.
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }
    func clearTempFolder() {
        let fileManager = FileManager.default
        let searchPaths: [String] = NSSearchPathForDirectoriesInDomains(.documentDirectory, .allDomainsMask, true)
        let documentPath_ = searchPaths.first
        let pathToSave = "\(documentPath_!)"

        do {
            let filePaths = try fileManager.contentsOfDirectory(atPath: pathToSave)
            for filePath in filePaths {
                try fileManager.removeItem(atPath: pathToSave + "/" + filePath)
            }
        } catch {
            print("Could not clear temp folder: \(error)")
        }
    }

    func tempFile() -> URL{
        let searchPaths: [String] = NSSearchPathForDirectoriesInDomains(.documentDirectory, .allDomainsMask, true)
        let documentPath_ = searchPaths.first
        let pathToSave = "\(documentPath_!)"
        print(pathToSave)
        return URL(fileURLWithPath: pathToSave)
    }
    @IBAction func actionStart(_ sender: Any) {
        recorder11.start()
    }
    @IBAction func actionPause(_ sender: Any) {
        recorder11.pause()
    }
    @IBAction func actionResume(_ sender: Any) {
        recorder11.resume()
    }

    @IBAction func action(_ sender: Any) {
        recorder11.stop()
//        recorder11 = nil
//        exit(0)
    }
}

