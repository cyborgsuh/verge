import Cocoa
import ServiceManagement

// Branded AppKit Preferences window: sidebar (General / Slide) + one page
// at a time. Reads/writes the same UserDefaults keys the gesture engines read live,
// so every change applies immediately (no restart).

// MARK: - Brand

private let vergePink      = NSColor(srgbRed: 1.00, green: 0.180, blue: 0.494, alpha: 1) // #FF2E7E
private let vergePinkLight = NSColor(srgbRed: 1.00, green: 0.435, blue: 0.710, alpha: 1) // #FF6FB5

// Thin rounded pink gradient bar (page-title accent).
private final class AccentBar: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 3) }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSGradient(starting: vergePink, ending: vergePinkLight)?.draw(in: path, angle: 0)
    }
}

// Rounded "card" behind each settings group. draw(_:) resolves the dynamic
// colors per appearance, so it adapts to light/dark automatically.
private final class CardView: NSView {
    private static let fill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.055)
            : NSColor(white: 1, alpha: 0.70)
    }
    override func draw(_ dirtyRect: NSRect) {
        CardView.fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        let stroke = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        stroke.lineWidth = 1
        stroke.stroke()
    }
}

// Sidebar entry: SF Symbol + title, pink pill when selected.
private final class SidebarItem: NSView {
    var onClick: (() -> Void)?
    var selected = false { didSet { needsDisplay = true; refresh() } }
    private let icon = NSImageView()
    private let label: NSTextField

    init(title: String, symbol: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        icon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let row = NSStackView(views: [icon, label])
        row.spacing = 9
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        icon.contentTintColor = selected ? .white : vergePink
        label.textColor = selected ? .white : .labelColor
    }
    override func draw(_ dirtyRect: NSRect) {
        guard selected else { return }
        NSGradient(starting: vergePink, ending: vergePinkLight)?
            .draw(in: NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7), angle: 0)
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

// MARK: - Controller

final class PreferencesController: NSObject, NSWindowDelegate {
    static let shared = PreferencesController()

    private let d = UserDefaults.standard
    private var window: NSWindow?
    private var edgeReadout: NSTextField!
    private var sensReadout: NSTextField!
    private var items: [SidebarItem] = []
    private var pages: [NSView] = []
    private var pageHost = NSView()

    private let pageWidth: CGFloat = 440

    // Bring the window forward from an .accessory (no-Dock) app.
    func show() {
        if window == nil { build() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)   // back to menu-bar-only
    }

    // MARK: build (lazy, one instance)

    private func build() {
        let sidebarWidth: CGFloat = 196
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: sidebarWidth + pageWidth + 56, height: 500),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Verge"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false          // we reuse this instance
        w.delegate = self

        let root = NSView()
        w.contentView = root

