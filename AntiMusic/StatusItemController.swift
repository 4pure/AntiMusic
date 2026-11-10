//
// StatusItemController.swift
// AntiMusic
//

import AppKit
import UniformTypeIdentifiers

@MainActor
protocol StatusItemControllerDelegate: AnyObject {
  var ignoreMediaKey: Bool { get }
  var playerPreset: MusicPlayerPreset { get }
  var customPlayerAppPath: String? { get }

  func resolvedPlayerPath() -> String
  func selectPlayerPreset(_ preset: MusicPlayerPreset)
  func selectCustomPlayer(path: String)
  func setIgnoreMediaKey(_ value: Bool)
  func openPreferredPlayer()
  func openSettings()
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
  weak var delegate: StatusItemControllerDelegate?

  private let statusItem: NSStatusItem
  private let statusMenu = NSMenu()

  override init() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "AntiMusic")
      button.image?.isTemplate = true
    }

    statusMenu.delegate = self
    statusItem.menu = statusMenu
    rebuildMenu()
  }

  func reloadMenu() {
    rebuildMenu()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    if menu == statusMenu {
      rebuildMenu()
    }
  }

  private func rebuildMenu() {
    statusMenu.removeAllItems()
    guard let delegate else { return }

    let playerRoot = NSMenuItem(title: "默认播放器", action: nil, keyEquivalent: "")
    let playerMenu = NSMenu(title: "默认播放器")
    for preset in MusicPlayerPreset.builtIn {
      let item = NSMenuItem(
        title: preset.displayName,
        action: #selector(selectPreset(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = preset.rawValue
      item.state = delegate.playerPreset == preset ? .on : .off
      playerMenu.addItem(item)
    }

    if let customPath = delegate.customPlayerAppPath, !customPath.isEmpty {
      let name = (customPath as NSString).lastPathComponent
      let item = NSMenuItem(
        title: "自定义（\(name)）",
        action: #selector(selectCustomPreset(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.state = delegate.playerPreset == .custom ? .on : .off
      playerMenu.addItem(item)
    }

    playerMenu.addItem(.separator())
    let pickItem = NSMenuItem(
      title: "选取其他应用…",
      action: #selector(pickCustomApp(_:)),
      keyEquivalent: ""
    )
    pickItem.target = self
    playerMenu.addItem(pickItem)
    playerRoot.submenu = playerMenu
    statusMenu.addItem(playerRoot)

    let openPlayerItem = NSMenuItem(
      title: "打开默认播放器",
      action: #selector(openPreferredPlayer(_:)),
      keyEquivalent: ""
    )
    openPlayerItem.target = self
    statusMenu.addItem(openPlayerItem)

    let ignoreItem = NSMenuItem(
      title: "屏蔽媒体键操作",
      action: #selector(toggleIgnoreMediaKey(_:)),
      keyEquivalent: ""
    )
    ignoreItem.target = self
    ignoreItem.state = delegate.ignoreMediaKey ? .on : .off
    statusMenu.addItem(ignoreItem)

    statusMenu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: "设置",
      action: #selector(openSettings(_:)),
      keyEquivalent: ","
    )
    settingsItem.target = self
    statusMenu.addItem(settingsItem)

    let quitItem = NSMenuItem(
      title: "退出 AntiMusic",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    statusMenu.addItem(quitItem)
  }

  @objc private func selectPreset(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String,
      let preset = MusicPlayerPreset(rawValue: raw)
    else { return }
    delegate?.selectPlayerPreset(preset)
  }

  @objc private func selectCustomPreset(_ sender: NSMenuItem) {
    guard let path = delegate?.customPlayerAppPath, !path.isEmpty else { return }
    delegate?.selectCustomPlayer(path: path)
  }

  @objc private func pickCustomApp(_ sender: NSMenuItem) {
    let panel = NSOpenPanel()
    panel.message = "选择要用于媒体键的音乐播放器应用"
    panel.prompt = "选择"
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.allowedContentTypes = [.application]
    panel.level = .floating

    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let resolved = try URL(resolvingAliasFileAt: url)
      delegate?.selectCustomPlayer(path: resolved.path)
    } catch {
      NSLog(
        "AntiMusic: failed picking custom app %@: %@", url.absoluteString, String(describing: error)
      )
    }
  }

  @objc private func toggleIgnoreMediaKey(_ sender: NSMenuItem) {
    guard let delegate else { return }
    delegate.setIgnoreMediaKey(!delegate.ignoreMediaKey)
  }

  @objc private func openPreferredPlayer(_ sender: NSMenuItem) {
    delegate?.openPreferredPlayer()
  }

  @objc private func openSettings(_ sender: NSMenuItem) {
    delegate?.openSettings()
  }
}
