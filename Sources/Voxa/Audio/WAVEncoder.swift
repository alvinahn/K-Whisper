import Foundation

/// Wraps Int16 PCM samples in a minimal WAV (RIFF) container.
enum WAVEncoder {
    static func wavData(samples: [Int16], sampleRate: Int = 16000, channels: Int = 1) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * MemoryLayout<Int16>.size
        let chunkSize = 36 + dataSize

        var data = Data()
        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(uint32LE(UInt32(chunkSize)))
        data.append("WAVE".data(using: .ascii)!)

        // fmt subchunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(uint32LE(16))                 // Subchunk1Size for PCM
        data.append(uint16LE(1))                  // AudioFormat: PCM
        data.append(uint16LE(UInt16(channels)))
        data.append(uint32LE(UInt32(sampleRate)))
        data.append(uint32LE(UInt32(byteRate)))
        data.append(uint16LE(UInt16(blockAlign)))
        data.append(uint16LE(UInt16(bitsPerSample)))

        // data subchunk
        data.append("data".data(using: .ascii)!)
        data.append(uint32LE(UInt32(dataSize)))
        samples.withUnsafeBufferPointer { ptr in
            data.append(UnsafeBufferPointer(start: ptr.baseAddress, count: ptr.count))
        }
        return data
    }

    private static func uint16LE(_ v: UInt16) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 2)
    }

    private static func uint32LE(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 4)
    }
}
