//
// ViewController.swift
// AntiMusic
//
// Created by nift4 on 09.12.2023.
//

import Cocoa
import UniformTypeIdentifiers

@MainActor
protocol SettingsViewDelegate: AnyObject {
  var ignoreMediaKey: Bool { get }
  var playerPreset: MusicPlayerPreset { get }
  var customPlayerAppPath: String? { get }
  var playerApp: String { get }

  func applyPlayerPreset(_ preset: MusicPlayerPreset, customPath: String?)
  func setIgnoreMediaKey(_ value: Bool)
}

@MainActor
public final class ViewController: NSViewController {

  weak var delegate: SettingsViewDelegate?
  private(set) var hasOpenPanel = false

  private let playerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let changeButton = NSButton(title: "选取应用…", target: nil, action: nil)
  private let pathLabel = NSTextField(labelWithString: "")
  private let ignoreCheckbox = NSButton(
    checkboxWithTitle: "屏蔽媒体键 / 蓝牙「播放」操作",
    target: nil,
    action: nil
  )

  public override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 168))
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    buildUI()
    reloadFromDelegate()
  }

  func reloadFromDelegate() {
    rebuildPlayerPopup()
    pathLabel.stringValue = delegate?.playerApp ?? ""
    ignoreCheckbox.state = (delegate?.ignoreMediaKey == true) ? .on : .off
  }

  private func buildUI() {
    let playerTitle = NSTextField(labelWithString: "默认播放器")
    playerTitle.font = .systemFont(ofSize: 13, weight: .semibold)
    playerTitle.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(playerTitle)

    playerPopup.translatesAutoresizingMaskIntoConstraints = false
    playerPopup.target = self
    playerPopup.action = #selector(playerPopupChanged(_:))
    view.addSubview(playerPopup)

    changeButton.bezelStyle = .rounded
    changeButton.translatesAutoresizingMaskIntoConstraints = false
    changeButton.target = self
    changeButton.action = #selector(onPressChange(_:))
    view.addSubview(changeButton)

    pathLabel.font = .systemFont(ofSize: 11)
    pathLabel.textColor = .secondaryLabelColor
    pathLabel.lineBreakMode = .byTruncatingMiddle
    pathLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(pathLabel)

    ignoreCheckbox.translatesAutoresizingMaskIntoConstraints = false
    ignoreCheckbox.target = self
    ignoreCheckbox.action = #selector(onToggleIgnore(_:))
    view.addSubview(ignoreCheckbox)

    NSLayoutConstraint.activate([
      playerTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      playerTitle.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),

      playerPopup.leadingAnchor.constraint(equalTo: playerTitle.leadingAnchor),
      playerPopup.topAnchor.constraint(equalTo: playerTitle.bottomAnchor, constant: 8),
      playerPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),

      changeButton.leadingAnchor.constraint(equalTo: playerPopup.trailingAnchor, constant: 10),
      changeButton.centerYAnchor.constraint(equalTo: playerPopup.centerYAnchor),
      changeButton.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

      pathLabel.leadingAnchor.constraint(equalTo: playerTitle.leadingAnchor),
      pathLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      pathLabel.topAnchor.constraint(equalTo: playerPopup.bottomAnchor, constant: 8),

      ignoreCheckbox.leadingAnchor.constraint(equalTo: playerTitle.leadingAnchor),
      ignoreCheckbox.trailingAnchor.constraint(
        lessThanOrEqualTo: view.trailingAnchor, constant: -20),
      ignoreCheckbox.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 16),
      ignoreCheckbox.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
    ])
  }

  private func rebuildPlayerPopup() {
    playerPopup.removeAllItems()
    var selectedIndex = 0

    for (index, preset) in MusicPlayerPreset.builtIn.enumerated() {
      playerPopup.addItem(withTitle: preset.displayName)
      playerPopup.item(at: index)?.representedObject = preset.rawValue
      if delegate?.playerPreset == preset {
        selectedIndex = index
      }
    }

    if let customPath = delegate?.customPlayerAppPath, !customPath.isEmpty {
      let title = "自定义（\((customPath as NSString).lastPathComponent)）"
      playerPopup.addItem(withTitle: title)
      let index = playerPopup.numberOfItems - 1
      playerPopup.item(at: index)?.representedObject = MusicPlayerPreset.custom.rawValue
      if delegate?.playerPreset == .custom {
        selectedIndex = index
      }
    }

    playerPopup.selectItem(at: selectedIndex)
  }

  @objc private func playerPopupChanged(_ sender: NSPopUpButton) {
    guard let raw = sender.selectedItem?.representedObject as? String,
      let preset = MusicPlayerPreset(rawValue: raw)
    else { return }
    if preset == .custom {
      guard let path = delegate?.customPlayerAppPath else { return }
      delegate?.applyPlayerPreset(.custom, customPath: path)
    } else {
      delegate?.applyPlayerPreset(preset, customPath: nil)
    }
    pathLabel.stringValue = delegate?.playerApp ?? ""
  }

  @objc private func onPressChange(_ sender: NSButton) {
    guard delegate != nil, !hasOpenPanel else { return }

    let panel = NSOpenPanel()
    panel.message = "选择要用于媒体键与控制中心「正在播放」的音乐播放器应用"
    panel.prompt = "选择"
    panel.showsResizeIndicator = true
    panel.allowsMultipleSelection = false
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.allowedContentTypes = [.application]

    hasOpenPanel = true
    panel.begin { [weak self] result in
      guard let self else { return }
      self.hasOpenPanel = false
      guard result == .OK, let url = panel.url else { return }

      do {
        let resolved = try URL(resolvingAliasFileAt: url)
        self.delegate?.applyPlayerPreset(.custom, customPath: resolved.path)
      } catch {
        NSLog("AntiMusic: failed parsing URL %@: %@", url.absoluteString, String(describing: error))
        return
      }

      self.reloadFromDelegate()
    }
  }

  @objc private func onToggleIgnore(_ sender: NSButton) {
    guard !hasOpenPanel else { return }
    delegate?.setIgnoreMediaKey(sender.state == .on)
  }
}
