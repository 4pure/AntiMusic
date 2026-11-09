//
// ViewController.swift
// AntiMusic
//
// Created by nift4 on 09.12.2023.
//

import Cocoa
import UniformTypeIdentifiers

public class ViewController: NSViewController {

    @IBOutlet weak var button: NSButton!
    @IBOutlet weak var label: NSTextField!
    @IBOutlet weak var checkbox: NSButton!
    var delegate: AppDelegate?
    private var hasOpenPanel = false

    @IBAction func onPressChange(sender: NSButton) {
        guard delegate != nil, !hasOpenPanel else { return }

        let panel = NSOpenPanel()
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
            guard result == .OK, let url = panel.url, let delegate = self.delegate else { return }

            do {
                let resolved = try URL(resolvingAliasFileAt: url)
                delegate.playerApp = resolved.path
            } catch {
                NSLog("AntiMusic: failed parsing URL %@: %@", url.absoluteString, String(describing: error))
                return
            }

            self.label.stringValue = delegate.playerApp
            delegate.writeSettings()
            delegate.refreshFakePlayerMetadata()
            delegate.refreshNowPlaying()
        }
    }

    @IBAction func onToggleIgnore(sender: NSButton) {
        guard !hasOpenPanel else { return }
        delegate?.ignoreMediaKey = sender.state == .on
        delegate?.writeSettings()
    }
}

// https://stackoverflow.com/a/24590678
extension NSView {
    var parentViewController: NSViewController? {
        var parentResponder: NSResponder? = nextResponder
        while let responder = parentResponder {
            if let viewController = responder as? NSViewController {
                return viewController
            }
            parentResponder = responder.nextResponder
        }
        return nil
    }
}
