import Foundation
import Testing
@testable import StageFlow

@Suite("E09 MIDI Decoding, Mappings & Hot-Plug Tests")
struct MIDITests {
    
    // MARK: - E09.1 & E09.2: Decoder Corpus Tests
    
    @Test("Decoder accurately parses UMP MIDI 1.0 Control Change (E09.1 / E09.2)")
    func testDecodeControlChange() {
        // MT=2 (0x2), Group=0, Status=0xB0 (CC Ch 0), CC=7, Value=100
        let word: UInt32 = 0x20B00764
        let event = MIDIDecoder.decode(word: word)
        #expect(event == .controlChange(channel: 0, cc: 7, value: 100))
        
        // CC on Channel 15 (0xBF), CC=1, Value=127
        let wordCh15: UInt32 = 0x20BF017F
        let eventCh15 = MIDIDecoder.decode(word: wordCh15)
        #expect(eventCh15 == .controlChange(channel: 15, cc: 1, value: 127))
    }
    
    @Test("Decoder parses Note On with positive velocity (E09.1 / E09.2)")
    func testDecodeNoteOnPositiveVelocity() {
        // MT=2, Group=0, Status=0x90 (Note On Ch 0), Note=60, Velocity=80
        let word: UInt32 = 0x20903C50
        let event = MIDIDecoder.decode(word: word)
        #expect(event == .noteOn(channel: 0, note: 60, velocity: 80))
    }
    
    @Test("Decoder strictly converts Note On with velocity 0 to Note Off (E09.2 / E09.4)")
    func testDecodeNoteOnVelocityZeroAsNoteOff() {
        // MT=2, Group=0, Status=0x90 (Note On Ch 0), Note=60, Velocity=0 -> MUST be .noteOff
        let word: UInt32 = 0x20903C00
        let event = MIDIDecoder.decode(word: word)
        #expect(event == .noteOff(channel: 0, note: 60, velocity: 0))
    }
    
    @Test("Decoder accurately parses standard Note Off (E09.1 / E09.2)")
    func testDecodeStandardNoteOff() {
        // MT=2, Group=0, Status=0x80 (Note Off Ch 2), Note=64, Velocity=64
        let word: UInt32 = 0x20824040
        let event = MIDIDecoder.decode(word: word)
        #expect(event == .noteOff(channel: 2, note: 64, velocity: 64))
    }
    
    @Test("Decoder parses Program Change and Pitch Bend (E09.1 / E09.2)")
    func testDecodeProgramChangeAndPitchBend() {
        // Program Change: Status=0xC0, Program=5
        let pcWord: UInt32 = 0x20C00500
        let pcEvent = MIDIDecoder.decode(word: pcWord)
        #expect(pcEvent == .programChange(channel: 0, program: 5))
        
        // Pitch Bend: Status=0xE0, LSB=0x00, MSB=0x40 (center 8192)
        let pbWord: UInt32 = 0x20E00040
        let pbEvent = MIDIDecoder.decode(word: pbWord)
        #expect(pbEvent == .pitchBend(channel: 0, value: 8192))
    }
    
    @Test("Decoder processes multiple UMP words in a single packet (E09.1)")
    func testDecodeMultipleWordsInPacket() {
        // Packet contains 3 words:
        // 1. CC 7 (Ch 0) = 127
        // 2. CC 1 (Ch 0) = 64
        // 3. Note On 60 (Ch 0) = 100
        let words: [UInt32] = [
            0x20B0077F,
            0x20B00140,
            0x20903C64
        ]
        let events = MIDIDecoder.decode(words: words)
        #expect(events.count == 3)
        #expect(events[0] == .controlChange(channel: 0, cc: 7, value: 127))
        #expect(events[1] == .controlChange(channel: 0, cc: 1, value: 64))
        #expect(events[2] == .noteOn(channel: 0, note: 60, velocity: 100))
    }
    
    @Test("Decoder safely handles unknown and malformed UMP words without crashing (E09.2)")
    func testDecodeMalformedWords() {
        // MT=0 Utility Jitter Reduction (1 word)
        let noopWord: UInt32 = 0x00000000
        let noopEvent = MIDIDecoder.decode(word: noopWord)
        #expect(noopEvent == .other)
        
        // MT=4 MIDI 2.0 (2 words)
        let words: [UInt32] = [0x40903C00, 0x12345678, 0x20B0077F]
        let events = MIDIDecoder.decode(words: words)
        // First message consumes 2 words, second is MT=2 CC
        #expect(events.count == 2)
        #expect(events[0] == .other)
        #expect(events[1] == .controlChange(channel: 0, cc: 7, value: 127))
    }
    
