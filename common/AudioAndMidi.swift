//
//  AudioAndMidi.swift
//  swiftui-test
//
//  Created by utku on 12/12/2022.
//

import Foundation
import AVFoundation

extension UInt8 {
    func hex() -> String {
        return String(format:"%02X", self)
    }
}

public struct MIDIHeader {
    /// The format of the MIDI file (0, 1, or 2)
    var format: UInt16 = 0
    var numTracks: UInt16 = 0
    
    /// The time division of the MIDI file (ticks per quart)
    var division: UInt16 = 0
    
    init() {}
    
    init(format: UInt16, numTracks: UInt16, division: UInt16) {
        self.format = format
        self.numTracks = numTracks
        self.division = division
    }
    
    init(fromBytes: [UInt8], index: inout Int) {
        // The first four bytes contain the MIDI header chunk identifier ("MThd")
        index += 4
        
        // The next four bytes contain the length of the MIDI header chunk (always 6)
        index += 4
        
        // The next two bytes contain the format of the MIDI file (0, 1, or 2)
        self.format = UInt16(fromBytes[index]) << 8 | UInt16(fromBytes[index + 1])
        index += 2
        
        // The next two bytes contain the number of tracks in the MIDI file
        self.numTracks = UInt16(fromBytes[index]) << 8 | UInt16(fromBytes[index + 1])
        index += 2

        // The next two bytes contain the division of the MIDI file (the timing resolution)
        self.division = UInt16(fromBytes[index]) << 8 | UInt16(fromBytes[index + 1])
        index += 2
    }
}


public class MIDIEvent {
    enum Status: UInt8 {
        case noteOn = 0x80
        case noteOff = 0x90
        case polyphonicAftertouch = 0xA0
        case controlChange = 0xB0
        case programChange = 0xC0
        case aftertouch = 0xD0
        case pitchBend = 0xE0
        //case meta = 0xF0
        case unsupported = 0
    }
    enum MetaStatus: UInt8 {
        case trackName = 0x03
        case marker = 0x06
        case cuePoint = 0x07
        case tempo = 0x51
        case smpteOffset = 0x54
        case timeSignature = 0x58
        case keySignature = 0x59
        case unsupported = 0
    }
    enum EventType {
        case midi
        case meta
    }
    
    var timeStamp = 0.0
    var tickDelta = 0.0
    var absoluteTicks = 0.0
    
    var channel: UInt8 = 0
    var noteNumber: UInt8 = 0
    var value = 0
    
    var type = EventType.midi
    var status = Status.unsupported
    var metaStatus = MetaStatus.unsupported
    var metaData = [UInt8]()
    
    static func loadVariableLength(fromBytes: [UInt8], index: inout Int) -> UInt32 {
        var value: UInt32 = 0
        var endOfMessage = false

        // Loop until we reach the end of the message
        while !endOfMessage {
            let byte = fromBytes[index]
            index += 1
            
            value = (value << 7) + UInt32(byte & 0x7F)
            
            // If the high bit of the byte is not set, we have reached the end of the message
            if byte & 0x80 == 0 {
                endOfMessage = true
            }
        }
        
        return value
    }
    
    static func load(fromBytes: [UInt8], index: inout Int, lastEvent: MIDIEvent?) -> MIDIEvent {
        let event = MIDIEvent()
        event.tickDelta = Double(loadVariableLength(fromBytes: fromBytes, index: &index))
        event.absoluteTicks = (lastEvent?.absoluteTicks ?? 0) + event.tickDelta
        
        let statusByte = fromBytes[index]
        index += 1
        
        if (statusByte & 0xF0) == 0xF0 {
            // system events
            if (statusByte == 0xF8) || (statusByte == 0xFA) || (statusByte == 0xFB) ||
                (statusByte == 0xFC)  || (statusByte == 0xFD) || (statusByte == 0xFE) {
                // these messages are status only, don't need to do anything.
            } else if (statusByte == 0xF1) || (statusByte == 0xF2) {
                // these messages contain a single byte.
                index += 1
            } else if (statusByte == 0xF2) {
                // this message contains 2 bytes.
                index += 2
            } else if (statusByte == 0xF0) {
                // this message's length is variable, it runs until a 0xF7 is encountered.
                while fromBytes[index] != 0xF7 {
                    index += 1
                }
                index += 1
            } else if statusByte == 0xFF {
                event.type = .meta
                event.metaStatus = MetaStatus(rawValue: fromBytes[index]) ?? .unsupported
                index += 1
                let statusLength = fromBytes[index]
                index += 1
                event.metaData.append(contentsOf: fromBytes[index ..< (index+Int(statusLength))])
                index += Int(statusLength)
            }
        } else {
            // midi event.
            event.type = .midi
            event.channel = statusByte & 0x0F
            event.status = Status(rawValue: statusByte & 0xF0) ?? .unsupported
            if event.status == .unsupported && lastEvent != nil {
                // if this is a running status message, take the values from the last event,
                //  and then back up the byte index by one.
                event.status = lastEvent!.status
                event.channel = lastEvent!.channel
                index -= 1
            }
            switch event.status {
            case .noteOn:
                fallthrough
            case .noteOff:
                fallthrough
            case .polyphonicAftertouch:
                fallthrough
            case .controlChange:
                event.noteNumber = fromBytes[index]
                event.value = Int(fromBytes[index+1])
                index += 2
            case .programChange:
                fallthrough
            case .aftertouch:
                index += 1
            case .pitchBend:
                event.value = Int(fromBytes[index] << 7) | Int(fromBytes[index + 1])
                index += 2
            default:
                break
            }
        }
        
        return event
    }
}

