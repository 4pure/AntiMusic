//
// AppDelegate.swift
// AntiMusic
//
// Created by nift4 on 08.12.2023.
//

import Cocoa
import MediaPlayer
import ServiceManagement

private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFunction = @convention(c) (DispatchQueue) -> Void
private typealias MRNowPlayingClientGetBundleIdentifierFunction = @convention(c) (AnyObject?) -> String
private typealias MRMediaRemoteGetNowPlayingClientFunction = @convention(c) (DispatchQueue, @escaping (AnyObject) -> Void) -> Void

private enum SettingsKey {
    static let ignoreMediaKey = "org.nift4.AntiMusic.IgnoreMediaKey"
    static let playerApp = "org.nift4.AntiMusic.PlayerApp"
}

private enum FakeArtwork {
    static let size = CGSize(width: 1024, height: 1024)
    static let lightBackground = NSColor(srgbRed: 0.8274509804, green: 0.8274509804, blue: 0.831372549, alpha: 1)
    static let darkBackground = NSColor(srgbRed: 0.3529411765, green: 0.3529411765, blue: 0.3764705882, alpha: 1)
}

@main
@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {

    private let mediaRemoteGetNowPlayingClient: MRMediaRemoteGetNowPlayingClientFunction
    private let mediaRemoteRegisterForNowPlayingNotifications: MRMediaRemoteRegisterForNowPlayingNotificationsFunction
    private let nowPlayingClientGetBundleIdentifier: MRNowPlayingClientGetBundleIdentifierFunction
    private let ownBundleIdentifier: String
    private var settingsVisible = false
    // Note: without title specified, we do not get to expanded Now Playing sheet.
    private var fakePlayer: [String: Any] = [MPMediaItemPropertyTitle: "<AntiMusic.app>"]

    // User-facing settings
    var ignoreMediaKey = false
    var playerApp = "/System/Applications/Music.app"

    public override init() {
        let mediaRemote = Self.loadMediaRemoteFunctions()
        mediaRemoteGetNowPlayingClient = mediaRemote.getNowPlayingClient
        mediaRemoteRegisterForNowPlayingNotifications = mediaRemote.registerForNowPlayingNotifications
        nowPlayingClientGetBundleIdentifier = mediaRemote.getBundleIdentifier
        ownBundleIdentifier = Bundle.main.bundleIdentifier ?? "org.nift4.AntiMusic"
        super.init()

        // Hack to "activate" media player as something that can show up in "Now Playing" (only needs to be done once)
        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.playbackState = .playing
        infoCenter.playbackState = .stopped

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            // Launch by Media Key / Bluetooth
            DispatchQueue.main.async {
                self?.handlePlay(fromControlCenter: false)
            }
            return .success
        }
        commandCenter.playCommand.addTarget { [weak self] _ in
            // Launch with Play button in Control Center / Siri
            DispatchQueue.main.async {
                self?.handlePlay(fromControlCenter: true)
            }
            return .success
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadSongInfo()
            }
        }
        mediaRemoteRegisterForNowPlayingNotifications(DispatchQueue.main)

        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(interfaceModeChanged(sender:)),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        ignoreMediaKey = UserDefaults.standard.bool(forKey: SettingsKey.ignoreMediaKey)
        playerApp = UserDefaults.standard.string(forKey: SettingsKey.playerApp) ?? playerApp
        refreshFakePlayerMetadata()
        loadSongInfo()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        enableLaunchAtLoginIfNeeded()
    }

    // When user opens app even though it already is open
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settingsVisible {
            return false
        }
        settingsVisible = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Hacky fix for menu bar not showing
        OperationQueue.main.addOperation {
            NSMenu.setMenuBarVisible(false)
            OperationQueue.main.addOperation {
                NSMenu.setMenuBarVisible(true)
            }
        }

        guard let window = NSApp.windows.first,
              let contentView = window.contentView,
              let controller = contentView.parentViewController as? ViewController else {
            NSLog("AntiMusic: settings window or ViewController missing")
            settingsVisible = false
            NSApp.setActivationPolicy(.accessory)
            return false
        }

        controller.delegate = self
        controller.label.stringValue = playerApp
        controller.checkbox.state = ignoreMediaKey ? .on : .off
        window.center()
        window.makeKeyAndOrderFront(NSApp)
        return false
    }

    public func applicationDidResignActive(_ notification: Notification) {
        NSApp.windows.first?.close()
        NSApp.setActivationPolicy(.accessory)
        settingsVisible = false
    }

    private func handlePlay(fromControlCenter: Bool) {
        if ignoreMediaKey && !fromControlCenter {
            return
        }
        let url = URL(fileURLWithPath: playerApp, isDirectory: true)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func refreshFakePlayerMetadata() {
        fakePlayer[MPMediaItemPropertyTitle] = (playerApp as NSString).lastPathComponent
        let targetSize = FakeArtwork.size
        let miniSize = CGSize(width: targetSize.width / 2, height: targetSize.height / 2)
        let playerAppPath = playerApp

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
        MPNowPlayingInfoCenter.default().nowPlayingInfo = fakePlayer
    }

    func writeSettings() {
        UserDefaults.standard.set(ignoreMediaKey, forKey: SettingsKey.ignoreMediaKey)
        UserDefaults.standard.set(playerApp, forKey: SettingsKey.playerApp)
    }

    private func loadSongInfo() {
        mediaRemoteGetNowPlayingClient(DispatchQueue.main) { [weak self] client in
            guard let self else { return }
            let commandCenter = MPRemoteCommandCenter.shared()
            let infoCenter = MPNowPlayingInfoCenter.default()
            let clientBundle = self.nowPlayingClientGetBundleIdentifier(client)

            // If there is a currently playing song and it's not our fake player, hide the fake player
            if clientBundle != self.ownBundleIdentifier {
                // Needs to be in this order for player to instantly disappear
                // Please note: If user is in full-sheet Now Playing, fake player won't disappear until reopening full-sheet.
                commandCenter.togglePlayPauseCommand.isEnabled = false
                commandCenter.playCommand.isEnabled = false
                infoCenter.nowPlayingInfo = nil
            } else {
                // If we are the only ones (*newest ones, but we autostart so we should be the oldest player at any given time),
                // show our fake player with user's preferred music player as icon and name.
                self.refreshNowPlaying()
                commandCenter.togglePlayPauseCommand.isEnabled = true
                commandCenter.playCommand.isEnabled = true
            }
        }
    }

    @objc private func interfaceModeChanged(sender: NSNotification) {
        refreshFakePlayerMetadata()
        refreshNowPlaying()
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

    private static func loadMediaRemoteFunctions() -> (
        getNowPlayingClient: MRMediaRemoteGetNowPlayingClientFunction,
        registerForNowPlayingNotifications: MRMediaRemoteRegisterForNowPlayingNotificationsFunction,
        getBundleIdentifier: MRNowPlayingClientGetBundleIdentifierFunction
    ) {
        let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        )
        guard
            let getNowPlayingClientPointer = CFBundleGetFunctionPointerForName(
                bundle,
                "MRMediaRemoteGetNowPlayingClient" as CFString
            ),
            let getBundleIdentifierPointer = CFBundleGetFunctionPointerForName(
                bundle,
                "MRNowPlayingClientGetBundleIdentifier" as CFString
            ),
            let registerPointer = CFBundleGetFunctionPointerForName(
                bundle,
                "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString
            )
        else {
            fatalError("AntiMusic: required MediaRemote private APIs unavailable")
        }

        return (
            unsafeBitCast(getNowPlayingClientPointer, to: MRMediaRemoteGetNowPlayingClientFunction.self),
            unsafeBitCast(registerPointer, to: MRMediaRemoteRegisterForNowPlayingNotificationsFunction.self),
            unsafeBitCast(getBundleIdentifierPointer, to: MRNowPlayingClientGetBundleIdentifierFunction.self)
        )
    }
}