    // MARK: - E09.4: Note & Pedal Semantics Tests
    
    @Test("Unmapped notes NEVER trigger Play/Pause or transport actions (E09.4 / SF-06)")
    @MainActor
    func testUnmappedNotesSafelyIgnored() {
        let store = MIDIMappingStore(storageKey: "test_unmapped_\(UUID())", userDefaults: UserDefaults())
        let midi = MIDIManager(mappingStore: store)
        
        var playPauseTriggerCount = 0
        midi.onPlayPauseTrigger = {
            playPauseTriggerCount += 1
        }
        
        // Send 10 different unmapped notes across various channels
        for note: UInt8 in [36, 48, 60, 62, 64, 65, 67, 69, 71, 72] {
            midi.processIncomingEvent(.noteOn(channel: 0, note: note, velocity: 100))
        }
        
        #expect(playPauseTriggerCount == 0, "Unmapped notes must NEVER trigger transport Play/Pause!")
    }
    
    @Test("Explicitly mapped note triggers assigned action (E09.4)")
    @MainActor
    func testMappedNoteTriggersAction() {
        let store = MIDIMappingStore(storageKey: "test_mapped_note_\(UUID())", userDefaults: UserDefaults())
        // Explicitly map Note 60 on Channel 0 to playPause
        let mapping = MIDIMapping(
            name: "Pedal Note",
            trigger: .note(channel: 0, note: 60),
            target: .playPause
        )
        store.addOrUpdateMapping(mapping)
        
        let midi = MIDIManager(mappingStore: store)
        var triggerCount = 0
        midi.onPlayPauseTrigger = {
            triggerCount += 1
        }
        
        // Note 60 triggers
        midi.processIncomingEvent(.noteOn(channel: 0, note: 60, velocity: 127))
        #expect(triggerCount == 1)
        
        // Note 60 Note Off does not re-trigger
        midi.processIncomingEvent(.noteOff(channel: 0, note: 60, velocity: 0))
        #expect(triggerCount == 1)
        
        // Note 61 (unmapped) does not trigger
        midi.processIncomingEvent(.noteOn(channel: 0, note: 61, velocity: 127))
        #expect(triggerCount == 1)
    }
    
    // MARK: - E09.5: Sustain Pedal Threshold & Transition Tests
    
    @Test("Sustain pedal triggers on rising edge threshold (value >= 64) and avoids repeat triggers (E09.5)")
    @MainActor
    func testSustainPedalThresholdAndEdgeTransition() {
        let store = MIDIMappingStore(storageKey: "test_sustain_\(UUID())", userDefaults: UserDefaults())
        let midi = MIDIManager(mappingStore: store)
        
        var triggerCount = 0
        midi.onPlayPauseTrigger = {
            triggerCount += 1
        }
        
        // 1. Initial values below threshold (0..63) -> NO trigger
        midi.processIncomingEvent(.controlChange(channel: 0, cc: 64, value: 0))
        midi.processIncomingEvent(.controlChange(channel: 0, cc: 64, value: 30))
        midi.processIncomingEvent(.controlChange(channel: 0, cc: 64, value: 63))
        #expect(triggerCount == 0)
        
        // 2. Crossing threshold (>= 64) -> EXACTLY 1 trigger
        midi.processIncomingEvent(.controlChange(channel: 0, cc: 64, value: 64))
        #expect(triggerCount == 1)
        
        // 3. Subsequent values while pressed (65, 80, 127) -> MUST NOT re-trigger!
        midi.processIncomingEvent(.controlChange(channel: 0, cc: 64, value: 65))
        midi.processIncomingEvent(.controlChange(channel: 0, cc: 64, value: 100))
        midi.processIncomingEvent(.controlChange(channel: 0, cc: 64, value: 127))
        #expect(triggerCount == 1, "Repeated sustain values >= 64 must not re-trigger!")
        
        // 4. Release pedal (< 64) -> resets state, does not trigger
        midi.processIncomingEvent(.controlChange(channel: 0, cc: 64, value: 0))
        #expect(triggerCount == 1)
        
        // 5. Press pedal again -> triggers second time
        midi.processIncomingEvent(.controlChange(channel: 0, cc: 64, value: 127))
        #expect(triggerCount == 2)
    }
    
