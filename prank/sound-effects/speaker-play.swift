// Plays a sound file on the Mac's built-in speakers, whatever the default output
// is, with the speakers' volume set for the duration and put back afterwards.
//
//   speaker-play FILE VOLUME GAIN
//
// VOLUME is the speakers' volume in percent, GAIN the playback gain (1 is
// normal). Exits 2 when the Mac has no built-in speakers, or they are not the
// active source (headphones in the jack), before playing anything.

import AVFoundation
import AudioToolbox
import CoreAudio

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
	AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

let internalSpeaker: UInt32 = 0x6973_706B // 'ispk'

func builtInSpeakers() -> AudioDeviceID? {
	let system = AudioObjectID(kAudioObjectSystemObject)
	var addr = address(kAudioHardwarePropertyDevices)
	var size = UInt32(0)
	guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return nil }
	var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
	guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &devices) == noErr else { return nil }

	return devices.first { device in
		var transportAddr = address(kAudioDevicePropertyTransportType)
		var transport = UInt32(0)
		var transportSize = UInt32(MemoryLayout<UInt32>.size)
		// The headphone jack is a built-in device too; only the speakers report 'ispk'.
		var sourceAddr = address(kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput)
		var source = UInt32(0)
		var sourceSize = UInt32(MemoryLayout<UInt32>.size)
		return AudioObjectGetPropertyData(device, &transportAddr, 0, nil, &transportSize, &transport) == noErr
			&& transport == kAudioDeviceTransportTypeBuiltIn
			&& AudioObjectGetPropertyData(device, &sourceAddr, 0, nil, &sourceSize, &source) == noErr
			&& source == internalSpeaker
	}
}

// The volume the menu-bar slider shows, which is what "80%" means to a person.
var volumeAddr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
var muteAddr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)

func volume(of device: AudioDeviceID) -> Float32? {
	var value = Float32(0)
	var size = UInt32(MemoryLayout<Float32>.size)
	return AudioObjectGetPropertyData(device, &volumeAddr, 0, nil, &size, &value) == noErr ? value : nil
}

func setVolume(_ value: Float32, of device: AudioDeviceID) {
	var value = value
	AudioObjectSetPropertyData(device, &volumeAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
}

func muted(_ device: AudioDeviceID) -> UInt32? {
	var value = UInt32(0)
	var size = UInt32(MemoryLayout<UInt32>.size)
	return AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &size, &value) == noErr ? value : nil
}

func setMuted(_ value: UInt32, _ device: AudioDeviceID) {
	var value = value
	AudioObjectSetPropertyData(device, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
}

func fail(_ message: String, _ code: Int32 = 1) -> Never {
	FileHandle.standardError.write("speaker-play: \(message)\n".data(using: .utf8)!)
	exit(code)
}

let args = CommandLine.arguments
guard args.count == 4, let percent = Float32(args[2]), let gain = Float32(args[3]), gain > 0 else {
	fail("usage: speaker-play FILE VOLUME GAIN", 64)
}
guard let speakers = builtInSpeakers() else { fail("no built-in speakers", 2) }

let file: AVAudioFile
do { file = try AVAudioFile(forReading: URL(fileURLWithPath: args[1])) } catch { fail("cannot read \(args[1]): \(error)") }

let engine = AVAudioEngine()
var device = speakers
guard let outputUnit = engine.outputNode.audioUnit,
	AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
	                     &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr
else { fail("cannot route playback to the built-in speakers") }

// A player node tops out at unity volume; the EQ's global gain takes it louder.
let player = AVAudioPlayerNode()
let booster = AVAudioUnitEQ(numberOfBands: 0)
booster.globalGain = max(-96, min(24, 20 * log10(gain)))
engine.attach(player)
engine.attach(booster)
engine.connect(player, to: booster, format: file.processingFormat)
engine.connect(booster, to: engine.mainMixerNode, format: file.processingFormat)

let savedVolume = volume(of: speakers)
let savedMute = muted(speakers)
setVolume(max(0, min(1, percent / 100)), of: speakers)
setMuted(0, speakers)

var startError: Error?
do {
	try engine.start()
	let finished = DispatchSemaphore(value: 0)
	player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { _ in finished.signal() }
	player.play()
	let seconds = Double(file.length) / file.processingFormat.sampleRate
	_ = finished.wait(timeout: .now() + seconds + 5)
	engine.stop()
} catch {
	startError = error
}

if let savedVolume { setVolume(savedVolume, of: speakers) }
if let savedMute { setMuted(savedMute, speakers) }
if let startError { fail("cannot start audio: \(startError)") }
