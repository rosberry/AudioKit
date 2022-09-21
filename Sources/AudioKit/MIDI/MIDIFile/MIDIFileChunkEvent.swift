// Copyright AudioKit. All Rights Reserved. Revision History at http://github.com/AudioKit/AudioKit/

import Foundation

/// MIDI File Chunk Event
public struct MIDIFileChunkEvent {
    public private(set) var data: [MIDIByte] // all data passed in
    public let timeFormat: MIDITimeFormat
    public let timeDivision: Int
    public let runningStatus: MIDIStatus?
    public let timeOffset: Int //accumulated time from previous events

    public init(data: [MIDIByte],
         timeFormat: MIDITimeFormat,
         timeDivision: Int,
         timeOffset: Int,
         runningStatus: MIDIStatus? = nil) {
        self.data = data
        self.timeFormat = timeFormat
        self.timeDivision = timeDivision
        self.timeOffset = timeOffset
        self.runningStatus = runningStatus
    }

    // computedData adds the status if running status was used
    public var computedData: [MIDIByte] {
        var outData = [MIDIByte]()
        if let addStatus = runningStatus {
            outData.append(addStatus.byte)
        }
        outData.append(contentsOf: rawEventData)
        return outData
    }

    // just the event data, no timing info
    public var rawEventData: [MIDIByte] {
        return Array(data.suffix(from: timeLength))
    }

    public var vlq: MIDIVariableLengthQuantity? {
        return MIDIVariableLengthQuantity(fromBytes: data)
    }

    public var timeLength: Int {
        return vlq?.length ?? 0
    }

    public var deltaTime: Int {
        return Int(vlq?.quantity ?? 0)
    }

    public var absoluteTime: Int {
        return deltaTime + timeOffset
    }

    public var position: Double {
        return Double(absoluteTime) / Double(timeDivision)
    }

    public var typeByte: MIDIByte? {
        if let runningStatus = self.runningStatus {
            return runningStatus.byte
        }
        if let index = typeIndex {
            return data[index]
        }
        return nil
    }

    public var typeIndex: Int? {
        if data.count > timeLength {
            if data[timeLength] == 0xFF,
                data.count > timeLength + 1 { //is Meta-Event
                return timeLength + 1
            } else if MIDIStatus(byte: data[timeLength]) != nil {
                return timeLength
            } else if MIDISystemCommand(rawValue: data[timeLength]) != nil {
                return timeLength
            }
        }
        return nil
    }

    public var length: Int {
        if let metaEvent = event as? MIDICustomMetaEvent {
            return metaEvent.length
        } else if let status = event as? MIDIStatus {
            return status.length
        } else if let command = event as? MIDISystemCommand {
            if let standardLength = command.length {
                return standardLength
            } else if command == .sysEx {
                return Int(data[timeLength + 1])
            } else {
                return data.count
            }
        } else if let index = typeIndex {
            return Int(data[index + 1])
        }
        return 0
    }

    public var event: MIDIMessage? {
        if let meta = MIDICustomMetaEvent(data: rawEventData) {
            return meta
        } else if let type = typeByte {
            if let status = MIDIStatus(byte: type) {
                return status
            } else if let command = MIDISystemCommand(rawValue: type) {
                return command
            }
        }
        return nil
    }

    public mutating func trim(length: Int) {
        data = Array(data.prefix(length))
    }
}
