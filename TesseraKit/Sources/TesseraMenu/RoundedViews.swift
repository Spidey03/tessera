import AppKit

/// Rounded, appearance-aware container used for the Settings window's inputs,
/// search field and list boxes.
///
/// Drawing with `NSBezierPath` + named `NSColor`s (rather than CALayer
/// background colors) keeps the fill and border correct when the system
/// appearance changes while the window is open.
@MainActor
class RoundedBox: NSView {
    var cornerRadius: CGFloat = 8
    var borderWidth: CGFloat = 1
    var fillColor: NSColor = .controlBackgroundColor
    var borderColor: NSColor = .separatorColor
    var contentInsets = NSEdgeInsets(top: 3, left: 7, bottom: 3, right: 7)

    private(set) var content: NSView?

    /// Wraps `view` so it fills the box, inset by `contentInsets`.
    func setContent(_ view: NSView) {
        content?.removeFromSuperview()
        content = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInsets.bottom),
        ])
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        fillColor.setFill()
        path.fill()
        if borderWidth > 0 {
            borderColor.setStroke()
            path.lineWidth = borderWidth
            path.stroke()
        }
    }

}

/// A borderless text field inside a `RoundedBox` — the Settings window's
/// standard input treatment. The field is wrapped rather than replaced so the
/// controller keeps its original reference (load/save read `stringValue`).
@MainActor
final class RoundedTextInput: RoundedBox {
    let textField: NSTextField

    convenience init(font: NSFont = .systemFont(ofSize: 13),
                     alignment: NSTextAlignment = .left,
                     placeholder: String? = nil) {
        self.init(wrapping: NSTextField(string: ""), font: font, placeholder: placeholder)
        textField.alignment = alignment
    }

    init(wrapping field: NSTextField,
         font: NSFont = .systemFont(ofSize: 13),
         placeholder: String? = nil) {
        textField = field
        super.init(frame: .zero)
        cornerRadius = 6
        contentInsets = NSEdgeInsets(top: 2, left: 7, bottom: 2, right: 7)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true

        field.isBezeled = false
        field.drawsBackground = false
        field.font = font
        if let placeholder {
            field.placeholderString = placeholder
        }
        setContent(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Rounded search field (magnifier glyph + borderless text field) matching the
/// input treatment above.
@MainActor
final class RoundedSearchInput: RoundedBox {
    let searchField = NSSearchField()

    init(placeholder: String = "Search") {
        super.init(frame: .zero)
        cornerRadius = 6
        contentInsets = NSEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 26).isActive = true

        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.font = .systemFont(ofSize: 13)
        searchField.placeholderString = placeholder
        searchField.usesSingleLineMode = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [icon, searchField])
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        setContent(row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Small rounded "capsule" behind a section title (Tiling, Animation, …).
@MainActor
final class SectionChip: RoundedBox {
    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        cornerRadius = 9
        fillColor = .controlBackgroundColor
        borderColor = .separatorColor
        contentInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)

        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor

        let row = NSStackView(views: [label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        setContent(row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
