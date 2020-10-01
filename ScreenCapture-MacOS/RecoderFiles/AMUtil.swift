//
//  AMUtil.swift
//  MyNew
//
//  Created by AnimakerPC167 on 21/09/20.
//  Copyright © 2020 AnimakerPC167. All rights reserved.
//

import Foundation
import AVFoundation

let logPrepend = "🍎 mac binary:"

private final class StandardErrorOutputStream: TextOutputStream {
  func write(_ string: String) {
    FileHandle.standardError.write(string.data(using: .utf8)!)
  }
}

private var stderr = StandardErrorOutputStream()

func printErr(_ item: Error) {
  print("\(logPrepend) error: \(item)", to: &stderr)

  // https://stackoverflow.com/a/30814498/696130
  Thread.callStackSymbols.forEach{print($0, to: &stderr)}
}

func printWithPrepend(_ text: String, file: String = #file, line: Int = #line, function: String = #function) {
  print("\(logPrepend) \(URL(fileURLWithPath: file).lastPathComponent):\(line) : \(function): \(text)")
    fflush(stdout)
}


// NOTE: when updating this file, please consider updating
//       src/js/shared/constants/resolution.js

// bit rate settings used by our transcoder
let numPixels360p = 172800 // 480×360
let numPixels480p = 307200 // 640×480
let numPixels720p = 921600 // 1280x720
let numPixels1080p = 2073600 // 1920x1080
let numPixels1440p = 3686400 // 2560x1440
let numPixels2160p = 8294400 // 3840x2160

// follow suit from YouTube's recommendations for uploads:
// https://support.google.com/youtube/answer/1722171?hl=en
let avgBitRate360p = 1000000 // 1 megabit
let avgBitRate480p = 2500000 // 2.5 megabits
let avgBitRate720p = 5000000 // 5 megabits
let avgBitRate1080p = 8000000 // 8 megabits
let avgBitRate1440p = 12000000 // 12 megabits
let avgBitRate2160p = 18000000 // 18 megabits


func getBitRateForNumPixels(_ numPixels: Int) -> Int {
  if numPixels < numPixels480p {
    return avgBitRate360p;
  } else if numPixels >= numPixels480p && numPixels < numPixels720p {
    return avgBitRate480p;
  } else if numPixels >= numPixels720p && numPixels < numPixels1080p {
    return avgBitRate720p;
  } else if numPixels >= numPixels1080p && numPixels < numPixels1440p {
    return avgBitRate1080p;
  } else if numPixels >= numPixels1440p && numPixels < numPixels2160p {
    return avgBitRate1440p;
  } else if numPixels >= numPixels2160p {
    return avgBitRate2160p;
  }

  // should be impossible to reach this point, but return 1080p as the default
  return avgBitRate1080p;
}

// MARK: - SignalHandler
struct SignalHandler {
  struct Signal: Hashable {
    static let hangup = Signal(rawValue: SIGHUP)
    static let interrupt = Signal(rawValue: SIGINT)
    static let quit = Signal(rawValue: SIGQUIT)
    static let abort = Signal(rawValue: SIGABRT)
    static let kill = Signal(rawValue: SIGKILL)
    static let alarm = Signal(rawValue: SIGALRM)
    static let termination = Signal(rawValue: SIGTERM)
    static let userDefined1 = Signal(rawValue: SIGUSR1)
    static let userDefined2 = Signal(rawValue: SIGUSR2)
 
    /// Signals that cause the process to exit
    static let exitSignals = [
      hangup,
      interrupt,
      quit,
      abort,
      alarm,
      termination
    ]

    let rawValue: Int32
    init(rawValue: Int32) {
      self.rawValue = rawValue
    }
  }

  typealias CSignalHandler = @convention(c) (Int32) -> Void
  typealias SignalHandler = (Signal) -> Void

  private static var handlers = [Signal: [SignalHandler]]()

  private static var cHandler: CSignalHandler = { rawSignal in
    let signal = Signal(rawValue: rawSignal)

    guard let signalHandlers = handlers[signal] else {
      return
    }

    for handler in signalHandlers {
      handler(signal)
    }
  }

  /// Handle some signals
  static func handle(signals: [Signal], handler: @escaping SignalHandler) {
    for signal in signals {
      // Since Swift has no way of running code on "struct creation", we need to initialize here…
      if handlers[signal] == nil {
        handlers[signal] = []
      }
      handlers[signal]?.append(handler)

      var signalAction = sigaction(
        __sigaction_u: unsafeBitCast(cHandler, to: __sigaction_u.self),
        sa_mask: 0,
        sa_flags: 0
      )

      _ = withUnsafePointer(to: &signalAction) { pointer in
        sigaction(signal.rawValue, pointer, nil)
      }
    }
  }

  /// Raise a signal
  static func raise(signal: Signal) {
    _ = Darwin.raise(signal.rawValue)
  }

