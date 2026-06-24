import AppKit
import UniformTypeIdentifiers

@MainActor
final class OpenFilesSidebarTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private struct RowPresentation: Equatable {
        let title: String
        let isEdited: Bool
        let isActive: Bool
    }

    enum Constants {
        static let rowFontSize: CGFloat = 13
        static let rowHeight: CGFloat = rowFontSize * 2
    }

    private let documentRouter: WorkspaceDocumentRouting
    private weak var tableView: NSTableView?
    private var documents: [Document] = []
    private var activeDocument: Document?
    private var fileIconsByPath: [String: NSImage] = [:]
    private var rowPresentationByDocumentIdentifier: [ObjectIdentifier: RowPresentation] = [:]
    private lazy var rowTitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: Constants.rowFontSize, weight: .medium),
        .foregroundColor: AppColors.sidebarText,
    ]
    private lazy var untitledIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .plainText)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }()
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
        let previousDocuments = self.documents
        let previousActiveDocument = self.activeDocument
        self.documents = documents
        self.activeDocument = activeDocument
        let livePaths = Set(documents.compactMap { $0.fileURL?.path })
        fileIconsByPath = fileIconsByPath.filter { livePaths.contains($0.key) }
        rowPresentationByDocumentIdentifier = rowPresentationByDocumentIdentifier.filter {
            let identifier = $0.key
            return documents.contains { document in
                ObjectIdentifier(document) == identifier
            }
        }

        if documentIdentifiers(in: previousDocuments) == documentIdentifiers(in: documents) {
            reloadChangedRows(previousDocuments: previousDocuments, previousActiveDocument: previousActiveDocument)
            reloadSelection(scrollIfNeeded: previousActiveDocument !== activeDocument)
            return
        }

        reload()
    }

    func applyTheme() {
        rowTitleAttributes = [
            .font: NSFont.systemFont(ofSize: Constants.rowFontSize, weight: .medium),
            .foregroundColor: AppColors.sidebarText,
        ]
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
        isReloadingSelection = false
        reloadSelection(scrollIfNeeded: true)
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
            let path = fileURL.path
            if let cachedIcon = fileIconsByPath[path] {
                return cachedIcon
            }

            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: 16, height: 16)
            fileIconsByPath[path] = icon
            return icon
        }

        return untitledIcon
    }

    private func attributedTitle(for document: Document) -> NSAttributedString {
        NSAttributedString(string: document.shortDisplayTitle, attributes: rowTitleAttributes)
    }

    private func reloadChangedRows(previousDocuments: [Document], previousActiveDocument: Document?) {
        guard let tableView else { return }

        let previousRowsByIdentifier = Dictionary(
            uniqueKeysWithValues: previousDocuments.enumerated().map { (index, document) in
                (ObjectIdentifier(document), index)
            }
        )

        var rowsNeedingReload = IndexSet()
        for (row, document) in documents.enumerated() {
            let identifier = ObjectIdentifier(document)
            guard previousRowsByIdentifier[identifier] == row else {
                rowsNeedingReload.insert(row)
                continue
            }

            let previousPresentation = rowPresentationByDocumentIdentifier[identifier]
            let nextPresentation = makeRowPresentation(
                for: document,
                isActive: document === activeDocument
            )
            if previousPresentation != nextPresentation {
                rowsNeedingReload.insert(row)
            }
        }

        if !rowsNeedingReload.isEmpty {
            tableView.reloadData(forRowIndexes: rowsNeedingReload, columnIndexes: IndexSet(integer: 0))
        }

        if previousActiveDocument !== activeDocument {
            if let previousActiveDocument,
               let previousRow = previousRowsByIdentifier[ObjectIdentifier(previousActiveDocument)] {
                tableView.reloadData(
                    forRowIndexes: IndexSet(integer: previousRow),
                    columnIndexes: IndexSet(integer: 0)
                )
            }

            if let activeDocument,
               let nextRow = documents.firstIndex(where: { $0 === activeDocument }) {
                tableView.reloadData(
                    forRowIndexes: IndexSet(integer: nextRow),
                    columnIndexes: IndexSet(integer: 0)
                )
            }
        }
    }

    private func reloadSelection(scrollIfNeeded: Bool) {
        guard let tableView else { return }

        isReloadingSelection = true
        defer { isReloadingSelection = false }

        guard let currentDocument = activeDocument else {
            tableView.deselectAll(nil)
            return
        }

        guard let row = documents.firstIndex(where: { $0 === currentDocument }) else {
            tableView.deselectAll(nil)
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        if scrollIfNeeded, !tableView.rows(in: tableView.visibleRect).contains(row) {
            tableView.scrollRowToVisible(row)
        }
    }

    private func documentIdentifiers(in documents: [Document]) -> [ObjectIdentifier] {
        documents.map(ObjectIdentifier.init)
    }

    private func makeRowPresentation(for document: Document, isActive: Bool) -> RowPresentation {
        let presentation = RowPresentation(
            title: document.shortDisplayTitle,
            isEdited: document.isDocumentEdited,
            isActive: isActive
        )
        rowPresentationByDocumentIdentifier[ObjectIdentifier(document)] = presentation
        return presentation
    }
}
