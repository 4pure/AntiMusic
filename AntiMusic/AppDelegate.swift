//
// AppDelegate.swift
// AntiMusic
//
// Created by nift4 on 08.12.2023.
//

import Cocoa
import MediaPlayer
import ServiceManagement

private enum FakeArtwork {
  static let size = CGSize(width: 1024, height: 1024)
  static let lightBackground = NSColor(
    srgbRed: 0.8274509804, green: 0.8274509804, blue: 0.831372549, alpha: 1)
  static let darkBackground = NSColor(
    srgbRed: 0.3529411765, green: 0.3529411765, blue: 0.3764705882, alpha: 1)
}

@main
@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {

  private let mediaRemote = MediaRemoteService()
  private let ownBundleID: String
  private var settingsVisible = false
  private var statusItemController: StatusItemController?
  private var settingsWindowController: NSWindowController?
  private var settingsViewController: ViewController?
  // Title is required so headset / media keys route to Remote Command Center.
  private var fakePlayer: [String: Any] = [MPMediaItemPropertyTitle: "<AntiMusic.app>"]
  private var isHoldingNowPlaying = true

  var ignoreMediaKey = false
  var playerPreset: MusicPlayerPreset = .appleMusic
  var customPlayerAppPath: String?
  var playerApp = "/System/Applications/Music.app"

  public override init() {
    ownBundleID = Bundle.main.bundleIdentifier ?? "org.nift4.AntiMusic"
    super.init()

    // Headset and system media keys are delivered through Now Playing.
    let infoCenter = MPNowPlayingInfoCenter.default()
    infoCenter.playbackState = .playing
    infoCenter.playbackState = .stopped

    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.handlePlay(fromControlCenter: false)
      }
      return .success
    }
    commandCenter.playCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        self?.handlePlay(fromControlCenter: true)
      }
      return .success
    }

    mediaRemote.onNowPlayingChanged { [weak self] in
      self?.loadSongInfo()
    }
    mediaRemote.start()

    DistributedNotificationCenter.default.addObserver(
      self,
      selector: #selector(interfaceModeChanged(sender:)),
      name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
      object: nil
    )

    loadPersistedSettings()
    refreshFakePlayerMetadata()
    loadSongInfo()
  }

  public func applicationDidFinishLaunching(_ notification: Notification) {
    enableLaunchAtLoginIfNeeded()

    let status = StatusItemController()
    status.delegate = self
    statusItemController = status
  }

  public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    openSettings()
    return false
  }

  public func applicationDidResignActive(_ notification: Notification) {
    guard settingsVisible else { return }
    if settingsViewController?.hasOpenPanel == true { return }
    settingsWindowController?.close()
    NSApp.setActivationPolicy(.accessory)
    settingsVisible = false
  }

  func openSettings() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    OperationQueue.main.addOperation {
      NSMenu.setMenuBarVisible(false)
      OperationQueue.main.addOperation {
        NSMenu.setMenuBarVisible(true)
      }
    }

    let controller = ensureSettingsWindow()
    controller.delegate = self
    controller.reloadFromDelegate()
    settingsWindowController?.window?.center()
    settingsWindowController?.showWindow(nil)
    settingsVisible = true
  }

  private func ensureSettingsWindow() -> ViewController {
    if let existing = settingsViewController, settingsWindowController != nil {
      return existing
    }

    let controller = ViewController()
    controller.delegate = self
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 168),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "AntiMusic 设置"
    window.contentViewController = controller
    window.isReleasedWhenClosed = false
    window.center()

    let windowController = NSWindowController(window: window)
    settingsViewController = controller
    settingsWindowController = windowController
    return controller
  }

  func resolvedPlayerPath() -> String {
    if let path = playerPreset.resolvedPath(customPath: customPlayerAppPath) {
      return path
    }
    return playerApp
  }

  func applyPlayerPreset(_ preset: MusicPlayerPreset, customPath: String? = nil) {
    if preset == .custom {
      if let customPath {
        customPlayerAppPath = customPath
      }
      guard let path = customPlayerAppPath, !path.isEmpty else { return }
      playerPreset = .custom
      playerApp = path
    } else {
      playerPreset = preset
      if let path = preset.resolvedPath(customPath: nil) {
        playerApp = path
      }
    }
    writeSettings()
    refreshFakePlayerMetadata()
    refreshNowPlaying()
    statusItemController?.reloadMenu()
    settingsViewController?.reloadFromDelegate()
  }

  func setIgnoreMediaKey(_ value: Bool) {
    ignoreMediaKey = value
    writeSettings()
    statusItemController?.reloadMenu()
    settingsViewController?.reloadFromDelegate()
  }

  private func handlePlay(fromControlCenter: Bool) {
    guard isHoldingNowPlaying else { return }
    if ignoreMediaKey && !fromControlCenter {
      return
    }
    openPreferredPlayer()
  }

  func openPreferredPlayer() {
    let path = resolvedPlayerPath()
    let url = URL(fileURLWithPath: path, isDirectory: true)
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) {
      _, error in
      if let error {
        NSLog("AntiMusic: failed to open player %@: %@", path, String(describing: error))
      }
    }
  }

  func refreshFakePlayerMetadata() {
    let path = resolvedPlayerPath()
    playerApp = path
    fakePlayer[MPMediaItemPropertyTitle] = (path as NSString).lastPathComponent
    let targetSize = FakeArtwork.size
    let miniSize = CGSize(width: targetSize.width / 2, height: targetSize.height / 2)
    let playerAppPath = path

    fakePlayer[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: targetSize) { _ in
      let icon = NSWorkspace.shared.icon(forFile: playerAppPath)
      let frame = NSRect(origin: .zero, size: miniSize)
      guard let rep = icon.bestRepresentation(for: frame, context: nil, hints: nil) else {
        return NSImage(size: targetSize)
      }

      let iconImage = NSImage(size: rep.size)
      iconImage.addRepresentation(rep)

      return NSImage(size: targetSize, flipped: false) { rect in
        let dark = [NSAppearance.Name.darkAqua, NSAppearance.Name.vibrantDark]
          .contains(NSApp.effectiveAppearance.name)
        (dark ? FakeArtwork.darkBackground : FakeArtwork.lightBackground).drawSwatch(in: rect)
        iconImage.draw(
          in: CGRect(
            origin: CGPoint(x: miniSize.width / 2, y: miniSize.height / 2),
            size: miniSize
          )
        )
        return true
      }
    }
  }

  func refreshNowPlaying() {
    guard isHoldingNowPlaying else { return }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = fakePlayer
  }

  func writeSettings() {
    UserDefaults.standard.set(ignoreMediaKey, forKey: SettingsKey.ignoreMediaKey)
    UserDefaults.standard.set(playerApp, forKey: SettingsKey.playerApp)
    UserDefaults.standard.set(playerPreset.rawValue, forKey: SettingsKey.playerPreset)
    UserDefaults.standard.set(customPlayerAppPath, forKey: SettingsKey.customPlayerApp)
  }

  private func loadPersistedSettings() {
    ignoreMediaKey = UserDefaults.standard.bool(forKey: SettingsKey.ignoreMediaKey)
    customPlayerAppPath = UserDefaults.standard.string(forKey: SettingsKey.customPlayerApp)

    if let raw = UserDefaults.standard.string(forKey: SettingsKey.playerPreset),
      let preset = MusicPlayerPreset(rawValue: raw)
    {
      playerPreset = preset
    } else if let legacyPath = UserDefaults.standard.string(forKey: SettingsKey.playerApp) {
      if let matched = MusicPlayerPreset.matchingBuiltIn(path: legacyPath) {
        playerPreset = matched
      } else {
        playerPreset = .custom
        customPlayerAppPath = legacyPath
      }
    }

    playerApp = resolvedPlayerPath()
  }

  private func loadSongInfo() {
    mediaRemote.fetchPlaybackOwner { [weak self] isPlaying, pid in
      guard let self else { return }
      let myPID = Int32(ProcessInfo.processInfo.processIdentifier)
      if isPlaying && pid != myPID {
        self.relinquishNowPlaying()
        return
      }

      self.mediaRemote.currentClientBundleIdentifier { [weak self] clientBundle in
        guard let self else { return }
        if let clientBundle, clientBundle != self.ownBundleID {
          self.relinquishNowPlaying()
        } else {
          self.reclaimNowPlaying()
        }
      }
    }
  }

  private func relinquishNowPlaying() {
    isHoldingNowPlaying = false
    let commandCenter = MPRemoteCommandCenter.shared()
    let infoCenter = MPNowPlayingInfoCenter.default()
    commandCenter.togglePlayPauseCommand.isEnabled = false
    commandCenter.playCommand.isEnabled = false
    infoCenter.nowPlayingInfo = nil
    infoCenter.playbackState = .stopped
  }

  private func reclaimNowPlaying() {
    isHoldingNowPlaying = true
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.playCommand.isEnabled = true
    refreshNowPlaying()
  }

  @objc private func interfaceModeChanged(sender: NSNotification) {
    refreshFakePlayerMetadata()
    if isHoldingNowPlaying {
      refreshNowPlaying()
    }
  }

  private func enableLaunchAtLoginIfNeeded() {
    let service = SMAppService.mainApp
    guard service.status != .enabled else { return }
    do {
      try service.register()
    } catch {
      NSLog("AntiMusic: failed to enable launch at login: %@", String(describing: error))
    }
  }
}

extension AppDelegate: StatusItemControllerDelegate {
  func selectPlayerPreset(_ preset: MusicPlayerPreset) {
    applyPlayerPreset(preset)
  }

  func selectCustomPlayer(path: String) {
    applyPlayerPreset(.custom, customPath: path)
  }
}

extension AppDelegate: SettingsViewDelegate {}