  /// Ignore a signal
  static func ignore(signal: Signal) {
    _ = Darwin.signal(signal.rawValue, SIG_IGN)
  }

  /// Restore default signal handling
  static func restore(signal: Signal) {
    _ = Darwin.signal(signal.rawValue, SIG_DFL)
  }
}

extension Array where Element == SignalHandler.Signal {
  static let exitSignals = SignalHandler.Signal.exitSignals
}
// MARK: -


// MARK: - CLI utils
extension FileHandle: TextOutputStream {
  public func write(_ string: String) {
    write(string.data(using: .utf8)!)
  }
}

struct CLI {
  static var standardInput = FileHandle.standardInput
  static var standardOutput = FileHandle.standardOutput
  static var standardError = FileHandle.standardError

  static let arguments = Array(CommandLine.arguments.dropFirst(1))
}

extension CLI {
  private static let once = Once()

  /// Called when the process exits, either normally or forced (through signals)
  /// When this is set, it's up to you to exit the process
  static var onExit: (() -> Void)? {
    didSet {
      guard let exitHandler = onExit else {
        return
      }

      let handler = {
        once.run(exitHandler)
      }

      atexit_b {
        handler()
      }

      SignalHandler.handle(signals: .exitSignals) { _ in
        handler()
      }
    }
  }

  /// Called when the process is being forced (through signals) to exit
  /// When this is set, it's up to you to exit the process
  static var onForcedExit: ((SignalHandler.Signal) -> Void)? {
    didSet {
      guard let exitHandler = onForcedExit else {
        return
      }

      SignalHandler.handle(signals: .exitSignals, handler: exitHandler)
    }
  }
}

enum PrintOutputTarget {
  case standardOutput
  case standardError
}

/// Make `print()` accept an array of items
/// Since Swift doesn't support spreading...
private func print<Target>(
  _ items: [Any],
  separator: String = " ",
  terminator: String = "\n",
  to output: inout Target
) where Target: TextOutputStream {
  let item = items.map { "\($0)" }.joined(separator: separator)
  Swift.print(item, terminator: terminator, to: &output)
}

func print(
  _ items: Any...,
  separator: String = " ",
  terminator: String = "\n",
  to output: PrintOutputTarget = .standardOutput
) {
  switch output {
  case .standardOutput:
    print(items, separator: separator, terminator: terminator)
  case .standardError:
    print(items, separator: separator, terminator: terminator, to: &CLI.standardError)
  }
}
// MARK: -

func getCameraCaptureDeviceForElectronId(_ videoDeviceId: String) -> AVCaptureDevice? {
  let pulledVideoDeviceArr = AVCaptureDevice.devices(for: AVMediaType.video).filter { videoDeviceId.range(of: $0.uniqueID) != nil }
  var pulledVideoDeviceId: String?

  if pulledVideoDeviceArr.isEmpty == false {
    pulledVideoDeviceId = (pulledVideoDeviceArr.first?.uniqueID)!
  }

  return AVCaptureDevice(uniqueID: pulledVideoDeviceId!)
}

func getAudioDeviceForElectronId(_ audioDeviceId: String) -> AVCaptureDevice? {
  let pulledAudioDeviceArr = AVCaptureDevice.devices(for: AVMediaType.audio).filter { audioDeviceId.range(of: $0.uniqueID) != nil }
  var pulledAudioDeviceId: String?

  if pulledAudioDeviceArr.isEmpty == false {
    pulledAudioDeviceId = (pulledAudioDeviceArr.first?.uniqueID)!
  }

  return AVCaptureDevice(uniqueID: pulledAudioDeviceId!)
}

// MARK: - Misc
func synchronized<T>(lock: AnyObject, closure: () throws -> T) rethrows -> T {
    objc_sync_enter(lock)
    defer {
        objc_sync_exit(lock)
    }

    return try closure()
}

final class Once {
  private var hasRun = false

  /**
  Executes the given closure only once (thread-safe)

  ```
  final class Foo {
    private let once = Once()

    func bar() {
      once.run {
        print("Called only once")
      }
    }
  }

  let foo = Foo()
  foo.bar()
  foo.bar()
  ```
  */
  func run(_ closure: () -> Void) {
    synchronized(lock: self) {
      guard !hasRun else {
        return
      }

      hasRun = true
      closure()
    }
  }
}

extension Data {
  func jsonDecoded<T: Decodable>() throws -> T {
    return try JSONDecoder().decode(T.self, from: self)
  }
}

extension String {
  func jsonDecoded<T: Decodable>() throws -> T {
    return try data(using: .utf8)!.jsonDecoded()
  }
}

func toJson<T>(_ data: T) throws -> String {
  let json = try JSONSerialization.data(withJSONObject: data)
  return String(data: json, encoding: .utf8)!
}