public struct MIDIFile {
    var header = MIDIHeader()
    var tracks: [[MIDIEvent]] = []
    var namedTracks: [String: [MIDIEvent]] = [:]
    var tempoTrack: [MIDIEvent]?
    
    var tempoMap: [(Double, Double)] = []
    
    var bpm = 120.0
    var usPerQuart = 500_000.0
    
    func peekForward(track: String, startTime: Double, endTime: Double) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        if let track = namedTracks[track] {
            for event in track {
                if event.timeStamp > endTime {
                    break
                }
                if event.timeStamp > startTime {
                    events.append(event)
                }
            }
        }
        return events
    }
    
    func peekForward(track: String, startBeat: Double, endBeat: Double) -> [MIDIEvent] {
        return peekForward(track: track, startTime: startBeat, endTime: endBeat)
    }
    
    func eventsOfMarker(track: String, marker: String) -> [MIDIEvent] {
        let events: [MIDIEvent] = []
        
        return events
    }
    
    init(path: String) {
        if let midiFile = FileManager.default.contents(atPath: path) {
            let midiBytes = [UInt8](midiFile)
            var index = 0
            header = .init(fromBytes: midiBytes, index: &index)
            for trackNo in 0 ..< header.numTracks {
                let trackHeaderPattern: [UInt8] = [0x4D, 0x54, 0x72, 0x6B] // MTrk
                let trackBytes = Array(midiBytes[index...])
                var trackByteIndex = 0
                if !trackBytes.starts(with: trackHeaderPattern) {
                    fatalError("Midi parse error: Track header does not match expectation.")
                }
                trackByteIndex += 4
                let trackLength: UInt32 =
                    UInt32(trackBytes[trackByteIndex + 0]) << 24 |
                    UInt32(trackBytes[trackByteIndex + 1]) << 16 |
                    UInt32(trackBytes[trackByteIndex + 2]) << 8 |
                    UInt32(trackBytes[trackByteIndex + 3])
                trackByteIndex += 4
                index += 8 + Int(trackLength)

                var lastEvent: MIDIEvent?
                var trackEvents = [MIDIEvent]()
                while (trackByteIndex) < (trackLength + 8) {
                    lastEvent = MIDIEvent.load(fromBytes: trackBytes, index: &trackByteIndex, lastEvent: lastEvent)
                    trackEvents.append(lastEvent!)
                }
                if (trackNo == 0) && (header.numTracks > 1) {
                    // first track of a multitrack file is the tempo track.
                    tempoTrack = trackEvents
                } else {
                    tracks.append(trackEvents)
                }
            }
            
            // after capturing all tracks, generate the tempo change map.
            var runningBPM = 120.0
            var runningUsPerQuart = 500_000.0
            var runningUsPerTick = runningUsPerQuart / Double(header.division)
            if tempoTrack != nil {
                var runningTime = 0.0
                var runningTicks = 0.0
                for event in tempoTrack! {
                    runningTicks += event.tickDelta
                    runningTime += (runningUsPerTick * event.tickDelta) * 0.000_001
                    if event.metaStatus == .tempo {
                        print("Got a set tempo event: \(event)!")
                        let microsecondsPerSecond: Double = 60_000_000
                        runningUsPerQuart = Double((Int(event.metaData[0]) << 16) | (Int(event.metaData[1]) << 8) | (Int(event.metaData[2])))
                        runningUsPerTick = runningUsPerQuart / Double(header.division)
                        runningBPM = microsecondsPerSecond / runningUsPerQuart
                    }
                }


            } else {
                
            }
            
            bpm = runningBPM
            usPerQuart = runningUsPerQuart
            
            // place timestamps into events, and get track names out of them if available.
            for track in tracks {
                var runningTime = 0.0
                var runningTicks = 0.0
                var trackName: String?
                for event in track {
                    if event.metaStatus == .trackName {
                        trackName = String(bytes: event.metaData, encoding: .ascii)
                    }
                    runningTicks += event.tickDelta
                    runningTime += (runningUsPerTick * event.tickDelta) * 0.000_001
                    event.timeStamp = runningTime
                }
                if trackName != nil {
                    namedTracks[trackName!] = track
                }
            }
        }
    }
}