        // ---- Sidebar
        let side = NSVisualEffectView()
        side.material = .sidebar
        side.blendingMode = .behindWindow
        side.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(side)

        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 40).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let name = NSTextField(labelWithString: "Verge")
        name.font = .systemFont(ofSize: 17, weight: .bold)
        let version = NSTextField(labelWithString:
            "v" + ((Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"))
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        let nameCol = NSStackView(views: [name, version])
        nameCol.orientation = .vertical
        nameCol.alignment = .leading
        nameCol.spacing = 1
        let brand = NSStackView(views: [iconView, nameCol])
        brand.spacing = 10

        items = [("General", "gearshape"), ("Slide", "hand.draw")].map {
            SidebarItem(title: $0.0, symbol: $0.1)
        }
        let list = NSStackView(views: items)
        list.orientation = .vertical
        list.spacing = 2
        let sideStack = NSStackView(views: [brand, list])
        sideStack.orientation = .vertical
        sideStack.alignment = .leading
        sideStack.spacing = 22
        sideStack.translatesAutoresizingMaskIntoConstraints = false
        side.addSubview(sideStack)
        for it in items { it.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }

        // ---- Page host
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pageHost)

        NSLayoutConstraint.activate([
            side.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            side.topAnchor.constraint(equalTo: root.topAnchor),
            side.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            side.widthAnchor.constraint(equalToConstant: sidebarWidth),
            sideStack.topAnchor.constraint(equalTo: side.topAnchor, constant: 46),
            sideStack.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 14),
            sideStack.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -14),
            list.widthAnchor.constraint(equalTo: sideStack.widthAnchor),
            pageHost.leadingAnchor.constraint(equalTo: side.trailingAnchor, constant: 28),
            pageHost.topAnchor.constraint(equalTo: root.topAnchor, constant: 40),
            pageHost.widthAnchor.constraint(equalToConstant: pageWidth),
            // must have real height: controls drawn outside it would render but never get clicks
            pageHost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        pages = [generalPage(), slidePage()]
        for (i, it) in items.enumerated() { it.onClick = { [weak self] in self?.select(i) } }

        // Size to the tallest page so switching never resizes the window.
        let tallest = pages.map { $0.fittingSize.height }.max() ?? 400
        w.setContentSize(NSSize(width: sidebarWidth + pageWidth + 56, height: tallest + 40 + 28))
        w.center()
        window = w
        select(min(max(d.integer(forKey: "prefsPage"), 0), pages.count - 1))

    }

    private func select(_ i: Int) {
        for (j, it) in items.enumerated() { it.selected = j == i }
        pageHost.subviews.forEach { $0.removeFromSuperview() }
        let p = pages[i]
        p.translatesAutoresizingMaskIntoConstraints = false
        pageHost.addSubview(p)
        NSLayoutConstraint.activate([
            p.topAnchor.constraint(equalTo: pageHost.topAnchor),
            p.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
            p.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
        ])
        d.set(i, forKey: "prefsPage")
    }

    // MARK: pages

    private func generalPage() -> NSView {
        let enableSwitch = NSSwitch()
        enableSwitch.target = self
        enableSwitch.action = #selector(toggleEnabled(_:))
        enableSwitch.state = boolDefault("enabled", true) ? .on : .off

        let loginSwitch = NSSwitch()
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin(_:))
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off

        return page("General", "Verge lives in your menu bar.", sections: [
            (nil, nil, card([labeledRow("Enable Verge", control: enableSwitch),
                             labeledRow("Open at Login", control: loginSwitch)])),
            ("How it works", nil, card([
                caption("Slide one finger along a trackpad edge: up raises, down lowers."),
            ])),
        ])
    }

