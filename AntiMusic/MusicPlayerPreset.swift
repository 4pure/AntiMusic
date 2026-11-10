//
// MusicPlayerPreset.swift
// AntiMusic
//

import Foundation

enum MusicPlayerPreset: String, CaseIterable {
  case appleMusic
  case netease
  case qishui
  case qqMusic
  case custom

  var displayName: String {
    switch self {
    case .appleMusic: return "音乐"
    case .netease: return "网易云音乐"
    case .qishui: return "汽水音乐"
    case .qqMusic: return "QQ音乐"
    case .custom: return "自定义"
    }
  }

  /// Built-in presets only (excludes `.custom`).
  static var builtIn: [MusicPlayerPreset] {
    [.appleMusic, .netease, .qishui, .qqMusic]
  }

  var candidatePaths: [String] {
    switch self {
    case .appleMusic:
      return ["/System/Applications/Music.app"]
    case .netease:
      return [
        "/Applications/NeteaseMusic.app",
        "/Applications/网易云音乐.app",
      ]
    case .qishui:
      return [
        "/Applications/汽水音乐.app",
        "/Applications/SodaMusic.app",
      ]
    case .qqMusic:
      return [
        "/Applications/QQMusic.app",
        "/Applications/QQ音乐.app",
      ]
    case .custom:
      return []
    }
  }

  func resolvedPath(customPath: String?) -> String? {
    switch self {
    case .custom:
      guard let customPath, !customPath.isEmpty else { return nil }
      return customPath
    default:
      return candidatePaths.first { FileManager.default.fileExists(atPath: $0) }
        ?? candidatePaths.first
    }
  }

  static func matchingBuiltIn(path: String) -> MusicPlayerPreset? {
    let standardized = (path as NSString).standardizingPath
    for preset in builtIn {
      for candidate in preset.candidatePaths {
        if (candidate as NSString).standardizingPath == standardized {
          return preset
        }
      }
    }
    return nil
  }
}

enum SettingsKey {
  static let ignoreMediaKey = "org.nift4.AntiMusic.IgnoreMediaKey"
  static let playerApp = "org.nift4.AntiMusic.PlayerApp"
  static let playerPreset = "org.nift4.AntiMusic.PlayerPreset"
  static let customPlayerApp = "org.nift4.AntiMusic.CustomPlayerApp"
}
