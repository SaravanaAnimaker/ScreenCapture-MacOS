//
//  AMExtension.swift
//  MyNew
//
//  Created by AnimakerPC167 on 21/09/20.
//  Copyright © 2020 AnimakerPC167. All rights reserved.
//

import Foundation
import AVFoundation

extension AVCaptureDevice {
    convenience init?(localizedName: String, type: AVMediaType) {
        guard let uniqueID = (AVCaptureDevice.devices(for: type).first {
            $0.localizedName == localizedName
        })?.uniqueID else { return nil }
        self.init(uniqueID: uniqueID)
    }
}

extension AVCaptureScreenInput {
  var fps: CMTimeScale {
    get {
      return minFrameDuration.timescale
    }
    set {
      minFrameDuration = CMTime(value: 1, timescale: newValue)
    }
  }

  convenience init?(displayID: CGDirectDisplayID,
                    fps: Int,
                    cropRect: CGRect?,
                    showCursor: Bool,
                    highlightCursor: Bool) {
    self.init(displayID: displayID)
    self.fps = Int32(fps)
    cropRect.map { self.cropRect = $0 }
    self.capturesCursor = showCursor
    self.capturesMouseClicks = highlightCursor
  }
}

extension CMSampleBuffer {
  var duration: CMTime {
    return CMSampleBufferGetDuration(self)
  }

  var presentation: CMTime {
    return CMSampleBufferGetPresentationTimeStamp(self)
  }

  var ready: Bool {
    return CMSampleBufferDataIsReady(self)
  }

  func adjustTime(offset: CMTime) -> CMSampleBuffer {
    var count = CMItemCount()
    CMSampleBufferGetSampleTimingInfoArray(self, 0, nil, &count)

//    CMSampleBufferGetSampleTimingInfoArray(self, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)

    var pInfo = CMSampleTimingInfo()
    CMSampleBufferGetSampleTimingInfoArray(self, count, &pInfo, &count)

//    CMSampleBufferGetSampleTimingInfoArray(self, entryCount: count, arrayToFill: &pInfo, entriesNeededOut: &count)

    pInfo.decodeTimeStamp = CMTimeSubtract(pInfo.decodeTimeStamp, offset)
    pInfo.presentationTimeStamp = CMTimeSubtract(pInfo.presentationTimeStamp, offset)

    var sampleBufferOut: CMSampleBuffer?
    CMSampleBufferCreateCopyWithNewTiming(nil,
                                          self,
                                          count,
                                          &pInfo,
                                          &sampleBufferOut);

//    CMSampleBufferCreateCopyWithNewTiming(allocator: nil,
//                                          sampleBuffer: self,
//                                          sampleTimingEntryCount: count,
//                                          sampleTimingArray: &pInfo,
//                                          sampleBufferOut: &sampleBufferOut);

    return sampleBufferOut!
  }
    func createSilentAudio(startFrm: Int64) -> CMSampleBuffer? {
        let nFrames = CMSampleBufferGetNumSamples(self)
        let numChannels: UInt32 = 2
        let sampleRate: Float64 = 44100
        let bytesPerFrame = UInt32(2 * numChannels)
        let blockSize = nFrames*Int(bytesPerFrame)

        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            kCFAllocatorDefault,
            nil,
            blockSize,  // blockLength
            nil,        // blockAllocator
            nil,        // customBlockSource
            0,          // offsetToData
            blockSize,  // dataLength
            0,          // flags
            &block
        )
        assert(status == kCMBlockBufferNoErr)

        // we seem to get zeros from the above, but I can't find it documented. so... memset:
        status = CMBlockBufferFillDataBytes(0, block!, 0, blockSize)
        assert(status == kCMBlockBufferNoErr)

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: numChannels,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var formatDesc: CMAudioFormatDescription?
        status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, nil, 0, nil, nil, &formatDesc)
        assert(status == noErr)

        var sampleBuffer: CMSampleBuffer?

        // born ready
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            kCFAllocatorDefault,
            block,      // dataBuffer
            formatDesc!,
            nFrames,    // numSamples
            CMTimeMake(startFrm, Int32(sampleRate)),    // sbufPTS
            nil,        // packetDescriptions
            &sampleBuffer
        )
        assert(status == noErr)

        return sampleBuffer
    }

}