    // MARK: - E09.6: Learning Flow & Persistence Tests
    
    @Test("MIDI Learning flow registers, persists and restores mappings across restarts (E09.6)")
    @MainActor
    func testLearningAndPersistence() {
        let key = "test_learning_store_\(UUID())"
        let defaults = UserDefaults()
        let store = MIDIMappingStore(storageKey: key, userDefaults: defaults)
        let midi = MIDIManager(mappingStore: store)
        
        var controlledTarget: String? = nil
        var controlledValue: Float? = nil
        midi.onVolumeChange = { target, value in
            controlledTarget = target
            controlledValue = value
        }
        
        // 1. Enter learning mode for Backing Volume
        midi.startLearning(target: .backingVolume)
        #expect(midi.isLearning == true)
        #expect(midi.learningTarget == .backingVolume)
        
        // 2. Incoming CC #25 learns the mapping
        midi.processIncomingEvent(.controlChange(channel: 2, cc: 25, value: 100))
        
        // 3. Verify learning ended and mapping was stored
        #expect(midi.isLearning == false)
        #expect(midi.learningTarget == nil)
        #expect(midi.lastLearnedMapping?.target == .backingVolume)
        #expect(midi.lastLearnedMapping?.trigger == .controlChange(channel: 2, cc: 25))
        #expect(controlledTarget == "backing")
        #expect(abs((controlledValue ?? 0) - (100.0 / 127.0)) < 0.001)
        
        // 4. Test Persistence: instantiate fresh store with same key (simulating app restart)
        let restoredStore = MIDIMappingStore(storageKey: key, userDefaults: defaults)
        #expect(restoredStore.userMappings.count == 1)
        #expect(restoredStore.userMappings.first?.target == .backingVolume)
        #expect(restoredStore.userMappings.first?.trigger == .controlChange(channel: 2, cc: 25))
        
        // 5. Subsequent events continue to control the learned target
        let newMidi = MIDIManager(mappingStore: restoredStore)
        var newTarget: String? = nil
        var newValue: Float? = nil
        newMidi.onVolumeChange = { target, value in
            newTarget = target
            newValue = value
        }
        newMidi.processIncomingEvent(.controlChange(channel: 2, cc: 25, value: 50))
        #expect(newTarget == "backing")
        #expect(abs((newValue ?? 0) - (50.0 / 127.0)) < 0.001)
    }
    
    // MARK: - E09.7: Precedence Tests
    
    @Test("Custom user mapping strictly overrides factory defaults (E09.7)")
    @MainActor
    func testUserMappingOverridesDefaults() {
        let store = MIDIMappingStore(storageKey: "test_precedence_\(UUID())", userDefaults: UserDefaults())
        // Default: CC 7 -> masterFOH
        let defaultTarget = store.lookup(event: .controlChange(channel: 0, cc: 7, value: 100))
        #expect(defaultTarget == .masterFOH)
        
        // User maps CC 7 on Channel 0 to Mic 1 Volume
        store.addOrUpdateMapping(MIDIMapping(
            name: "Mic 1 Fader Override",
            trigger: .controlChange(channel: 0, cc: 7),
            target: .mic1Volume
        ))
        
        // Now CC 7 on Ch 0 must resolve to mic1Volume!
        let overriddenTarget = store.lookup(event: .controlChange(channel: 0, cc: 7, value: 100))
        #expect(overriddenTarget == .mic1Volume)
        
        // CC 7 on other channel (Ch 1) falls back to default masterFOH
        let ch1Target = store.lookup(event: .controlChange(channel: 1, cc: 7, value: 100))
        #expect(ch1Target == .masterFOH)
    }
    
    // MARK: - E09.8: Next & Previous Track Actions Tests
    
