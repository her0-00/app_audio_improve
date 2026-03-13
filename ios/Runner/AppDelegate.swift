import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var audioEngine: CinemaAudioEngine?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(name: "cinema.audio.luxe/audio", binaryMessenger: controller.binaryMessenger)
        
        audioEngine = CinemaAudioEngine()
        
        channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard let self = self else { return }
            
            switch call.method {
            case "loadAudio":
                if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
                    self.audioEngine?.loadAudio(path: path)
                    result(nil)
                }
            case "play":
                self.audioEngine?.play()
                result(nil)
            case "pause":
                self.audioEngine?.pause()
                result(nil)
            case "seek":
                if let args = call.arguments as? [String: Any], let position = args["position"] as? Double {
                    self.audioEngine?.seek(to: position)
                    result(nil)
                }
            case "getDuration":
                result(self.audioEngine?.getDuration() ?? 0.0)
            case "setEffect":
                if let args = call.arguments as? [String: Any],
                   let effect = args["effect"] as? String,
                   let value = args["value"] as? Double {
                    self.audioEngine?.setEffect(effect: effect, value: Float(value))
                    result(nil)
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

class CinemaAudioEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    
    private let eq = AVAudioUnitEQ(numberOfBands: 3)
    private let reverb = AVAudioUnitReverb()
    private let compressor = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_DynamicsProcessor,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0))
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0))
    
    private var reverbMix: Float = 0.15
    private var bassGain: Float = 0.0
    private var volumeBoost: Float = 0.0
    
    init() {
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        engine.attach(player)
        engine.attach(eq)
        engine.attach(reverb)
        engine.attach(compressor)
        engine.attach(limiter)
        
        eq.bands[0].frequency = 40
        eq.bands[0].bandwidth = 1.0
        eq.bands[0].gain = 0
        eq.bands[0].filterType = .parametric
        eq.bands[0].bypass = false
        
        eq.bands[1].frequency = 1000
        eq.bands[1].bandwidth = 0.5
        eq.bands[1].gain = 2
        eq.bands[1].filterType = .parametric
        eq.bands[1].bypass = false
        
        eq.bands[2].frequency = 8000
        eq.bands[2].bandwidth = 1.0
        eq.bands[2].gain = 3
        eq.bands[2].filterType = .parametric
        eq.bands[2].bypass = false
        
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = reverbMix * 100
        
        engine.connect(player, to: eq, format: nil)
        engine.connect(eq, to: reverb, format: nil)
        engine.connect(reverb, to: compressor, format: nil)
        engine.connect(compressor, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)
        
        engine.prepare()
        try? engine.start()
    }
    
    func loadAudio(path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            audioFile = try AVAudioFile(forReading: url)
            player.stop()
        } catch {
            print("Error loading audio: \(error)")
        }
    }
    
    func play() {
        guard let file = audioFile else { return }
        
        if !player.isPlaying {
            player.scheduleFile(file, at: nil) {
                DispatchQueue.main.async {
                    self.player.stop()
                }
            }
            player.play()
        }
    }
    
    func pause() {
        player.pause()
    }
    
    func seek(to position: Double) {
        guard let file = audioFile else { return }
        let framePosition = AVAudioFramePosition(position * file.processingFormat.sampleRate)
        player.stop()
        player.scheduleSegment(file, startingFrame: framePosition, frameCount: AVAudioFrameCount(file.length - framePosition), at: nil)
        if player.isPlaying {
            player.play()
        }
    }
    
    func getDuration() -> Double {
        guard let file = audioFile else { return 0.0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
    
    func setEffect(effect: String, value: Float) {
        switch effect {
        case "reverb":
            reverbMix = value
            reverb.wetDryMix = value * 100
        case "bass":
            bassGain = value
            eq.bands[0].gain = value * 18
        case "volume":
            volumeBoost = value
            engine.mainMixerNode.outputVolume = 1.0 + (value * 2.0)
        default:
            break
        }
    }
}
