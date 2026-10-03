import SwiftUI

struct PatchProjectEditorView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let existingProject: PatchProject?
    let passwordIsProtected: Bool
    let initialDraft: PatchProjectDraft?
    let onSave: (PatchProject, String?) -> Void

    @State private var name: String
    @State private var author: String
    @State private var isPrivate: Bool
    @State private var bundleID: String
    @State private var bundleIdentifiers: [String]
    @State private var directories: [PatchDirectory]
    @State private var rules: [PatchRule]
    @State private var password = ""
    @State private var ruleEditor: PatchRuleEditorContext?
    @State private var validationMessageKey: String?

    init(
        existingProject: PatchProject?,
        passwordIsProtected: Bool,
        initialDraft: PatchProjectDraft? = nil,
        onSave: @escaping (PatchProject, String?) -> Void
    ) {
        self.existingProject = existingProject
        self.passwordIsProtected = passwordIsProtected
        self.initialDraft = initialDraft
        self.onSave = onSave
        _name = State(initialValue: existingProject?.name ?? initialDraft?.name ?? "")
        _author = State(initialValue: existingProject?.author ?? "")
        _isPrivate = State(initialValue: existingProject?.isPrivate ?? false)
        _bundleID = State(initialValue: initialDraft?.bundleIdentifiers.first ?? "")
        _bundleIdentifiers = State(
            initialValue: existingProject?.bundleIdentifiers
                ?? initialDraft?.bundleIdentifiers
                ?? []
        )
        _directories = State(
            initialValue: existingProject?.directories ?? initialDraft?.directories ?? []
        )
        _rules = State(initialValue: existingProject?.rules ?? initialDraft?.rules ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(language.text("patch.project")) {
                    TextField(language.text("patch.project_name"), text: $name)
                        .textInputAutocapitalization(.words)
                    TextField(language.text("patch.author_optional"), text: $author)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }

                if existingProject == nil {
                    Section {
                        if let capturedBundle = initialDraft?.bundleIdentifiers.first {
                            LabeledContent(language.text("patch.target_bundle")) {
                                Text(capturedBundle)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            TextField("com.example.app", text: $bundleID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.body.monospaced())
                        }
                    } header: {
                        Text(language.text("patch.target_bundle"))
                    } footer: {
                        Text(language.text("patch.workspace_bundle_footer"))
                    }
                }

                if existingProject != nil || !rules.isEmpty || !directories.isEmpty {
                    Section {
                    ForEach(rules) { rule in
                        Button {
                            ruleEditor = PatchRuleEditorContext(rule: rule)
                        } label: {
                            HStack(spacing: 10) {
                                ruleRow(rule)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(language.text("patch.edit_rule_hint"))
                    }
                    .onDelete { rules.remove(atOffsets: $0) }

                        if existingProject != nil {
                            Button {
                                ruleEditor = PatchRuleEditorContext(rule: nil)
                            } label: {
                                Label(language.text("patch.add_rule"), systemImage: "plus.circle.fill")
                            }
                        }
                        if !directories.isEmpty {
                            LabeledContent(language.text("patch.folders")) {
                                Text("\(directories.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(language.text("patch.captured_content"))
                    } footer: {
                        Text(language.text("patch.workspace_edit_footer"))
                    }
                }

                Section {
                    if existingProject == nil {
                        SecureField(language.text("patch.password_optional"), text: $password)
                            .textContentType(.newPassword)
                    } else {
                        Label(
                            language.text(passwordIsProtected ? "patch.password_locked" : "patch.no_password"),
                            systemImage: passwordIsProtected ? "lock.fill" : "lock.open"
                        )
                    }
                } header: {
                    Text(language.text("patch.password"))
                } footer: {
                    Text(language.text(existingProject == nil
                        ? "patch.password_immutable_footer"
                        : "patch.password_existing_footer"))
                }

                Section {
                    Toggle(isOn: $isPrivate) {
                        Label(
                            language.text("patch.private"),
                            systemImage: "eye.slash.fill"
                        )
                    }
                    .disabled(existingProject != nil)
                } header: {
                    Text(language.text("patch.privacy"))
                } footer: {
                    Text(language.text(existingProject == nil
                        ? "patch.private_footer"
                        : "patch.private_existing_footer"))
                }

                if let validationMessageKey {
                    Section {
                        Label(language.text(validationMessageKey), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(language.text(existingProject == nil ? "patch.new" : "patch.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.done"), action: save)
                }
            }
            .sheet(item: $ruleEditor) { context in
                PatchRuleEditorView(rule: context.rule) { savedRule in
                    if let index = rules.firstIndex(where: { $0.id == savedRule.id }) {
                        rules[index] = savedRule
                    } else {
                        rules.append(savedRule)
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: PatchRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rule.bundleID)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(rule.relativePath)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if rule.hasReplacement {
                Text(rule.replacementFilename)
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            } else {
                Label(language.text("patch.replacement_required"), systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 3)
    }

    private func save() {
        let projectName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectName.isEmpty, projectName.utf8.count <= 120 else {
            validationMessageKey = "patch.error.invalid_project"
            return
        }
        guard projectAuthor.utf8.count <= PatchPackageLimits.maximumAuthorBytes,
              !projectAuthor.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
              ) else {
            validationMessageKey = "patch.error.invalid_author"
            return
        }
        author = projectAuthor
        if existingProject == nil, isPrivate, password.isEmpty {
            validationMessageKey = "patch.error.private_password"
            return
        }
        if existingProject == nil, initialDraft == nil {
            do {
                let canonical = try PatchPathValidator.canonicalBundleIdentifier(bundleID)
                guard canonical == bundleID.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    throw PatchPackageError.invalidBundleIdentifier
                }
                bundleID = canonical
                bundleIdentifiers = [canonical]
            } catch let error as PatchPackageError {
                validationMessageKey = error.localizationKey
                return
            } catch {
                validationMessageKey = "patch.error.invalid_bundle"
                return
            }
        }
        guard !bundleIdentifiers.isEmpty || !rules.isEmpty || !directories.isEmpty else {
            validationMessageKey = "patch.error.invalid_project"
            return
        }
        guard let incompleteRule = rules.first(where: { !$0.hasReplacement }) else {
            saveCompleteProject(named: projectName)
            return
        }
        validationMessageKey = "patch.error.replacement_required"
        ruleEditor = PatchRuleEditorContext(rule: incompleteRule)
    }

    private func saveCompleteProject(named projectName: String) {
        let project = PatchProject(
            id: existingProject?.id ?? UUID(),
            name: projectName,
            author: author,
            isPrivate: isPrivate,
            createdAt: existingProject?.createdAt ?? Date(),
            updatedAt: Date(),
            bundleIdentifiers: bundleIdentifiers,
            directories: directories,
            rules: rules
        )
        do {
            try PatchPackageCodec.validate(project)
            onSave(project, existingProject == nil && !password.isEmpty ? password : nil)
            dismiss()
        } catch let error as PatchPackageError {
            validationMessageKey = error.localizationKey
        } catch {
            validationMessageKey = "patch.error.invalid_project"
        }
    }
}

private struct PatchRuleEditorContext: Identifiable {
    let id = UUID()
    let rule: PatchRule?
}

struct PatchRuleEditorView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let originalRule: PatchRule?
    let onSave: (PatchRule) -> Void

    @State private var bundleID: String
    @State private var relativePath: String
    @State private var replacementFilename: String
    @State private var replacementData: Data
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var validationMessageKey: String?

    init(rule: PatchRule?, onSave: @escaping (PatchRule) -> Void) {
        originalRule = rule
        self.onSave = onSave
        _bundleID = State(initialValue: rule?.bundleID ?? "")
        _relativePath = State(initialValue: rule?.relativePath ?? "")
        _replacementFilename = State(initialValue: rule?.replacementFilename ?? "")
        _replacementData = State(initialValue: rule?.replacementData ?? Data())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("com.example.app", text: $bundleID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    TextField("Library/path/file", text: $relativePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text(language.text("patch.destination"))
                } footer: {
                    Text(language.text("patch.bundle_not_uuid_footer"))
                }

                Section(language.text("patch.replacement_file")) {
                    Button {
                        showFileImporter = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: replacementFilename.isEmpty ? "doc.badge.plus" : "doc.fill")
                                .foregroundStyle(AppTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(replacementFilename.isEmpty
                                     ? language.text("patch.choose_file")
                                     : replacementFilename)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(language.text(replacementFilename.isEmpty
                                     ? "patch.replacement_required"
                                     : "patch.change_replacement"))
                                    .font(.caption)
                                    .foregroundStyle(replacementFilename.isEmpty ? Color.orange : Color.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(isImporting)
                    if isImporting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(language.text("patch.importing_replacement"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !replacementFilename.isEmpty {
                        LabeledContent(
                            language.text("patch.file_size"),
                            value: ByteCountFormatter.string(
                                fromByteCount: Int64(replacementData.count),
                                countStyle: .file
                            )
                        )
                    }
                }

                if let validationMessageKey {
                    Section {
                        Label(language.text(validationMessageKey), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(language.text(originalRule == nil ? "patch.add_rule" : "patch.edit_rule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.done"), action: save)
                        .disabled(isImporting)
                }
            }
            .sheet(isPresented: $showFileImporter) {
                FileDocumentPicker(
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showFileImporter = false
                        importFile(result)
                    },
                    onCancel: {
                        showFileImporter = false
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        isImporting = true
        validationMessageKey = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory != true,
                      values.isSymbolicLink != true,
                      values.isRegularFile == true else {
                    throw PatchPackageError.invalidProject
                }
                let importedData = try Data(contentsOf: url, options: .mappedIfSafe)
                DispatchQueue.main.async {
                    replacementData = importedData
                    replacementFilename = url.lastPathComponent
                    isImporting = false
                }
            } catch let error as PatchPackageError {
                DispatchQueue.main.async {
                    validationMessageKey = error.localizationKey
                    isImporting = false
                }
            } catch {
                DispatchQueue.main.async {
                    validationMessageKey = "patch.error.invalid_project"
                    isImporting = false
                }
            }
        }
    }

    private func save() {
        do {
            let canonicalBundle = try PatchPathValidator.canonicalBundleIdentifier(bundleID)
            let canonicalPath = try PatchPathValidator.canonicalRelativePath(relativePath)
            guard !replacementFilename.isEmpty else { throw PatchPackageError.invalidProject }
            onSave(PatchRule(
                id: originalRule?.id ?? UUID(),
                bundleID: canonicalBundle,
                relativePath: canonicalPath,
                replacementFilename: replacementFilename,
                replacementData: replacementData
            ))
            dismiss()
        } catch let error as PatchPackageError {
            validationMessageKey = error.localizationKey
        } catch {
            validationMessageKey = "patch.error.invalid_project"
        }
    }
}

// MARK: - Folder Patch Selection View

struct FolderPatchSelectionView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let containerRoot: URL
    let folder: URL
    let onCreate: ([PatchDraftCandidate]) -> Void

    @State private var candidates: [PatchDraftCandidate] = []
    @State private var selectedIDs = Set<String>()
    @State private var isLoading = true
    @State private var validationMessageKey: String?

    private var selectedCandidates: [PatchDraftCandidate] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(language.text("patch.folder_scanning"))
                } else if candidates.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder")
                            .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                            .foregroundStyle(.secondary)
                        Text(language.text("patch.folder_empty"))
                            .font(.headline)
                        Text(language.text("patch.folder_empty_message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    fileList
                }
            }
            .navigationTitle(language.text("patch.select_files"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("patch.add_selected")) {
                        let selection = selectedCandidates
                        dismiss()
                        onCreate(selection)
                    }
                    .disabled(selectedIDs.isEmpty)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(selectionActionTitle, action: toggleAll)
                }
            }
            .task { loadCandidates() }
        }
    }

    private var fileList: some View {
        List {
            if let validationMessageKey {
                Section {
                    Label(
                        language.text(validationMessageKey),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.red)
                }
            }

            Section {
                ForEach(candidates) { candidate in
                    Button {
                        toggle(candidate)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.url.lastPathComponent)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(candidate.relativePath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 5) {
                                Image(systemName: selectedIDs.contains(candidate.id)
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .foregroundStyle(selectedIDs.contains(candidate.id)
                                                     ? AppTheme.accent
                                                     : Color.secondary)
                                Text(ByteCountFormatter.string(
                                    fromByteCount: candidate.byteCount,
                                    countStyle: .file
                                ))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(language.text("patch.selected_count", Int64(selectedIDs.count)))
                    .textCase(nil)
            } footer: {
                Text(language.text("patch.folder_selection_footer"))
            }
        }
        .listStyle(.plain)
    }

    private var selectionActionTitle: String {
        selectedIDs.count == candidates.count
            ? language.text("patch.deselect_all")
            : language.text("patch.select_all")
    }

    private func loadCandidates() {
        guard isLoading else { return }
        let root = containerRoot
        let selectedFolder = folder
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try PatchDraftService.candidates(
                    in: selectedFolder,
                    containerRoot: root
                )
            }
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let loaded):
                    candidates = loaded
                    selectedIDs = Set(loaded.map(\.id))
                case .failure(let error as PatchPackageError):
                    validationMessageKey = error.localizationKey
                case .failure:
                    validationMessageKey = "patch.error.invalid_project"
                }
            }
        }
    }

    private func toggle(_ candidate: PatchDraftCandidate) {
        validationMessageKey = nil
        if selectedIDs.remove(candidate.id) != nil { return }
        selectedIDs.insert(candidate.id)
    }

    private func toggleAll() {
        validationMessageKey = nil
        if selectedIDs.count == candidates.count {
            selectedIDs.removeAll()
            return
        }
        selectedIDs = Set(candidates.map(\.id))
    }
}
