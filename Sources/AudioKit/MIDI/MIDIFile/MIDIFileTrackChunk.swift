// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import Foundation

/// MIDI File Track Chunk
public struct MIDIFileTrackChunk: MIDIFileChunk {
    /// Raw data as array of MIDI Bytes
    public private(set) var rawData: [MIDIByte]
    private var processedData: [MIDIByte] = []

    let timeFormat: MIDITimeFormat
    let timeDivision: Int

    /// Initialize from a raw data array
    /// - Parameter data: Array of MIDI Bytes
    public init?(data: [MIDIByte]) {
        guard
            data.count > 8
            else {
                return nil
        }
        let lengthBytes = Array(data[4..<8])
        let length = Int(MIDIHelper.convertTo32Bit(msb: lengthBytes[0],
                                                   data1: lengthBytes[1],
                                                   data2: lengthBytes[2],
                                                   lsb: lengthBytes[3]))
        timeFormat = .ticksPerBeat
        timeDivision = 480 //arbitrary value
        rawData = Array(data.prefix(upTo: length + 8)) //the message + 4 byte header type, + 4 byte length
        if isNotValid || !isTrack {
            return nil
        }
    }

    init?(chunk: MIDIFileChunk, timeFormat: MIDITimeFormat, timeDivision: Int) {
        guard chunk.type == .track else {
            return nil
        }
        rawData = chunk.rawData
        self.timeFormat = timeFormat
        self.timeDivision = timeDivision
    }

    /// Array of chunk events
    public var chunkEvents: [MIDIFileChunkEvent] {
        var events = [MIDIFileChunkEvent]()
        var accumulatedDeltaTime = 0
        var currentTimeVLQ: MIDIVariableLengthQuantity?
        var runningStatus: MIDIByte?
        var processedBytes = 0
        while processedBytes < data.count {
            let subData = Array(data.suffix(from: processedBytes))
            let byte = data[processedBytes]
            if currentTimeVLQ == nil, let vlqTime = MIDIVariableLengthQuantity(fromBytes: subData) {
                currentTimeVLQ = vlqTime
                processedBytes += vlqTime.length
            } else if let vlqTime = currentTimeVLQ {
                var event: MIDIFileChunkEvent?
                if let metaEvent = MIDICustomMetaEvent(data: subData) {
                    let metaData = metaEvent.data
                    event = MIDIFileChunkEvent(data: vlqTime.data + metaData,
                                                 timeFormat: timeFormat,
                                                 timeDivision: timeDivision,
                                                 timeOffset: accumulatedDeltaTime)
                    processedBytes += metaEvent.data.count
                    runningStatus = nil
                } else if let sysExEvent = MIDISysExMessage(bytes: subData) {
                    let sysExData = sysExEvent.data
                    event = MIDIFileChunkEvent(data: vlqTime.data + sysExData,
                                               timeFormat: timeFormat,
                                               timeDivision: timeDivision,
                                               timeOffset: accumulatedDeltaTime)
                    if let endIndex = sysExEvent.data.lastIndex(of: 0xF7) {
                        processedBytes += endIndex + 1
                    }
                    else {
                        processedBytes += sysExEvent.data.count
                    }

                    runningStatus = nil
                } else if let status = MIDIStatus(byte: byte) {
                    let messageLength = status.length
                    let chunkData = Array(subData.prefix(messageLength))
                    event = MIDIFileChunkEvent(data: vlqTime.data + chunkData,
                                                 timeFormat: timeFormat,
                                                 timeDivision: timeDivision,
                                                 timeOffset: accumulatedDeltaTime)
                    runningStatus = status.byte
                    processedBytes += messageLength
                } else if let activeRunningStatus = runningStatus,
                    let status = MIDIStatus(byte: activeRunningStatus) {
                    let messageLength = status.length - 1 // drop one since running status is used
                    let chunkData = Array(subData.prefix(messageLength))
                    event = MIDIFileChunkEvent(data: vlqTime.data + chunkData,
                                                 timeFormat: timeFormat,
                                                 timeDivision: timeDivision,
                                                 timeOffset: accumulatedDeltaTime,
                                                 runningStatus: status)
                    processedBytes += messageLength
                } else {
                    return []
                }
                guard let currentEvent = event else { break }
                events.append(currentEvent)
                accumulatedDeltaTime += Int(vlqTime.quantity)
                currentTimeVLQ = nil
            }
        }
        return events
    }