class MidiEventQueue {
    var queue: [MIDIEvent]
    
    func popLast() -> MIDIEvent? {
        return queue.popLast()
    }
    
    func merge(queue: [MIDIEvent]) {
        self.queue.append(contentsOf: queue)
        self.queue.sort { (p1: MIDIEvent, p2: MIDIEvent) in
            return p1.timeStamp >= p2.timeStamp
        }
    }
    
    init(queue: [MIDIEvent]) {
        self.queue = queue
    }
}

public class MidiEventProvider {
    var filename = ""
    var midiFile: MIDIFile?

    var currentTime: Double = 0.0
    var currentTimeInBeats: Double = 0.0
    var bpm = 120.0
    
    init(url: URL) {
        self.filename = url.lastPathComponent
        midiFile = .init(path: url.relativePath)
        if midiFile == nil {
            return
        }
        
        for (name, track) in midiFile!.namedTracks {
            trackBasedTargets[name] = []
            trackQueues[name] = MidiEventQueue(queue: track.reversed())
        }
        
    }
    
    func dispatchEvent(event: MIDIEvent, trackName: String) {
        guard let targets = trackBasedTargets[trackName]
        else {
            return
        }
        switch event.status {
        case .noteOff:
            for target in targets {
                target.onNoteOff(noteNumber: Int(event.noteNumber), time: currentTime)
            }
        case .noteOn:
            for target in targets {
                target.onNoteOn(noteNumber: Int(event.noteNumber), time: currentTime)
            }
        case .controlChange:
            for target in targets {
                target.onCC(ccIndex: Int(event.noteNumber), ccValue: Float(event.value) / 127.0)
            }
        case .pitchBend:
            for target in targets {
                target.onPitchWheel(value: Float(event.value) / Float(UInt16.max))
            }
        default:
            break
        }
    }
    
    func processEvent(event: MIDIEvent) {
        switch event.metaStatus {
        case .trackName:
            break
        case .tempo:
            print("Got a set tempo event: \(event)!")
            let microsecondsPerSecond: Double = 60_000_000
            let value = Double((Int(event.metaData[0]) << 16) | (Int(event.metaData[1]) << 8) | (Int(event.metaData[2])))
            bpm = microsecondsPerSecond / value
        case .timeSignature:
            break
        case .keySignature:
            break
        default:
            break
        }
    }
    
    func cumulativeTick(absoluteTime: Double) {
        currentTime = absoluteTime
        
        for (name, track) in trackQueues {
            var lastEvent = track.queue.last
            while (lastEvent?.timeStamp ?? 9999999.0) < currentTime {
                dispatchEvent(event: lastEvent!, trackName: name)
                lastEvent = track.queue.popLast()
                lastEvent = track.queue.last
            }
        }
        
    }
    
    func attachHandler(handler: any MusicEvents) {
        if let _ = trackBasedTargets[handler.targetTrack] {
            trackBasedTargets[handler.targetTrack]!.append(handler)
        }
    }
    
    public func peekForward(track: String, startTime: Double = 0.0, endTime: Double = 999999999.0) -> [MIDIEvent] {
        if let file = midiFile {
            return file.peekForward(track: track, startTime: startTime, endTime: endTime)
        }
        return []
    }
    
    private var usPerBeat = 500_000
    private var running = false
    private var trackQueues: [String: MidiEventQueue] = [:]
    private var allTrackEvents: [String: MidiEventQueue] = [:]
    private var metaQueue: MidiEventQueue?
    private var trackBasedTargets: [String: [any MusicEvents]] = [:]
    private var allTrackTargets: [any MusicEvents] = []
    
}


public class BackgroundMusicPlayer {
    private var player: AVPlayer!
    private var observer: NSKeyValueObservation?
    let timeInterval = CMTimeMakeWithSeconds(0.001, preferredTimescale: Int32(NSEC_PER_SEC)); // 1 second
    var readyToPlay = false
    var currentTime = 0.0

    
    init(songName: String) {
        player = .init(url: Bundle.main.url(forResource: songName, withExtension: ".mp3", subdirectory: "music")!)
        observer = player.observe(\.status, changeHandler: { player, status in
            if player.status == .readyToPlay {
                self.readyToPlay = true
                player.preroll(atRate: 10.0)
            }
        })
        
        player.addPeriodicTimeObserver(forInterval: timeInterval, queue: nil) { currentTime in
            self.currentTime = currentTime.seconds
        }
    }
    
    func startBlocking() {
//        while !readyToPlay {
//
//        }
        player.volume = 0.3
        player.play()
    }
    
    func pause() {
        player.pause()
    }
    
    func resume() {
        player.playImmediately(atRate: 1.0)
    }
    
    func reset() {
        player = AVPlayer()
    }
    
    func destroy() {
        
    }
    
}
