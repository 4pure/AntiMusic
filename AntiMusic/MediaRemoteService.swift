//
// MediaRemoteService.swift
// AntiMusic
//
// Detects whether another app currently owns playback so AntiMusic can
// reclaim / release the media-key Now Playing slot.
//

import Foundation

@MainActor
final class MediaRemoteService {
  private typealias GetNowPlayingClient =
    @convention(c) (DispatchQueue, @escaping (AnyObject) -> Void) -> Void
  private typealias GetBundleIdentifier = @convention(c) (AnyObject?) -> String
  private typealias RegisterForNotifications = @convention(c) (DispatchQueue) -> Void
  private typealias GetIsPlaying =
    @convention(c) (DispatchQueue, @escaping (ObjCBool) -> Void) -> Void
  private typealias GetPID = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void

  private let getNowPlayingClient: GetNowPlayingClient
  private let getBundleIdentifier: GetBundleIdentifier
  private let registerForNotifications: RegisterForNotifications
  private let getIsPlaying: GetIsPlaying
  private let getPID: GetPID
  private var infoObservers: [NSObjectProtocol] = []

  init() {
    let loaded = Self.loadSymbols()
    getNowPlayingClient = loaded.getNowPlayingClient
    getBundleIdentifier = loaded.getBundleIdentifier
    registerForNotifications = loaded.registerForNotifications
    getIsPlaying = loaded.getIsPlaying
    getPID = loaded.getPID
  }

  deinit {
    for observer in infoObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func start() {
    registerForNotifications(DispatchQueue.main)
  }

  func onNowPlayingChanged(_ handler: @escaping @MainActor () -> Void) {
    let names = [
      "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
      "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
      "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    ]
    for name in names {
      let token = NotificationCenter.default.addObserver(
        forName: NSNotification.Name(name),
        object: nil,
        queue: .main
      ) { _ in
        Task { @MainActor in
          handler()
        }
      }
      infoObservers.append(token)
    }
  }

  func fetchPlaybackOwner(
    completion: @escaping @MainActor (_ isPlaying: Bool, _ pid: Int32) -> Void
  ) {
    getIsPlaying(DispatchQueue.main) { [weak self] playingFlag in
      guard let self else { return }
      self.getPID(DispatchQueue.main) { pid in
        Task { @MainActor in
          completion(playingFlag.boolValue, pid)
        }
      }
    }
  }

  func currentClientBundleIdentifier(completion: @escaping @MainActor (String?) -> Void) {
    getNowPlayingClient(DispatchQueue.main) { [weak self] client in
      guard let self else { return }
      let value = self.getBundleIdentifier(client)
      let bundleID = value.trimmingCharacters(in: .whitespacesAndNewlines)
      Task { @MainActor in
        completion(bundleID.isEmpty ? nil : bundleID)
      }
    }
  }

  private static func loadSymbols() -> (
    getNowPlayingClient: GetNowPlayingClient,
    getBundleIdentifier: GetBundleIdentifier,
    registerForNotifications: RegisterForNotifications,
    getIsPlaying: GetIsPlaying,
    getPID: GetPID
  ) {
    let handle = dlopen(
      "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
      RTLD_NOW
    )
    func require(_ name: String) -> UnsafeMutableRawPointer {
      guard let pointer = dlsym(handle, name) else {
        fatalError("AntiMusic: MediaRemote symbol missing: \(name)")
      }
      return pointer
    }
    return (
      unsafeBitCast(require("MRMediaRemoteGetNowPlayingClient"), to: GetNowPlayingClient.self),
      unsafeBitCast(require("MRNowPlayingClientGetBundleIdentifier"), to: GetBundleIdentifier.self),
      unsafeBitCast(
        require("MRMediaRemoteRegisterForNowPlayingNotifications"),
        to: RegisterForNotifications.self),
      unsafeBitCast(
        require("MRMediaRemoteGetNowPlayingApplicationIsPlaying"), to: GetIsPlaying.self),
      unsafeBitCast(require("MRMediaRemoteGetNowPlayingApplicationPID"), to: GetPID.self)
    )
  }
}
