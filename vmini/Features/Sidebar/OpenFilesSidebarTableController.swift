import AppKit
import UniformTypeIdentifiers

@MainActor
final class OpenFilesSidebarTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    enum Constants {
        static let rowFontSize: CGFloat = 13
        static let rowHeight: CGFloat = rowFontSize * 2
    }

    private let documentRouter: WorkspaceDocumentRouting
    private weak var tableView: NSTableView?
    private var documents: [Document] = []
    private var activeDocument: Document?
    private var isReloadingSelection = false

    init(documentRouter: WorkspaceDocumentRouting) {
        self.documentRouter = documentRouter
    }

    func attach(to tableView: NSTableView) {
        self.tableView = tableView
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(activateSelection)
        tableView.doubleAction = #selector(activateSelection)
    }

    func update(documents: [Document], activeDocument: Document?) {
        self.documents = documents
        self.activeDocument = activeDocument
        reload()
    }

    func applyTheme() {
        tableView?.needsDisplay = true
    }

    var contentHeight: CGFloat {
        guard let tableView, !documents.isEmpty else { return 0 }
        return tableView.rect(ofRow: documents.count - 1).maxY
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        documents.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Constants.rowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarSelectionRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("OpenFileCell")
        let cellView = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? makeCellView(identifier: identifier)
        let document = documents[row]
        cellView.imageView?.image = icon(for: document)
        cellView.textField?.attributedStringValue = attributedTitle(for: document)
        return cellView
    }

    @objc
    func reload() {
        guard let tableView else { return }

        isReloadingSelection = true
        tableView.reloadData()

        guard let currentDocument = activeDocument else {
            tableView.deselectAll(nil)
            isReloadingSelection = false
            return
        }

        if let row = documents.firstIndex(where: { $0 === currentDocument }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }

        isReloadingSelection = false
    }

    @objc
    private func activateSelection() {
        guard let tableView else { return }

        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < documents.count else { return }
        documentRouter.present(document: documents[row])
    }

    private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cellView = NSTableCellView()
        cellView.identifier = identifier

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.lineBreakMode = .byTruncatingMiddle
        textField.textColor = AppColors.sidebarText
        textField.font = NSFont.systemFont(ofSize: Constants.rowFontSize, weight: .medium)

        cellView.imageView = imageView
        cellView.textField = textField
        cellView.addSubview(imageView)
        cellView.addSubview(textField)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 14),
            imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),

            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -12),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        ])

        return cellView
    }

    private func icon(for document: Document) -> NSImage {
        if let fileURL = document.fileURL {
            let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }

        let icon = NSWorkspace.shared.icon(for: .plainText)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func attributedTitle(for document: Document) -> NSAttributedString {
        NSAttributedString(
            string: document.shortDisplayTitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: Constants.rowFontSize, weight: .medium),
                .foregroundColor: AppColors.sidebarText,
            ]
        )
    }
}