    public func recompose() -> [MIDIByte] {
        var processedData: [MIDIByte] = Array(rawData.prefix(8))
        var accumulatedDeltaTime = 0
        var currentTimeVLQ: MIDIVariableLengthQuantity?
        var runningStatus: MIDIByte?
        var processedBytes = 0
        var shouldSkipNextVLQ: Bool = false
        while processedBytes < data.count {
            let subData = Array(data.suffix(from: processedBytes))
            let byte = data[processedBytes]
            if currentTimeVLQ == nil, let vlqTime = MIDIVariableLengthQuantity(fromBytes: subData) {
                currentTimeVLQ = vlqTime
                processedBytes += vlqTime.length
                if shouldSkipNextVLQ == false {
                    processedData.append(contentsOf: vlqTime.data)
                }
                shouldSkipNextVLQ = false
            } else if let vlqTime = currentTimeVLQ {
                var event: MIDIFileChunkEvent?
                if let metaEvent = MIDICustomMetaEvent(data: subData) {
                    let metaData = metaEvent.data
                    event = MIDIFileChunkEvent(data: vlqTime.data + metaData,
                                                 timeFormat: timeFormat,
                                                 timeDivision: timeDivision,
                                                 timeOffset: accumulatedDeltaTime)
                    processedBytes += metaEvent.data.count
                    runningStatus = nil
                } else if let sysExEvent = MIDISysExMessage(bytes: subData) {
                    let sysExData = sysExEvent.data
                    var sysexChunk = MIDIFileChunkEvent(data: vlqTime.data + sysExData,
                                                        timeFormat: timeFormat,
                                                        timeDivision: timeDivision,
                                                        timeOffset: accumulatedDeltaTime)
                    if let endIndex = sysExEvent.data.lastIndex(of: 0xF7) {
                        processedBytes += endIndex + 1
                        sysexChunk.trim(length: sysExEvent.data.count)
                        shouldSkipNextVLQ = true
                    }
                    else {
                        processedBytes += sysExEvent.data.count
                    }

                    runningStatus = nil
                    //event = sysexChunk

                } else if let status = MIDIStatus(byte: byte) {
                    let messageLength = status.length
                    let chunkData = Array(subData.prefix(messageLength))
                    event = MIDIFileChunkEvent(data: vlqTime.data + chunkData,
                                                 timeFormat: timeFormat,
                                                 timeDivision: timeDivision,
                                                 timeOffset: accumulatedDeltaTime)
                    runningStatus = status.byte
                    processedBytes += messageLength
                } else if let activeRunningStatus = runningStatus,
                    let status = MIDIStatus(byte: activeRunningStatus) {
                    let messageLength = status.length - 1 // drop one since running status is used
                    let chunkData = Array(subData.prefix(messageLength))
                    event = MIDIFileChunkEvent(data: vlqTime.data + chunkData,
                                                 timeFormat: timeFormat,
                                                 timeDivision: timeDivision,
                                                 timeOffset: accumulatedDeltaTime,
                                                 runningStatus: status)
                    processedBytes += messageLength
                } else {
                    return processedData
                }

                if let currentEvent = event {
                    processedData.append(contentsOf: currentEvent.rawEventData)
                }

                accumulatedDeltaTime += Int(vlqTime.quantity)
                currentTimeVLQ = nil
            }
        }

        return processedData
    }
}
