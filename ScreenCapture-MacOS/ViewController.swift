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
  let duration: Double?
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
            //          "mute":            false,
            //          "videoCodec":      "h264"
            //        }
            let displayId = CGMainDisplayID()
            let cropRect: CGRect = CGRect.null
            let camOnly = true
            let mute = false
            let displayWidth = CGDisplayPixelsWide(displayId)
            let displayHeight = CGDisplayPixelsHigh(displayId)
            var width: Int = 0
            var height: Int = 0
            let showCursor = true
            let highlightClicks = false
            let hdEnabled = false
            var avgBitRate = 0
            let fps = 60
            let durationSecond : Double = 10

            var videoDevice = AVCaptureDevice.default(for: AVMediaType.video)
            var audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)

            
            printWithPrepend("showCursor: \(showCursor)")
            printWithPrepend("highlightClicks: \(highlightClicks)")

            printWithPrepend("hdEnabled: \(hdEnabled)")

            printWithPrepend("camOnly: \(camOnly)")
            printWithPrepend("Mute: \(mute)")

            
            if cropRect != CGRect.null {
                width = Int(cropRect.width)
            } else {
                width = displayWidth
            }
            
            if cropRect != CGRect.null {
                height = Int(cropRect.height)
            } else {
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
            
            if width > 0 && height > 0 {
                avgBitRate = getBitRateForNumPixels(width * height)
            }
            
            let pulledVideoDeviceId = "FaceTime HD Camera (Built-in)"

            if camOnly {
                if let pulledVideoDevice = getCameraCaptureDeviceForElectronId(pulledVideoDeviceId) {
                    videoDevice = pulledVideoDevice
                }
            } else {
                videoDevice = nil
            }
            
            if videoDevice != nil {
                printWithPrepend("videoDevice: \(videoDevice!.localizedName)")
            }
            let pulledAudioDeviceId = "MacBook Pro Microphone"
            if !mute {
                if let pulledAudioDevice = getAudioDeviceForElectronId(pulledAudioDeviceId) {
                    audioDevice = pulledAudioDevice
                }
            } else {
                audioDevice = nil
            }

            if audioDevice != nil {
                printWithPrepend("audioDevice: \(audioDevice!.localizedName)")
            }
            
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
                                        duration: durationSecond)
        }catch {
            printErr("Error" as! Error)
        }
        recorder11.onStart = {
            if let printStr = self.dicToJSON(dic: ["status":"STRATED"]), printStr != ""{
                print(printStr)
            }
            
        }
        
        recorder11.onFinish = {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1000)) {
                if let printStr = self.dicToJSON(dic: ["status":"END","totalChunks":"\(self.recorder11.capture.counter-1)"]), printStr != ""{
                    print(printStr)
                }
            }
        }
        
        recorder11.onWrite = { (url: URL) -> Void in
            if let printStr = self.dicToJSON(dic: ["status":"PROGRESS","chunkNumber":"\(url.pathComponents.last?.dropLast(4) ?? "")","location":"\(url.path)"]), printStr != ""{
                print(printStr)
            }
        }
        
        recorder11.onError = {(error:Error) -> Void in
            printWithPrepend("[status:ERROR]")
            self.recorder11 = nil
        }

        // Do any additional setup after loading the view.
    }
    func dicToJSON(dic:NSDictionary) -> String?{
        if let theJSONData = try? JSONSerialization.data(
            withJSONObject: dic,
            options: []) {
            let theJSONText = String(data: theJSONData,
                                     encoding: .utf8)
            return theJSONText ?? ""
        }
        return ""
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

