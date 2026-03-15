import UIKit
import Flutter
import AVFoundation
import MediaPlayer
import Accelerate

@UIApplicationMain
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

  private var playlist: [String] = []
  private var currentIndex: Int = 0
  private var shuffleEnabled = false
  private var repeatMode = 0
  private var shuffledIndices: [Int] = []
  private var shufflePosition: Int = 0

  private var currentEQProfile = "default"
  private var currentPreset = "cinema"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let ch = FlutterMethodChannel(
      name: "cinema.audio.luxe/audio",
      binaryMessenger: controller.binaryMessenger
    )
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
          channel?.invokeMethod("log", arguments: "setRepeat(\(mode))")
          self.repeatMode = mode; result(nil)
        }
      case "getAudioDevice":
        result(self.getCurrentAudioDevice())
      case "getOutputDevices":
        result(self.getAvailableOutputDevices())
      case "setOutputDevice":
        if let args = call.arguments as? [String: Any], let portType = args["portType"] as? String {
          result(self.setOutputDevice(portType: portType))
        } else {
          result(false)
        }
      case "bindDeviceProfile":
        // Appelé depuis Flutter quand l'utilisateur associe un profil à un appareil renommé
        if let args = call.arguments as? [String: Any],
           let name = args["name"] as? String,
           let profile = args["profile"] as? String {
          self.bindDeviceProfile(name: name, profile: profile); result(nil)
        }
      case "getCurrentIndex":
        result(self.currentIndex)
      case "isPlaying":
        result(self.isPlaying)
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
      try session.setCategory(
        .playback, mode: .default,
        options: [.allowBluetoothA2DP, .allowAirPlay]
      )
      try session.setPreferredIOBufferDuration(0.005)
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch { print("Session error: \(error)") }
  }

  // MARK: - Engine Setup

  func setupAudioEngine() {
    configureAudioSession()

    audioEngine = AVAudioEngine()
    player      = AVAudioPlayerNode()
    eq          = AVAudioUnitEQ(numberOfBands: 10)
    reverb      = AVAudioUnitReverb()
    delay       = AVAudioUnitDelay()
    distortion  = AVAudioUnitDistortion()
    timePitch   = AVAudioUnitTimePitch()
    mixerNode   = AVAudioMixerNode()

    let compDesc = AudioComponentDescription(
      componentType: kAudioUnitType_Effect,
      componentSubType: kAudioUnitSubType_DynamicsProcessor,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0, componentFlagsMask: 0
    )
    compressor = AVAudioUnitEffect(audioComponentDescription: compDesc)

    guard
      let engine = audioEngine, let player = player, let eq = eq,
      let reverb = reverb, let delay = delay, let distortion = distortion,
      let timePitch = timePitch, let comp = compressor, let mixer = mixerNode
    else { return }

    engine.attach(player); engine.attach(eq); engine.attach(reverb)
    engine.attach(delay);  engine.attach(distortion); engine.attach(timePitch)
    engine.attach(comp);   engine.attach(mixer)

    applyEQBands(defaultEQBands())
    reverb.loadFactoryPreset(.largeHall2); reverb.wetDryMix = 25
    delay.delayTime = 0.28; delay.feedback = 30
    delay.lowPassCutoff = 9000; delay.wetDryMix = 12
    distortion.loadFactoryPreset(.drumsBitBrush); distortion.wetDryMix = 3

    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    engine.connect(player,     to: eq,         format: format)
    engine.connect(eq,         to: distortion, format: format)
    engine.connect(distortion, to: comp,       format: format)
    engine.connect(comp,       to: delay,      format: format)
    engine.connect(delay,      to: reverb,     format: format)
    engine.connect(reverb,     to: timePitch,  format: format)
    engine.connect(timePitch,  to: mixer,      format: format)
    engine.connect(mixer,      to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 1.0

    engine.prepare()
    do { try engine.start(); isEngineRunning = true }
    catch { print("Engine start error: \(error)") }

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

  private func defaultEQBands()          -> [(Float, Float)] { [(32,4),(64,3),(125,2),(250,1),(500,1),(1000,2),(2000,3),(4000,4),(8000,5),(12000,4)] }
  private func lp23EQBands()             -> [(Float, Float)] { [(32,2),(60,6),(125,1),(300,-4),(500,0),(1000,1),(3000,5),(4000,3),(8000,2),(12000,6)] }
  private func lp201EQBands()            -> [(Float, Float)] { [(32,1),(64,3),(125,2),(250,-2),(500,0),(1000,2),(2000,2),(4000,3),(8000,3),(12000,4)] }
  private func airpodsEQBands()          -> [(Float, Float)] { [(32,2),(64,2),(125,1),(250,0),(500,0),(1000,1),(2000,2),(4000,3),(8000,3),(12000,5)] }
  private func genericBluetoothEQBands() -> [(Float, Float)] { [(32,3),(64,3),(125,2),(250,0),(500,0),(1000,1),(2000,2),(4000,3),(8000,3),(12000,3)] }
  private func wiredEQBands()            -> [(Float, Float)] { [(32,2),(64,2),(125,1),(250,0),(500,0),(1000,1),(2000,2),(4000,3),(8000,4),(12000,4)] }
  private func speakerEQBands()          -> [(Float, Float)] { [(32,-4),(64,-2),(125,0),(250,2),(500,3),(1000,4),(2000,3),(4000,2),(8000,1),(12000,0)] }

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
    case "lp23":      applyEQBands(lp23EQBands())
    case "lp201":     applyEQBands(lp201EQBands())
    case "airpods":   applyEQBands(airpodsEQBands())
    case "bluetooth": applyEQBands(genericBluetoothEQBands())
    case "wired":     applyEQBands(wiredEQBands())
    case "speaker":   applyEQBands(speakerEQBands())
    default:          applyEQBands(defaultEQBands())
    }
  }

  // MARK: - Device → Profile binding (résistant au renommage)
  // Sauvegarde dans UserDefaults : clé "eq_profile_for_<nomExactAppareil>"
  // Fonctionne même si l'appareil s'appelle "<->" ou ">-<"

  private func savedProfile(for deviceName: String) -> String? {
    UserDefaults.standard.string(forKey: "eq_profile_for_\(deviceName)")
  }

  func bindDeviceProfile(name: String, profile: String) {
    UserDefaults.standard.set(profile, forKey: "eq_profile_for_\(name)")
    applyEQProfile(profile)
  }

  // MARK: - Audio Device Detection (universel)
  // Fonctionne avec : AirPods, Bluetooth générique, filaire, haut-parleur,
  // HDMI, AirPlay, et tout appareil renommé avec n'importe quel nom

  func getCurrentAudioDevice() -> String {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    guard let port = outputs.first else { return "speaker" }
    let rawName = port.portName
    let name    = rawName.lowercased()

    switch port.portType {

    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
      // Priorité 1 : profil associé manuellement (résistant à tout renommage)
      if let saved = savedProfile(for: rawName) { return "saved:\(rawName):\(saved)" }
      // Priorité 2 : détection par nom d'usine
      if name.contains("lp23")    || name.contains("lp-23")  || name.contains("thinkplus") { return "auto:lp23" }
      if name.contains("lp201")   || name.contains("lp-201") || name.contains("lp 201")    { return "auto:lp201" }
      if name.contains("airpods")                                                            { return "auto:airpods" }
      // Priorité 3 : Bluetooth inconnu → profil générique + notification Flutter
      return "unknown_bt:\(rawName)"

    case .headphones, .headsetMic:
      if let saved = savedProfile(for: rawName) { return "saved:\(rawName):\(saved)" }
      if name.contains("lp201") || name.contains("lp-201")   { return "auto:lp201" }
      if name.contains("airpods")                             { return "auto:airpods" }
      return "wired:\(rawName)"

    case .airPlay:
      return "airplay:\(rawName)"

    case .builtInSpeaker:
      return "speaker"

    case .builtInReceiver:
      return "receiver"

    default:
      // HDMI, USB, CarPlay, etc.
      if let saved = savedProfile(for: rawName) { return "saved:\(rawName):\(saved)" }
      return "other:\(rawName)"
    }
  }

  func getAvailableOutputDevices() -> [[String: String]] {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    return outputs.map { output in
      [
        "portType": output.portType.rawValue,
        "portName": output.portName,
      ]
    }
  }

  func setOutputDevice(portType: String) -> Bool {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setActive(true)
      if portType == AVAudioSession.Port.builtInSpeaker.rawValue {
        try session.overrideOutputAudioPort(.speaker)
      } else {
        try session.overrideOutputAudioPort(.none)
      }
      return true
    } catch {
      print("Failed to set output device: \(error)")
      return false
    }
  }

  private func autoApplyEQForDevice() {
    let device = getCurrentAudioDevice()

    if device == "speaker" || device == "receiver" {
      applyEQProfile("speaker")

    } else if device.hasPrefix("saved:") {
      // "saved:<nom>:<profil>" — le nom peut contenir des ":" donc on split sur 2 max
      let parts = device.split(separator: ":", maxSplits: 2).map(String.init)
      if parts.count == 3 { applyEQProfile(parts[2]) }

    } else if device.hasPrefix("auto:") {
      applyEQProfile(String(device.dropFirst("auto:".count)))

    } else if device.hasPrefix("wired:") {
      applyEQProfile("wired")

    } else if device.hasPrefix("airplay:") {
      applyEQProfile("default")

    } else if device.hasPrefix("unknown_bt:") {
      // Bluetooth inconnu → profil générique immédiat + Flutter propose l'association
      applyEQProfile("bluetooth")
      let rawName = String(device.dropFirst("unknown_bt:".count))
      channel?.invokeMethod("onUnknownDevice", arguments: ["name": rawName])

    } else {
      applyEQProfile("default")
    }
  }

  // MARK: - Presets

  func applyPreset(_ preset: String) {
    do {
      channel?.invokeMethod("log", arguments: "applyPreset(\(preset))")
      currentPreset = preset
      guard let reverb = reverb, let delay = delay,
            let distortion = distortion, let eq = eq else {
        channel?.invokeMethod("log", arguments: "⚠️ Audio units not ready")
        return
      }

      switch preset {
      case "cinema":
        reverb.loadFactoryPreset(.largeHall2); reverb.wetDryMix = 30
        delay.wetDryMix = 15; delay.delayTime = 0.28; distortion.wetDryMix = 3
        eq.bands[0].gain = 5; eq.bands[9].gain = 4
        audioEngine?.mainMixerNode.outputVolume = 1.0; applyCrossfeed(0.3)
      case "concert":
        reverb.loadFactoryPreset(.largeRoom2); reverb.wetDryMix = 40
        delay.wetDryMix = 20; delay.delayTime = 0.35; distortion.wetDryMix = 5
        eq.bands[0].gain = 3; eq.bands[5].gain = 4; eq.bands[9].gain = 5
        audioEngine?.mainMixerNode.outputVolume = 1.0; applyCrossfeed(0.2)
      case "studio":
        reverb.loadFactoryPreset(.smallRoom); reverb.wetDryMix = 8
        delay.wetDryMix = 5; delay.delayTime = 0.1; distortion.wetDryMix = 2
        applyEQBands(defaultEQBands())
        audioEngine?.mainMixerNode.outputVolume = 1.0; applyCrossfeed(0.0)
      case "bassBoost":
        reverb.wetDryMix = 15; delay.wetDryMix = 8; distortion.wetDryMix = 6
        eq.bands[0].gain = 10; eq.bands[1].gain = 8; eq.bands[2].gain = 5; eq.bands[3].gain = -2
        audioEngine?.mainMixerNode.outputVolume = 1.0; applyCrossfeed(0.1)
      case "vocal":
        reverb.loadFactoryPreset(.mediumHall); reverb.wetDryMix = 20
        delay.wetDryMix = 10; delay.delayTime = 0.15; distortion.wetDryMix = 4
        eq.bands[4].gain = 3; eq.bands[5].gain = 6; eq.bands[6].gain = 7
        eq.bands[7].gain = 5; eq.bands[0].gain = -2
        audioEngine?.mainMixerNode.outputVolume = 1.0; applyCrossfeed(0.25)
      default: 
        channel?.invokeMethod("log", arguments: "⚠️ Unknown preset: \(preset)")
      }
      channel?.invokeMethod("log", arguments: "✅ Preset \(preset) applied")
    } catch {
      channel?.invokeMethod("log", arguments: "❌ applyPreset error: \(error)")
    }
  }

  private func applyCrossfeed(_ amount: Float) {
    mixerNode?.outputVolume = 1.0 - (amount * 0.15)
    player?.pan = 0
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
    info[MPMediaItemPropertyTitle] = playlist.isEmpty
      ? "Cinema Audio Luxe"
      : URL(fileURLWithPath: playlist[currentIndex]).deletingPathExtension().lastPathComponent
    info[MPMediaItemPropertyPlaybackDuration] = getDuration()
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = getPosition()
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  // MARK: - Playback

  func loadAudio(path: String) {
    do {
      guard FileManager.default.fileExists(atPath: path) else {
        channel?.invokeMethod("log", arguments: "⚠️ File not found: \(path)")
        return
      }

      if audioEngine == nil { setupAudioEngine() }

      audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: path))
      seekFrameOffset = 0
      lastSeekTime = 0
      player?.stop()
      channel?.invokeMethod("log", arguments: "✅ Audio loaded")
    } catch {
      channel?.invokeMethod("log", arguments: "❌ Load error: \(error)")
    }
  }

  func loadPlaylist(paths: [String], index: Int) {
    do {
      channel?.invokeMethod("log", arguments: "loadPlaylist: \(paths.count) tracks, index: \(index)")
      guard !paths.isEmpty, index >= 0, index < paths.count else {
        channel?.invokeMethod("log", arguments: "⚠️ Invalid playlist parameters")
        playlist = []
        currentIndex = 0
        return
      }

      playlist = paths
      currentIndex = index
      loadAudio(path: paths[index])

      if shuffleEnabled && !paths.isEmpty {
        buildShuffleOrder()
      }
      channel?.invokeMethod("log", arguments: "✅ Playlist loaded with \(paths.count) tracks")
    } catch {
      channel?.invokeMethod("log", arguments: "❌ loadPlaylist error: \(error)")
    }
  }

  func play() {
    do {
      guard let file = audioFile else {
        channel?.invokeMethod("log", arguments: "⚠️ No audio loaded")
        return
      }
      if audioEngine == nil || !isEngineRunning { setupAudioEngine() }
      guard let player = player, isEngineRunning else {
        channel?.invokeMethod("log", arguments: "⚠️ Engine not ready")
        return
      }
      player.stop()
      let startFrame = seekFrameOffset
      let remaining  = file.length - startFrame
      guard remaining > 0 else {
        channel?.invokeMethod("log", arguments: "⚠️ Nothing to play")
        return
      }
      player.scheduleSegment(file, startingFrame: startFrame,
        frameCount: AVAudioFrameCount(remaining), at: nil) { [weak self] in
        DispatchQueue.main.async { self?.onTrackFinished() }
      }
      player.play()
      isPlaying = true
      updateNowPlaying()
      channel?.invokeMethod("log", arguments: "✅ Playing")
    } catch {
      channel?.invokeMethod("log", arguments: "❌ CRASH play: \(error)")
    }
  }

  func pause() {
    do {
      guard isPlaying else {
        channel?.invokeMethod("log", arguments: "⚠️ Not playing")
        return
      }

      lastSeekTime    = getPosition()
      seekFrameOffset = AVAudioFramePosition(lastSeekTime * (audioFile?.processingFormat.sampleRate ?? 44100))
      if let player = player {
        player.pause()
      } else {
        channel?.invokeMethod("log", arguments: "⚠️ Player nil")
      }

      isPlaying = false
      updateNowPlaying()
      channel?.invokeMethod("log", arguments: "✅ Paused")
    } catch {
      channel?.invokeMethod("log", arguments: "❌ CRASH pause: \(error)")
    }
  }

  func seek(to position: Double) {
    do {
      guard let file = audioFile, isEngineRunning, let player = player else {
        channel?.invokeMethod("log", arguments: "⚠️ Seek: not ready")
        return
      }
      
      // Limiter strictement la position pour éviter le callback onTrackFinished
      let maxPosition = getDuration() * 0.98  // 98% max pour éviter la fin
      let safePosition = min(position, maxPosition)
      
      let framePos  = AVAudioFramePosition(safePosition * file.processingFormat.sampleRate)
      let remaining = file.length - framePos
      guard remaining > 100 else {  // Au moins 100 frames restantes
        channel?.invokeMethod("log", arguments: "⚠️ Seek: too close to end")
        return
      }
      seekFrameOffset = framePos
      lastSeekTime = safePosition
      let wasPlaying = isPlaying
      player.stop()
      
      // NE PAS utiliser le callback completion pour éviter onTrackFinished pendant seek
      player.scheduleSegment(file, startingFrame: framePos,
        frameCount: AVAudioFrameCount(remaining), at: nil, completionHandler: nil)
      
      if wasPlaying { player.play() }
      updateNowPlaying()
      channel?.invokeMethod("log", arguments: "✅ Seeked to \(safePosition)")
    } catch {
      channel?.invokeMethod("log", arguments: "❌ CRASH seek: \(error)")
    }
  }

  func getDuration() -> Double {
    guard let file = audioFile else { return 0 }
    return Double(file.length) / file.processingFormat.sampleRate
  }

  func getPosition() -> Double {
    guard let player = player, let file = audioFile else { return lastSeekTime }
    if let nodeTime = player.lastRenderTime,
       let playerTime = player.playerTime(forNodeTime: nodeTime) {
      return min(lastSeekTime + Double(playerTime.sampleTime) / playerTime.sampleRate, getDuration())
    }
    return lastSeekTime
  }

  // MARK: - Shuffle

  private func buildShuffleOrder() {
    guard !playlist.isEmpty else {
      shuffledIndices = []
      shufflePosition = 0
      return
    }
    shuffledIndices = Array(0..<playlist.count).shuffled()
    if let pos = shuffledIndices.firstIndex(of: currentIndex) {
      shuffledIndices.swapAt(0, pos); shufflePosition = 0
    }
  }

  func setShuffle(_ enabled: Bool) {
    do {
      channel?.invokeMethod("log", arguments: "setShuffle(\(enabled))")
      shuffleEnabled = enabled
      if enabled && !playlist.isEmpty {
        buildShuffleOrder()
        channel?.invokeMethod("log", arguments: "setShuffle: shuffle enabled, order built")
      } else if !enabled {
        shufflePosition = 0
        shuffledIndices = []
        channel?.invokeMethod("log", arguments: "setShuffle: shuffle disabled")
      }
    } catch {
      channel?.invokeMethod("log", arguments: "❌ setShuffle error: \(error)")
    }
  }

  private func nextIndex() -> Int? {
    channel?.invokeMethod("log", arguments: "nextIndex() called, shuffle: \(shuffleEnabled), repeat: \(repeatMode)")
    guard !playlist.isEmpty else {
      channel?.invokeMethod("log", arguments: "nextIndex(): playlist empty")
      return nil
    }

    if shuffleEnabled {
      // Reconstruire l'ordre shuffle si nécessaire
      if shuffledIndices.isEmpty || shuffledIndices.count != playlist.count {
        buildShuffleOrder()
      }

      guard !shuffledIndices.isEmpty else {
        channel?.invokeMethod("log", arguments: "nextIndex(): shuffle list empty")
        return nil
      }

      shufflePosition += 1
      if shufflePosition >= shuffledIndices.count {
        if repeatMode == 1 {
          buildShuffleOrder()
          channel?.invokeMethod("log", arguments: "nextIndex(): repeat shuffle, new order")
          return shuffledIndices.first
        }
        channel?.invokeMethod("log", arguments: "nextIndex(): reached end (no repeat)")
        return nil
      }
      channel?.invokeMethod("log", arguments: "nextIndex(): shuffle next at \(shufflePosition)")
      return shuffledIndices[shufflePosition]
    } else {
      let next = currentIndex + 1
      if next >= playlist.count {
        channel?.invokeMethod("log", arguments: "nextIndex(): reached end of playlist")
        return repeatMode == 1 ? 0 : nil
      }
      channel?.invokeMethod("log", arguments: "nextIndex(): linear next \(next)")
      return next
    }
  }

  private func onTrackFinished() {
    do {
      guard !playlist.isEmpty else {
        channel?.invokeMethod("onTrackFinished", arguments: nil)
        return
      }

      isPlaying = false

      if repeatMode == 2 {
        seek(to: 0)
        play()
        return
      }

      if let next = nextIndex() {
        currentIndex = next
        loadAudio(path: playlist[currentIndex])
        play()
        channel?.invokeMethod("onTrackChanged", arguments: ["index": currentIndex])
      } else {
        channel?.invokeMethod("onTrackFinished", arguments: nil)
      }
    } catch {
      channel?.invokeMethod("log", arguments: "❌ onTrackFinished error: \(error)")
    }
  }

  func playNext() {
    do {
      channel?.invokeMethod("log", arguments: "playNext() called")
      guard !playlist.isEmpty else {
        channel?.invokeMethod("log", arguments: "playNext(): playlist empty")
        return
      }

      if let next = nextIndex() {
        currentIndex = next
        channel?.invokeMethod("log", arguments: "playNext(): loading track at index \(currentIndex)")
        loadAudio(path: playlist[currentIndex])
        play()
        channel?.invokeMethod("onTrackChanged", arguments: ["index": currentIndex])
      } else {
        channel?.invokeMethod("log", arguments: "playNext(): no next index")
      }
    } catch {
      channel?.invokeMethod("log", arguments: "❌ playNext error: \(error)")
    }
  }

  func playPrevious() {
    do {
      channel?.invokeMethod("log", arguments: "playPrevious() called")
      guard !playlist.isEmpty else {
        channel?.invokeMethod("log", arguments: "playPrevious(): playlist empty")
        return
      }

      if getPosition() > 3 {
        channel?.invokeMethod("log", arguments: "playPrevious(): seeking to start")
        seek(to: 0); return
      }

      if shuffleEnabled {
        if shuffledIndices.isEmpty || shuffledIndices.count != playlist.count {
          buildShuffleOrder()
        }

        if shufflePosition > 0 {
          shufflePosition -= 1
          currentIndex = shuffledIndices[shufflePosition]
          channel?.invokeMethod("log", arguments: "playPrevious(): shuffle prev at \(shufflePosition)")
        } else {
          shufflePosition = shuffledIndices.count - 1
          currentIndex = shuffledIndices[shufflePosition]
          channel?.invokeMethod("log", arguments: "playPrevious(): shuffle wrap to end")
        }
      } else {
        guard currentIndex > 0 else {
          channel?.invokeMethod("log", arguments: "playPrevious(): at start, seeking to 0")
          seek(to: 0); return
        }
        currentIndex -= 1
        channel?.invokeMethod("log", arguments: "playPrevious(): linear prev to \(currentIndex)")
      }

      loadAudio(path: playlist[currentIndex])
      play()
      channel?.invokeMethod("onTrackChanged", arguments: ["index": currentIndex])
    } catch {
      channel?.invokeMethod("log", arguments: "❌ playPrevious error: \(error)")
    }
  }

  // MARK: - Effects

  func setEffect(effect: String, value: Float) {
    do {
      channel?.invokeMethod("log", arguments: "setEffect(\(effect), \(value))")
      switch effect {
      case "reverb":    reverb?.wetDryMix = value * 100
      case "bass":
        eq?.bands[0].gain = value * 14; eq?.bands[1].gain = value * 11; eq?.bands[2].gain = value * 8
      case "volume":
        audioEngine?.mainMixerNode.outputVolume = min(1.0, max(0.0, value))
      case "delay":     delay?.wetDryMix = value * 50
      case "warmth":    distortion?.wetDryMix = value * 20
      case "clarity":
        eq?.bands[6].gain = value * 8; eq?.bands[7].gain = value * 10; eq?.bands[8].gain = value * 12
      case "presence":
        eq?.bands[4].gain = value * 6; eq?.bands[5].gain = value * 8
      case "pitch":     timePitch?.pitch = value * 400 - 200
      case "crossfeed": applyCrossfeed(value)
      case "exciter":   distortion?.wetDryMix = value * 15
      case "compress":
        if let au = compressor {
          AudioUnitSetParameter(au.audioUnit, kDynamicsProcessorParam_Threshold,
            kAudioUnitScope_Global, 0, Float(-40 + value * 30), 0)
        }
      default: 
        channel?.invokeMethod("log", arguments: "⚠️ Unknown effect: \(effect)")
      }
      channel?.invokeMethod("log", arguments: "✅ Effect \(effect) applied")
    } catch {
      channel?.invokeMethod("log", arguments: "❌ setEffect error: \(error)")
    }
  }

  // MARK: - Route Change

  @objc func handleRouteChange(notification: Notification) {
    do {
      guard let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

      switch reason {
      case .newDeviceAvailable:
        autoApplyEQForDevice()
        channel?.invokeMethod("onDeviceChanged", arguments: ["device": getCurrentAudioDevice()])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          self?.restartEngineKeepingPosition()
        }
      case .oldDeviceUnavailable:
        if isPlaying { pause() }
        applyEQProfile("speaker")
        channel?.invokeMethod("onDeviceChanged", arguments: ["device": "speaker"])
      case .categoryChange, .override:
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
          self?.restartEngineKeepingPosition()
        }
      default: break
      }
    } catch {
      channel?.invokeMethod("log", arguments: "❌ handleRouteChange error: \(error)")
    }
  }

  @objc func handleInterruption(notification: Notification) {
    do {
      guard let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
      if type == .began {
        if isPlaying { pause() }
      } else if type == .ended {
        if let optVal = info[AVAudioSessionInterruptionOptionKey] as? UInt,
           AVAudioSession.InterruptionOptions(rawValue: optVal).contains(.shouldResume) { play() }
      }
    } catch {
      channel?.invokeMethod("log", arguments: "❌ handleInterruption error: \(error)")
    }
  }

  private func restartEngineKeepingPosition() {
    do {
      let savedPos = getPosition(); let wasPlaying = isPlaying
      guard let engine = audioEngine else {
        setupAudioEngine(); if wasPlaying { play() }; return
      }
      configureAudioSession()
      if isEngineRunning { engine.stop(); isEngineRunning = false }
      try engine.start(); isEngineRunning = true
      if wasPlaying { seek(to: savedPos) }
      else {
        seekFrameOffset = AVAudioFramePosition(savedPos * (audioFile?.processingFormat.sampleRate ?? 44100))
        lastSeekTime = savedPos
      }
      channel?.invokeMethod("log", arguments: "✅ Engine restarted")
    } catch {
      channel?.invokeMethod("log", arguments: "❌ restartEngine error: \(error)")
      audioEngine = nil; setupAudioEngine()
      let savedPos = getPosition(); let wasPlaying = isPlaying
      seek(to: savedPos); if wasPlaying { play() }
    }
  }
}