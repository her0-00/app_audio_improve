import UIKit
import Flutter
import AVFoundation
import MediaPlayer
import Accelerate

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var audioEngine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var eq: AVAudioUnitEQ?
  private var reverb: AVAudioUnitReverb?
  private var delay: AVAudioUnitDelay?
  private var distortion: AVAudioUnitDistortion?
  private var timePitch: AVAudioUnitTimePitch?
  private var compressor: AVAudioUnitEffect?
  private var mixerNode: AVAudioMixerNode?

  private var audioFile: AVAudioFile?
  private var isEngineRunning = false
  private var isPlaying = false
  private var seekFrameOffset: AVAudioFramePosition = 0
  private var lastSeekTime: Double = 0
  private var channel: FlutterMethodChannel?

  // Playlist / shuffle / repeat
  private var playlist: [String] = []
  private var currentIndex: Int = 0
  private var shuffleEnabled = false
  private var repeatMode = 0 // 0=off, 1=all, 2=one
  private var shuffledIndices: [Int] = []
  private var shufflePosition: Int = 0

  // Profil EQ actif
  private var currentEQProfile = "default"
  private var currentPreset = "cinema"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let ch = FlutterMethodChannel(name: "cinema.audio.luxe/audio", binaryMessenger: controller.binaryMessenger)
    self.channel = ch

    ch.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "loadAudio":
        if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
          self.loadAudio(path: path); result(nil)
        }
      case "loadPlaylist":
        if let args = call.arguments as? [String: Any],
           let paths = args["paths"] as? [String],
           let index = args["index"] as? Int {
          self.loadPlaylist(paths: paths, index: index); result(nil)
        }
      case "play":   self.play();    result(nil)
      case "pause":  self.pause();   result(nil)
      case "seek":
        if let args = call.arguments as? [String: Any], let pos = args["position"] as? Double {
          self.seek(to: pos); result(nil)
        }
      case "getDuration": result(self.getDuration())
      case "getPosition": result(self.getPosition())
      case "next":     self.playNext();     result(nil)
      case "previous": self.playPrevious(); result(nil)
      case "setEffect":
        if let args = call.arguments as? [String: Any],
           let effect = args["effect"] as? String,
           let value = args["value"] as? Double {
          self.setEffect(effect: effect, value: Float(value)); result(nil)
        }
      case "setPreset":
        if let args = call.arguments as? [String: Any], let preset = args["preset"] as? String {
          self.applyPreset(preset); result(nil)
        }
      case "setEQProfile":
        if let args = call.arguments as? [String: Any], let profile = args["profile"] as? String {
          self.applyEQProfile(profile); result(nil)
        }
      case "setShuffle":
        if let args = call.arguments as? [String: Any], let enabled = args["enabled"] as? Bool {
          self.setShuffle(enabled); result(nil)
        }
      case "setRepeat":
        if let args = call.arguments as? [String: Any], let mode = args["mode"] as? Int {
          self.repeatMode = mode; result(nil)
        }
      case "getAudioDevice":
        result(self.getCurrentAudioDevice())
      case "openURL":
        if let args = call.arguments as? [String: Any],
           let urlString = args["url"] as? String,
           let url = URL(string: urlString) {
          UIApplication.shared.open(url); result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Audio Session

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default,
        options: [.allowBluetoothA2DP, .allowAirPlay])
      try session.setPreferredIOBufferDuration(0.005)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch { print("Session error: \(error)") }
  }

  // MARK: - Engine Setup

  func setupAudioEngine() {
    configureAudioSession()

    audioEngine  = AVAudioEngine()
    player       = AVAudioPlayerNode()
    eq           = AVAudioUnitEQ(numberOfBands: 10)
    reverb       = AVAudioUnitReverb()
    delay        = AVAudioUnitDelay()
    distortion   = AVAudioUnitDistortion()
    timePitch    = AVAudioUnitTimePitch()
    mixerNode    = AVAudioMixerNode()

    // Compresseur multibande via DynamicsProcessor
    var compDesc = AudioComponentDescription(
      componentType: kAudioUnitType_Effect,
      componentSubType: kAudioUnitSubType_DynamicsProcessor,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0, componentFlagsMask: 0)
    compressor = AVAudioUnitEffect(audioComponentDescription: compDesc)

    guard let engine = audioEngine, let player = player, let eq = eq,
          let reverb = reverb, let delay = delay, let distortion = distortion,
          let timePitch = timePitch, let comp = compressor,
          let mixer = mixerNode else { return }

    engine.attach(player)
    engine.attach(eq)
    engine.attach(reverb)
    engine.attach(delay)
    engine.attach(distortion)
    engine.attach(timePitch)
    engine.attach(comp)
    engine.attach(mixer)

    // EQ 10 bandes — profil par défaut (cinéma Dolby)
    applyEQBands(defaultEQBands())

    reverb.loadFactoryPreset(.largeHall2)
    reverb.wetDryMix = 25

    delay.delayTime = 0.28
    delay.feedback = 30
    delay.lowPassCutoff = 9000
    delay.wetDryMix = 12

    // Exciter harmonique : distortion douce 2nd harmonique
    distortion.loadFactoryPreset(.drumsBitBrush)
    distortion.wetDryMix = 3

    // Compresseur : threshold -20dB, ratio 4:1
    if let au = comp.audioUnit {
      AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold,
        kAudioUnitScope_Global, 0, -20, 0)
      AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom,
        kAudioUnitScope_Global, 0, 5, 0)
      AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime,
        kAudioUnitScope_Global, 0, 0.001, 0)
      AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime,
        kAudioUnitScope_Global, 0, 0.05, 0)
      AudioUnitSetParameter(au, kDynamicsProcessorParam_MasterGain,
        kAudioUnitScope_Global, 0, 0, 0)
    }

    let format = engine.mainMixerNode.outputFormat(forBus: 0)
    // Chaîne : player → EQ → distortion(exciter) → compressor → delay → reverb → timePitch → mixer → main
    engine.connect(player,     to: eq,          format: format)
    engine.connect(eq,         to: distortion,  format: format)
    engine.connect(distortion, to: comp,        format: format)
    engine.connect(comp,       to: delay,       format: format)
    engine.connect(delay,      to: reverb,      format: format)
    engine.connect(reverb,     to: timePitch,   format: format)
    engine.connect(timePitch,  to: mixer,       format: format)
    engine.connect(mixer,      to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 1.0

    engine.prepare()
    do {
      try engine.start()
      isEngineRunning = true
    } catch { print("Engine start error: \(error)") }

    NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange),
      name: AVAudioSession.routeChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption),
      name: AVAudioSession.interruptionNotification, object: nil)

    setupRemoteControls()
    applyPreset(currentPreset)
    autoApplyEQForDevice()
  }

  // MARK: - EQ Profiles

  private func defaultEQBands() -> [(Float, Float)] {
    [(32,4),(64,3),(125,2),(250,1),(500,1),(1000,2),(2000,3),(4000,4),(8000,5),(12000,4)]
  }

  // ThinkPlus P23 (Bluetooth 10mm driver) : boost 60Hz, coupe 300Hz, boost 3kHz, air 12kHz
  private func p23EQBands() -> [(Float, Float)] {
    [(32,2),(60,6),(125,1),(300,-4),(500,0),(1000,1),(3000,5),(4000,3),(8000,2),(12000,6)]
  }

  // Série L201 (filaire) : courbe plus plate, moins de coloration
  private func l201EQBands() -> [(Float, Float)] {
    [(32,1),(64,3),(125,2),(250,-2),(500,0),(1000,2),(2000,2),(4000,3),(8000,3),(12000,4)]
  }

  private func applyEQBands(_ bands: [(Float, Float)]) {
    guard let eq = eq else { return }
    let filterTypes: [AVAudioUnitEQFilterType] = [
      .highPass, .parametric, .parametric, .parametric, .parametric,
      .parametric, .parametric, .parametric, .parametric, .lowPass
    ]
    for (i, (freq, gain)) in bands.enumerated() {
      eq.bands[i].frequency  = freq
      eq.bands[i].gain       = gain
      eq.bands[i].bandwidth  = 0.7
      eq.bands[i].filterType = filterTypes[i]
      eq.bands[i].bypass     = false
    }
  }

  func applyEQProfile(_ profile: String) {
    currentEQProfile = profile
    switch profile {
    case "p23":    applyEQBands(p23EQBands())
    case "l201":   applyEQBands(l201EQBands())
    default:       applyEQBands(defaultEQBands())
    }
  }

  // MARK: - Presets

  func applyPreset(_ preset: String) {
    currentPreset = preset
    guard let reverb = reverb, let delay = delay,
          let distortion = distortion, let eq = eq else { return }

    switch preset {
    case "cinema":
      reverb.loadFactoryPreset(.largeHall2); reverb.wetDryMix = 30
      delay.wetDryMix = 15; delay.delayTime = 0.28
      distortion.wetDryMix = 3
      eq.bands[0].gain = 5; eq.bands[9].gain = 4
      audioEngine?.mainMixerNode.outputVolume = 1.2
      applyCrossfeed(0.3) // Crossfeed pour simulation enceintes cinéma

    case "concert":
      reverb.loadFactoryPreset(.largeRoom2); reverb.wetDryMix = 40
      delay.wetDryMix = 20; delay.delayTime = 0.35
      distortion.wetDryMix = 5
      eq.bands[0].gain = 3; eq.bands[5].gain = 4; eq.bands[9].gain = 5
      audioEngine?.mainMixerNode.outputVolume = 1.3
      applyCrossfeed(0.2)

    case "studio":
      reverb.loadFactoryPreset(.smallRoom); reverb.wetDryMix = 8
      delay.wetDryMix = 5; delay.delayTime = 0.1
      distortion.wetDryMix = 2
      applyEQBands(defaultEQBands())
      audioEngine?.mainMixerNode.outputVolume = 1.0
      applyCrossfeed(0.0) // Pas de crossfeed en studio

    case "bassBoost":
      reverb.wetDryMix = 15
      delay.wetDryMix = 8
      distortion.wetDryMix = 6
      eq.bands[0].gain = 10; eq.bands[1].gain = 8; eq.bands[2].gain = 5
      eq.bands[3].gain = -2
      audioEngine?.mainMixerNode.outputVolume = 1.1
      applyCrossfeed(0.1)

    case "vocal":
      reverb.loadFactoryPreset(.mediumHall); reverb.wetDryMix = 20
      delay.wetDryMix = 10; delay.delayTime = 0.15
      distortion.wetDryMix = 4
      eq.bands[4].gain = 3; eq.bands[5].gain = 6; eq.bands[6].gain = 7
      eq.bands[7].gain = 5; eq.bands[0].gain = -2
      audioEngine?.mainMixerNode.outputVolume = 1.15
      applyCrossfeed(0.25)

    default: break
    }
  }

  // MARK: - Crossfeed stéréo (simulation écoute enceintes)
  // Implémenté via le mixerNode outputVolume + pan subtil sur le player
  private func applyCrossfeed(_ amount: Float) {
    // amount 0..1 : 0 = stéréo pure, 1 = mono (crossfeed max)
    // On simule en réduisant la séparation stéréo via le volume du mixer
    mixerNode?.outputVolume = 1.0 - (amount * 0.15)
    player?.pan = 0 // centré
  }

  // MARK: - Remote Controls

  private func setupRemoteControls() {
    let rc = MPRemoteCommandCenter.shared()
    rc.playCommand.addTarget  { [weak self] _ in self?.play();         return .success }
    rc.pauseCommand.addTarget { [weak self] _ in self?.pause();        return .success }
    rc.nextTrackCommand.addTarget     { [weak self] _ in self?.playNext();     return .success }
    rc.previousTrackCommand.addTarget { [weak self] _ in self?.playPrevious(); return .success }
    rc.changePlaybackPositionCommand.addTarget { [weak self] event in
      if let e = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: e.positionTime) }
      return .success
    }
  }

  private func updateNowPlaying() {
    var info = [String: Any]()
    info[MPMediaItemPropertyTitle] = playlist.isEmpty ? "Cinema Audio Luxe" :
      URL(fileURLWithPath: playlist[currentIndex]).deletingPathExtension().lastPathComponent
    info[MPMediaItemPropertyPlaybackDuration] = getDuration()
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = getPosition()
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  // MARK: - Audio Device Detection

  func getCurrentAudioDevice() -> String {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    guard let port = outputs.first else { return "speaker" }
    switch port.portType {
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
      let name = port.portName.lowercased()
      if name.contains("p23") || name.contains("thinkplus") { return "lenovo_p23" }
      if name.contains("l20") || name.contains("l201")      { return "lenovo_l201" }
      return "bluetooth:\(port.portName)"
    case .headphones:
      let name = port.portName.lowercased()
      if name.contains("lenovo") || name.contains("l20") { return "lenovo_l201" }
      return "headphones:\(port.portName)"
    case .builtInSpeaker: return "speaker"
    default: return port.portName
    }
  }

  private func autoApplyEQForDevice() {
    let device = getCurrentAudioDevice()
    switch device {
    case "lenovo_p23": applyEQProfile("p23")
    case "lenovo_l201": applyEQProfile("l201")
    default: applyEQProfile("default")
    }
  }

  // MARK: - Playback

  func loadAudio(path: String) {
    if audioEngine == nil { setupAudioEngine() }
    do {
      audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: path))
      seekFrameOffset = 0; lastSeekTime = 0
      player?.stop()
    } catch { print("Load error: \(error)") }
  }

  func loadPlaylist(paths: [String], index: Int) {
    playlist = paths; currentIndex = index
    loadAudio(path: paths[index])
    if shuffleEnabled { buildShuffleOrder() }
  }

  func play() {
    guard let file = audioFile else { return }
    if audioEngine == nil || !isEngineRunning { setupAudioEngine() }
    guard let player = player, isEngineRunning else { return }

    player.stop()
    let startFrame = seekFrameOffset
    let remaining  = file.length - startFrame
    guard remaining > 0 else { return }

    player.scheduleSegment(file, startingFrame: startFrame,
      frameCount: AVAudioFrameCount(remaining), at: nil) { [weak self] in
      DispatchQueue.main.async { self?.onTrackFinished() }
    }
    player.play()
    isPlaying = true
    updateNowPlaying()
  }

  func pause() {
    lastSeekTime = getPosition()
    seekFrameOffset = AVAudioFramePosition(lastSeekTime * (audioFile?.processingFormat.sampleRate ?? 44100))
    player?.pause()
    isPlaying = false
    updateNowPlaying()
  }

  func seek(to position: Double) {
    guard let file = audioFile, isEngineRunning, let player = player else { return }
    let framePos  = AVAudioFramePosition(position * file.processingFormat.sampleRate)
    let remaining = file.length - framePos
    guard remaining > 0 else { return }

    seekFrameOffset = framePos; lastSeekTime = position
    let wasPlaying = isPlaying
    player.stop()
    player.scheduleSegment(file, startingFrame: framePos,
      frameCount: AVAudioFrameCount(remaining), at: nil) { [weak self] in
      DispatchQueue.main.async { self?.onTrackFinished() }
    }
    if wasPlaying { player.play() }
    updateNowPlaying()
  }

  func getDuration() -> Double {
    guard let file = audioFile else { return 0 }
    return Double(file.length) / file.processingFormat.sampleRate
  }

  func getPosition() -> Double {
    guard let player = player, let file = audioFile else { return lastSeekTime }
    if let nodeTime = player.lastRenderTime,
       let playerTime = player.playerTime(forNodeTime: nodeTime) {
      let pos = lastSeekTime + Double(playerTime.sampleTime) / playerTime.sampleRate
      return min(pos, getDuration())
    }
    return lastSeekTime
  }

  // MARK: - Shuffle

  private func buildShuffleOrder() {
    shuffledIndices = Array(0..<playlist.count).shuffled()
    if let pos = shuffledIndices.firstIndex(of: currentIndex) {
      shuffledIndices.swapAt(0, pos)
      shufflePosition = 0
    }
  }

  func setShuffle(_ enabled: Bool) {
    shuffleEnabled = enabled
    if enabled { buildShuffleOrder() }
  }

  private func nextIndex() -> Int? {
    if shuffleEnabled {
      shufflePosition += 1
      if shufflePosition >= shuffledIndices.count {
        if repeatMode == 1 { buildShuffleOrder(); return shuffledIndices[0] }
        return nil
      }
      return shuffledIndices[shufflePosition]
    } else {
      let next = currentIndex + 1
      if next >= playlist.count {
        return repeatMode == 1 ? 0 : nil
      }
      return next
    }
  }

  private func onTrackFinished() {
    isPlaying = false
    if repeatMode == 2 {
      seek(to: 0); play(); return
    }
    if let next = nextIndex() {
      currentIndex = next
      loadAudio(path: playlist[currentIndex])
      play()
      channel?.invokeMethod("onTrackChanged", arguments: ["index": currentIndex])
    } else {
      channel?.invokeMethod("onTrackFinished", arguments: nil)
    }
  }

  func playNext() {
    guard !playlist.isEmpty else { return }
    if let next = nextIndex() {
      currentIndex = next
      loadAudio(path: playlist[currentIndex])
      play()
      channel?.invokeMethod("onTrackChanged", arguments: ["index": currentIndex])
    }
  }

  func playPrevious() {
    if getPosition() > 3 { seek(to: 0); return }
    if shuffleEnabled {
      if shufflePosition > 0 {
        shufflePosition -= 1
        currentIndex = shuffledIndices[shufflePosition]
      }
    } else {
      guard currentIndex > 0 else { seek(to: 0); return }
      currentIndex -= 1
    }
    loadAudio(path: playlist[currentIndex])
    play()
    channel?.invokeMethod("onTrackChanged", arguments: ["index": currentIndex])
  }

  // MARK: - Effects

  func setEffect(effect: String, value: Float) {
    switch effect {
    case "reverb":    reverb?.wetDryMix = value * 100
    case "bass":
      eq?.bands[0].gain = value * 14
      eq?.bands[1].gain = value * 11
      eq?.bands[2].gain = value * 8
    case "volume":    audioEngine?.mainMixerNode.outputVolume = 1.0 + value * 2.0
    case "delay":     delay?.wetDryMix = value * 50
    case "warmth":    distortion?.wetDryMix = value * 20
    case "clarity":
      eq?.bands[6].gain = value * 8
      eq?.bands[7].gain = value * 10
      eq?.bands[8].gain = value * 12
    case "presence":
      eq?.bands[4].gain = value * 6
      eq?.bands[5].gain = value * 8
    case "pitch":     timePitch?.pitch = value * 400 - 200
    case "crossfeed": applyCrossfeed(value)
    case "exciter":   distortion?.wetDryMix = value * 15
    case "compress":
      if let au = compressor?.audioUnit {
        let threshold = -40 + value * 30  // -40dB à -10dB
        AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold,
          kAudioUnitScope_Global, 0, threshold, 0)
      }
    default: break
    }
  }

  // MARK: - Route Change

  @objc func handleRouteChange(notification: Notification) {
    guard let info = notification.userInfo,
          let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

    switch reason {
    case .newDeviceAvailable:
      // Auto-detect Lenovo et appliquer le bon profil EQ
      let device = getCurrentAudioDevice()
      if device == "lenovo_p23"  { applyEQProfile("p23") }
      else if device == "lenovo_l201" { applyEQProfile("l201") }
      channel?.invokeMethod("onDeviceChanged", arguments: ["device": device])
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
        self?.restartEngineKeepingPosition()
      }
    case .oldDeviceUnavailable:
      if isPlaying { pause() }
      channel?.invokeMethod("onDeviceChanged", arguments: ["device": "speaker"])
    case .categoryChange, .override:
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
        self?.restartEngineKeepingPosition()
      }
    default: break
    }
  }

  @objc func handleInterruption(notification: Notification) {
    guard let info = notification.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
    if type == .began {
      if isPlaying { pause() }
    } else if type == .ended {
      if let optVal = info[AVAudioSessionInterruptionOptionKey] as? UInt,
         AVAudioSession.InterruptionOptions(rawValue: optVal).contains(.shouldResume) { play() }
    }
  }

  private func restartEngineKeepingPosition() {
    let savedPos = getPosition()
    let wasPlaying = isPlaying
    guard let engine = audioEngine else {
      setupAudioEngine(); if wasPlaying { play() }; return
    }
    configureAudioSession()
    if isEngineRunning { engine.stop(); isEngineRunning = false }
    do {
      try engine.start(); isEngineRunning = true
      if wasPlaying { seek(to: savedPos) }
      else {
        seekFrameOffset = AVAudioFramePosition(savedPos * (audioFile?.processingFormat.sampleRate ?? 44100))
        lastSeekTime = savedPos
      }
    } catch {
      audioEngine = nil; setupAudioEngine()
      seek(to: savedPos); if wasPlaying { play() }
    }
  }
}