    @Test("Next and Previous track actions trigger respective callbacks and update AppState (E09.8)")
    @MainActor
    func testNextAndPreviousTrackActions() {
        let store = MIDIMappingStore(storageKey: "test_nav_\(UUID())", userDefaults: UserDefaults())
        store.addOrUpdateMapping(MIDIMapping(
            name: "Next Track Button",
            trigger: .note(channel: 0, note: 62),
            target: .nextTrack
        ))
        store.addOrUpdateMapping(MIDIMapping(
            name: "Prev Track Button",
            trigger: .note(channel: 0, note: 60),
            target: .previousTrack
        ))
        
        let midi = MIDIManager(mappingStore: store)
        let appState = AppState()
        
        // Add 3 songs to playlist
        let song1 = SongTrack(title: "Song 1", duration: 180)
        let song2 = SongTrack(title: "Song 2", duration: 200)
        let song3 = SongTrack(title: "Song 3", duration: 220)
        appState.playlist = [song1, song2, song3]
        appState.selectTrack(song1)
        
        var nextCount = 0
        var prevCount = 0
        midi.onNextTrackTrigger = {
            nextCount += 1
            appState.selectNextTrack()
        }
        midi.onPreviousTrackTrigger = {
            prevCount += 1
            appState.selectPreviousTrack()
        }
        
        // Trigger Next Track
        midi.processIncomingEvent(.noteOn(channel: 0, note: 62, velocity: 127))
        #expect(nextCount == 1)
        #expect(appState.selectedTrack?.title == "Song 2")
        
        // Trigger Next Track again
        midi.processIncomingEvent(.noteOn(channel: 0, note: 62, velocity: 127))
        #expect(nextCount == 2)
        #expect(appState.selectedTrack?.title == "Song 3")
        
        // Trigger Previous Track
        midi.processIncomingEvent(.noteOn(channel: 0, note: 60, velocity: 127))
        #expect(prevCount == 1)
        #expect(appState.selectedTrack?.title == "Song 2")
    }
    
    // MARK: - E09.9: Hot-Plug Simulation Tests
    
    @Test("Hot-plug simulation updates connected devices and names safely (E09.9)")
    @MainActor
    func testHotPlugUpdatesDeviceList() {
        let midi = MIDIManager()
        
        // Initial state
        midi.simulateHotPlug(deviceNames: [])
        #expect(midi.connectedDeviceName == "No MIDI Devices")
        #expect(midi.connectedDevices.isEmpty)
        
        // Device plugged in
        midi.simulateHotPlug(deviceNames: ["Arturia KeyLab 61"])
        #expect(midi.connectedDeviceName == "Arturia KeyLab 61")
        #expect(midi.connectedDevices == ["Arturia KeyLab 61"])
        
        // Second device plugged in
        midi.simulateHotPlug(deviceNames: ["Arturia KeyLab 61", "Behringer FCB1010"])
        #expect(midi.connectedDeviceName == "Arturia KeyLab 61, Behringer FCB1010")
        #expect(midi.connectedDevices.count == 2)
        
        // 20 Hot-plug reconnect cycles
        for cycle in 1...20 {
            midi.simulateHotPlug(deviceNames: ["Controller \(cycle)"])
            #expect(midi.connectedDevices == ["Controller \(cycle)"])
        }
    }
    
    // MARK: - E09.11: CC Burst & Coalescing Tests
    
    @Test("Rapid burst of 1,000 CC events processes without UI stall and settles on exact final value (E09.11)")
    @MainActor
    func testRapidCCBurstCoalescing() async throws {
        let store = MIDIMappingStore(storageKey: "test_burst_\(UUID())", userDefaults: UserDefaults())
        let midi = MIDIManager(mappingStore: store)
        
        var audioUpdateCount = 0
        var lastAudioValue: Float = 0
        midi.onVolumeChange = { target, value in
            if target == "masterFOH" {
                audioUpdateCount += 1
                lastAudioValue = value
            }
        }
        
        // Fire burst of 1,000 CC events in tight loop (simulating aggressive fader sweep)
        for i in 1...1000 {
            let val = UInt8(i % 128)
            midi.processIncomingEvent(.controlChange(channel: 0, cc: 7, value: val))
        }
        
        // Audio updates must receive every single event without loss
        #expect(audioUpdateCount == 1000)
        #expect(abs(lastAudioValue - (Float(1000 % 128) / 127.0)) < 0.001)
        
        // Flush any pending coalesced UI updates
        midi.flushUIUpdates()
        
        // UI lastReceivedCC must reflect the final value of the burst
        #expect(midi.lastReceivedCC?.cc == 7)
        #expect(midi.lastReceivedCC?.value == UInt8(1000 % 128))
    }
}
