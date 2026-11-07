import AppKit

/// Borderless, non-activating floating panel. Never becomes key, so it never steals focus.
final class PreviewPanel: NSPanel {
    private let effect = NSVisualEffectView()
    private var tiles: [TileView] = []

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        contentView = effect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func clear() {
        tiles.forEach { $0.removeFromSuperview() } // drops all thumbnail images from memory
        tiles = []
        effect.subviews.forEach { $0.removeFromSuperview() }
    }

    func display(app: NSRunningApplication, windows: [WindowEntry], thumbnails: Bool, iconFrame: CGRect,
                 onSelect: @escaping (Int) -> Void, onClose: @escaping (Int) -> Void) {
        clear()
        let iconRect = AX.toCocoa(iconFrame)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: iconRect.midX, y: iconRect.midY)) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let edge = Self.dockEdge(icon: iconRect, screen: screen.frame)
        let visible = screen.visibleFrame

        let pad: CGFloat = 10, gap: CGFloat = 6, headerH: CGFloat = 22
        let tileSize = thumbnails ? CGSize(width: 220, height: 168) : CGSize(width: 300, height: 28)

        // Grid: thumbnails flow horizontally for a bottom Dock; text rows always stack vertically.
        let n = windows.count
        var cols: Int
        if !thumbnails {
            let maxRows = max(1, Int((visible.height - 2 * pad - headerH) / (tileSize.height + gap)))
            cols = Int(ceil(Double(n) / Double(maxRows)))
        } else if edge == .bottom {
            cols = max(1, min(n, Int((visible.width - 2 * pad) / (tileSize.width + gap))))
        } else {
            let maxRows = max(1, Int((visible.height - 2 * pad - headerH) / (tileSize.height + gap)))
            cols = Int(ceil(Double(n) / Double(maxRows)))
        }
        cols = max(1, cols)
        let rows = Int(ceil(Double(n) / Double(cols)))

        let width = 2 * pad + CGFloat(cols) * tileSize.width + CGFloat(cols - 1) * gap
        let height = 2 * pad + headerH + CGFloat(rows) * tileSize.height + CGFloat(rows - 1) * gap

        let header = NSTextField(labelWithString: app.localizedName ?? "")
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.frame = CGRect(x: pad + 4, y: height - pad - headerH + 2, width: width - 2 * pad - 8, height: 18)
        effect.addSubview(header)

        let appIcon = app.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!
        for (i, w) in windows.enumerated() {
            let col = i % cols, row = i / cols
            let x = pad + CGFloat(col) * (tileSize.width + gap)
            let y = height - pad - headerH - CGFloat(row + 1) * tileSize.height - CGFloat(row) * gap
            let tile = TileView(frame: CGRect(origin: CGPoint(x: x, y: y), size: tileSize),
                                title: w.title, minimized: w.minimized, icon: appIcon, thumbnailMode: thumbnails)
            tile.onClick = { onSelect(i) }
            tile.onClose = { onClose(i) }
            effect.addSubview(tile)
            tiles.append(tile)
        }

        let size = CGSize(width: width, height: height)
        setFrame(CGRect(origin: Self.origin(size: size, icon: iconRect, edge: edge, visible: visible), size: size), display: true)
        orderFrontRegardless()
    }

    func setThumbnails(_ images: [Int: CGImage]) {
        for (i, img) in images where i < tiles.count { tiles[i].setThumbnail(img) }
    }

    enum Edge { case bottom, left, right }

    private static func dockEdge(icon: CGRect, screen: CGRect) -> Edge {
        let b = icon.minY - screen.minY, l = icon.minX - screen.minX, r = screen.maxX - icon.maxX
        if b <= l && b <= r { return .bottom }
        return l < r ? .left : .right
    }

    private static func origin(size: CGSize, icon: CGRect, edge: Edge, visible: CGRect) -> CGPoint {
        let offset: CGFloat = 8
        var p: CGPoint
        switch edge {
        case .bottom: p = CGPoint(x: icon.midX - size.width / 2, y: icon.maxY + offset)
        case .left:   p = CGPoint(x: icon.maxX + offset, y: icon.midY - size.height / 2)
        case .right:  p = CGPoint(x: icon.minX - size.width - offset, y: icon.midY - size.height / 2)
        }
        p.x = min(max(p.x, visible.minX + 4), visible.maxX - size.width - 4)
        p.y = min(max(p.y, visible.minY + 4), visible.maxY - size.height - 4)
        return p
    }
}

/// One window in the preview: thumbnail (or icon) + title, with a hover close button.
final class TileView: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    private let imageView = NSImageView()
    private let label: NSTextField
    private let closeView = ClickableImageView()
    private let thumbnailMode: Bool
    private var tracking: NSTrackingArea?

    init(frame: CGRect, title: String, minimized: Bool, icon: NSImage, thumbnailMode: Bool) {
        self.thumbnailMode = thumbnailMode
        label = NSTextField(labelWithString: minimized ? "\(title) (minimized)" : title)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8

        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = minimized ? .secondaryLabelColor : .labelColor
        imageView.image = icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        if minimized { imageView.alphaValue = 0.5 }

        closeView.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close window")
        closeView.contentTintColor = .secondaryLabelColor
        closeView.isHidden = true
        closeView.onClick = { [weak self] in self?.onClose?() }

        let b = bounds
        if thumbnailMode {
            label.frame = CGRect(x: 8, y: 6, width: b.width - 16, height: 18)
            imageView.frame = CGRect(x: 8, y: 28, width: b.width - 16, height: b.height - 36)
            closeView.frame = CGRect(x: b.width - 24, y: b.height - 24, width: 18, height: 18)
        } else {
            imageView.frame = CGRect(x: 6, y: 5, width: 18, height: 18)
            label.frame = CGRect(x: 30, y: 5, width: b.width - 58, height: 18)
            closeView.frame = CGRect(x: b.width - 24, y: 5, width: 18, height: 18)
        }
        if thumbnailMode { imageView.frame = imageView.frame.insetBy(dx: 40, dy: 25) } // icon placeholder, smaller
        addSubview(imageView)
        addSubview(label)
        addSubview(closeView)
        toolTip = title
    }

    required init?(coder: NSCoder) { fatalError() }

    func setThumbnail(_ cg: CGImage) {
        let b = bounds
        imageView.frame = CGRect(x: 8, y: 28, width: b.width - 16, height: b.height - 36)
        imageView.image = NSImage(cgImage: cg, size: .zero)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        closeView.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
        closeView.isHidden = true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}

final class ClickableImageView: NSImageView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
}