    private func slidePage() -> NSView {
        let seg = NSSegmentedControl(labels: ["Brightness", "Volume"],
                                     trackingMode: .selectOne,
                                     target: self, action: #selector(changeSide(_:)))
        seg.selectedSegment = d.bool(forKey: "swapSides") ? 1 : 0
        seg.selectedSegmentBezelColor = vergePink

        let scrubSwitch = NSSwitch()
        scrubSwitch.target = self
        scrubSwitch.action = #selector(toggleScrub(_:))
        scrubSwitch.state = boolDefault("topScrub", true) ? .on : .off

        let backlightPop = NSPopUpButton()
        backlightPop.addItems(withTitles: ["Off", "⌘ Command", "⌥ Option", "⌃ Control", "⇧ Shift"])
        backlightPop.selectItem(at: Self.backlightKeys.firstIndex(
            of: d.string(forKey: "backlightModifier") ?? "command") ?? 1)
        backlightPop.target = self
        backlightPop.action = #selector(changeBacklightModifier(_:))

        // "edgeZone" (0.04 is the reachable floor — never below)
        edgeReadout = readoutLabel()
        let edgeSlider = NSSlider(value: clamp(doubleDefault("edgeZone", 0.045), 0.04, 0.10),
                                  minValue: 0.04, maxValue: 0.10,
                                  target: self, action: #selector(changeEdge(_:)))
        edgeSlider.trackFillColor = vergePink
        updateEdgeReadout(edgeSlider.doubleValue)

        // "stepTravel"
        sensReadout = readoutLabel()
        let sensSlider = NSSlider(value: clamp(doubleDefault("stepTravel", 0.05), 0.02, 0.12),
                                  minValue: 0.02, maxValue: 0.12,
                                  target: self, action: #selector(changeSens(_:)))
        sensSlider.trackFillColor = vergePink
        updateSensReadout(sensSlider.doubleValue)

        return page("Slide", "Trackpad edges for volume, brightness and video.", sections: [
            ("Edges", nil, card([labeledRow("Left edge controls", control: seg),
                                 caption("The right edge controls the other one."),
                                 labeledRow("Video scrub (top edge)", control: scrubSwitch),
                                 caption("1s in native players. Browsers scrub in ~5s steps."),
                                 labeledRow("Keyboard backlight", control: backlightPop),
                                 caption("Hold this while sliding the brightness edge.")])),
            ("Edge zone", edgeReadout, card([sliderRow("Closer", edgeSlider, "Farther in")])),
            ("Step size", sensReadout, card([sliderRow("Fine", sensSlider, "Coarse")])),
        ])
    }

    // MARK: actions (write the key immediately)

    @objc private func toggleEnabled(_ s: NSSwitch) {
        d.set(s.state == .on, forKey: "enabled")
    }

    @objc private func changeSide(_ s: NSSegmentedControl) {
        d.set(s.selectedSegment == 1, forKey: "swapSides")   // Volume selected = swapped
    }

    @objc private func toggleScrub(_ s: NSSwitch) {
        d.set(s.state == .on, forKey: "topScrub")
    }

    // Popup order must match this list (index 0 = "Off").
    fileprivate static let backlightKeys = ["none", "command", "option", "control", "shift"]

    @objc private func changeBacklightModifier(_ p: NSPopUpButton) {
        let i = min(max(p.indexOfSelectedItem, 0), Self.backlightKeys.count - 1)
        d.set(Self.backlightKeys[i], forKey: "backlightModifier")
    }

    @objc private func toggleLogin(_ s: NSSwitch) {
        do {
            if s.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Verge: login toggle failed: \(error)")
            s.state = SMAppService.mainApp.status == .enabled ? .on : .off  // revert on failure
        }
    }

    @objc private func changeEdge(_ s: NSSlider) {
        d.set(s.doubleValue, forKey: "edgeZone")
        updateEdgeReadout(s.doubleValue)
    }

    @objc private func changeSens(_ s: NSSlider) {
        d.set(s.doubleValue, forKey: "stepTravel")
        updateSensReadout(s.doubleValue)
    }

    // MARK: view helpers

    private func updateEdgeReadout(_ v: Double) {
        edgeReadout.stringValue = String(format: "%.1f%% from edge", v * 100)
    }

    private func updateSensReadout(_ v: Double) {
        sensReadout.stringValue = String(format: "%.2f per step", v)
    }

    // Page = big title + accent + subtitle, then titled cards.
    private func page(_ title: String, _ subtitle: String,
                      sections: [(String?, NSTextField?, NSView)]) -> NSView {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8

        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 24, weight: .bold)
        content.addArrangedSubview(t)
        let bar = AccentBar()
        content.addArrangedSubview(bar)
        let sub = caption(subtitle)
        sub.font = .systemFont(ofSize: 12)
        content.addArrangedSubview(sub)
        content.setCustomSpacing(20, after: sub)

        for (title, readout, card) in sections {
            if let title {
                let head = NSStackView()
                head.spacing = 8
                let label = NSTextField(labelWithString: "")
                label.attributedStringValue = NSAttributedString(
                    string: title.uppercased(),
                    attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                 .foregroundColor: NSColor.secondaryLabelColor,
                                 .kern: 0.8])
                head.addArrangedSubview(label)
                if let readout {
                    let spacer = NSView()
                    spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
                    head.addArrangedSubview(spacer)
                    head.addArrangedSubview(readout)
                }
                content.addArrangedSubview(head)
                content.setCustomSpacing(6, after: head)
                head.widthAnchor.constraint(equalToConstant: pageWidth).isActive = true
            }
            content.addArrangedSubview(card)
            content.setCustomSpacing(18, after: card)
            card.widthAnchor.constraint(equalToConstant: pageWidth).isActive = true
        }
        return content
    }

    private func card(_ views: [NSView]) -> NSView {
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        // Full-width rows inside the card so switches/sliders reach the right edge.
        for v in views where v is NSStackView {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return card
    }

    private func labeledRow(_ title: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        row.addArrangedSubview(label)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(control)
        return row
    }

    private func sliderRow(_ minText: String, _ slider: NSSlider, _ maxText: String) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.distribution = .fill
        slider.isContinuous = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(endLabel(minText))
        row.addArrangedSubview(slider)
        row.addArrangedSubview(endLabel(maxText))
        return row
    }

    private func readoutLabel() -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        l.textColor = vergePink
        return l
    }

    private func endLabel(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func caption(_ t: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: t)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = pageWidth - 28
        return l
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
    private func boolDefault(_ k: String, _ def: Bool) -> Bool { (d.object(forKey: k) as? Bool) ?? def }
    private func doubleDefault(_ k: String, _ def: Double) -> Double { (d.object(forKey: k) as? Double) ?? def }
}
