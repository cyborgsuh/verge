import Cocoa
import ServiceManagement

// Branded AppKit Preferences window. Reads/writes the same UserDefaults keys the
// gesture engine reads live ("enabled", "swapSides", "edgeZone", "stepTravel"),
// so every change applies immediately (no restart).

// MARK: - Brand

private let vergePink      = NSColor(srgbRed: 1.00, green: 0.180, blue: 0.494, alpha: 1) // #FF2E7E
private let vergePinkLight = NSColor(srgbRed: 1.00, green: 0.435, blue: 0.710, alpha: 1) // #FF6FB5

// Thin rounded pink gradient bar (header accent).
private final class AccentBar: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 4) }
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
            : NSColor(white: 0, alpha: 0.040)
    }
    override func draw(_ dirtyRect: NSRect) {
        CardView.fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        let stroke = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        stroke.lineWidth = 1
        stroke.stroke()
    }
}

// MARK: - Controller

final class PreferencesController: NSObject, NSWindowDelegate {
    static let shared = PreferencesController()

    private let d = UserDefaults.standard
    private var window: NSWindow?
    private var edgeReadout: NSTextField!
    private var sensReadout: NSTextField!

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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Verge"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false          // we reuse this instance
        w.delegate = self

        let fx = NSVisualEffectView()
        fx.material = .underWindowBackground
        fx.blendingMode = .behindWindow
        fx.state = .active
        w.contentView = fx

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(content)
        let contentWidth: CGFloat = 372
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: fx.topAnchor, constant: 34),
            content.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 24),
            content.widthAnchor.constraint(equalToConstant: contentWidth),
        ])

        // ---- Header: icon + wordmark + accent bar + tagline
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 58).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let name = NSTextField(labelWithString: "Verge")
        name.font = .systemFont(ofSize: 26, weight: .bold)

        let tagline = NSTextField(labelWithString: "Slide the verge.")
        tagline.font = .systemFont(ofSize: 13, weight: .medium)
        tagline.textColor = .secondaryLabelColor

        let titleCol = NSStackView(views: [name, AccentBar(), tagline])
        titleCol.orientation = .vertical
        titleCol.alignment = .leading
        titleCol.spacing = 4

        let header = NSStackView(views: [iconView, titleCol])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        content.addArrangedSubview(header)
        content.setCustomSpacing(20, after: header)

        // ---- General
        let enableSwitch = NSSwitch()
        enableSwitch.target = self
        enableSwitch.action = #selector(toggleEnabled(_:))
        enableSwitch.state = boolDefault("enabled", true) ? .on : .off
        let enableRow = labeledRow("Enable Verge", control: enableSwitch)

        let seg = NSSegmentedControl(labels: ["Brightness", "Volume"],
                                     trackingMode: .selectOne,
                                     target: self, action: #selector(changeSide(_:)))
        seg.selectedSegment = d.bool(forKey: "swapSides") ? 1 : 0
        seg.selectedSegmentBezelColor = vergePink
        let sideRow = labeledRow("Left edge controls", control: seg)

        let loginSwitch = NSSwitch()
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin(_:))
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let loginRow = labeledRow("Open at Login", control: loginSwitch)

        addSection("General", readout: nil,
                   card: card([enableRow, sideRow,
                               caption("The right edge controls the other one."),
                               loginRow]),
                   to: content, width: contentWidth)

        // ---- Edge zone  <-> "edgeZone" (0.04 is the reachable floor — never below)
        edgeReadout = readoutLabel()
        let edgeSlider = NSSlider(value: clamp(doubleDefault("edgeZone", 0.045), 0.04, 0.10),
                                  minValue: 0.04, maxValue: 0.10,
                                  target: self, action: #selector(changeEdge(_:)))
        edgeSlider.isContinuous = true
        edgeSlider.trackFillColor = vergePink
        addSection("Edge Zone", readout: edgeReadout,
                   card: card([sliderRow("Closer to edge", edgeSlider, "Farther in"),
                               caption("How far from the trackpad edge Verge listens.")]),
                   to: content, width: contentWidth)
        updateEdgeReadout(edgeSlider.doubleValue)

        // ---- Sensitivity  <-> "stepTravel"
        sensReadout = readoutLabel()
        let sensSlider = NSSlider(value: clamp(doubleDefault("stepTravel", 0.05), 0.02, 0.12),
                                  minValue: 0.02, maxValue: 0.12,
                                  target: self, action: #selector(changeSens(_:)))
        sensSlider.isContinuous = true
        sensSlider.trackFillColor = vergePink
        addSection("Sensitivity", readout: sensReadout,
                   card: card([sliderRow("Fine", sensSlider, "Coarse"),
                               caption("Finger travel needed for one volume/brightness step.")]),
                   to: content, width: contentWidth)
        updateSensReadout(sensSlider.doubleValue)

        // ---- Footer
        let footer = caption("Slide along the trackpad edge — up raises, down lowers.")
        content.addArrangedSubview(footer)

        // Size the window to fit the content (top inset + content + bottom pad).
        content.layoutSubtreeIfNeeded()
        let h = content.fittingSize.height + 34 + 22
        w.setContentSize(NSSize(width: 420, height: h))
        w.center()
        window = w
    }

    // MARK: actions (write the key immediately)

    @objc private func toggleEnabled(_ s: NSSwitch) {
        d.set(s.state == .on, forKey: "enabled")
    }

    @objc private func changeSide(_ s: NSSegmentedControl) {
        d.set(s.selectedSegment == 1, forKey: "swapSides")   // Volume selected = swapped
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

    private func addSection(_ title: String, readout: NSTextField?, card: NSView,
                            to content: NSStackView, width: CGFloat) {
        let head = NSStackView()
        head.orientation = .horizontal
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
        content.addArrangedSubview(card)
        content.setCustomSpacing(18, after: card)
        head.widthAnchor.constraint(equalToConstant: width).isActive = true
        card.widthAnchor.constraint(equalToConstant: width).isActive = true
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
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
    private func boolDefault(_ k: String, _ def: Bool) -> Bool { (d.object(forKey: k) as? Bool) ?? def }
    private func doubleDefault(_ k: String, _ def: Double) -> Double { (d.object(forKey: k) as? Double) ?? def }
}
