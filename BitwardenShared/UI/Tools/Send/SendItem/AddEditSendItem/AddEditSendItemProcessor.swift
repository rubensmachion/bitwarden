import BitwardenSdk
import Foundation

// MARK: - AddEditSendItemProcessor

/// The processor used to manage state and handle actions for the add/edit send item screen.
///
class AddEditSendItemProcessor: StateProcessor<AddEditSendItemState, AddEditSendItemAction, AddEditSendItemEffect> {
    // MARK: Types

    typealias Services = HasPasteboardService
        & HasSendRepository

    // MARK: Properties

    /// The `Coordinator` that handles navigation for this processor.
    let coordinator: any Coordinator<SendItemRoute>

    /// The services required by this processor.
    let services: Services

    // MARK: Initialization

    /// Creates a new `AddEditSendItemProcessor`.
    ///
    /// - Parameters:
    ///   - coordinator: The coordinator that handles navigation for this processor.
    ///   - services: The services required by this processor.
    ///   - state: The initial state of this processor.
    ///
    init(
        coordinator: any Coordinator<SendItemRoute>,
        services: Services,
        state: AddEditSendItemState
    ) {
        self.coordinator = coordinator
        self.services = services
        super.init(state: state)
    }

    // MARK: Methods

    override func perform(_ effect: AddEditSendItemEffect) async {
        switch effect {
        case .copyLinkPressed:
            guard let sendView = state.originalSendView,
                  let url = try? await services.sendRepository.shareURL(for: sendView)
            else { return }

            services.pasteboardService.copy(url.absoluteString)
            state.toast = Toast(text: Localizations.valueHasBeenCopied(Localizations.sendLink))
        case .deletePressed:
            guard let sendView = state.originalSendView else { return }
            let alert = Alert.confirmation(title: Localizations.areYouSureDeleteSend) { [weak self] in
                await self?.deleteSend(sendView)
            }
            coordinator.showAlert(alert)
        case .removePassword:
            guard let sendView = state.originalSendView else { return }
            let alert = Alert.confirmation(title: Localizations.areYouSureRemoveSendPassword) { [weak self] in
                await self?.removePassword(sendView)
            }
            coordinator.showAlert(alert)
        case .savePressed:
            await saveSendItem()
        case .shareLinkPressed:
            guard let sendView = state.originalSendView else { return }
            await shareSaveURL(sendView)
        }
    }

    override func receive(_ action: AddEditSendItemAction) {
        switch action {
        case .chooseFilePressed:
            presentFileSelectionAlert()
        case .clearExpirationDatePressed:
            state.customExpirationDate = nil
        case let .customDeletionDateChanged(newValue):
            state.customDeletionDate = newValue
        case let .customExpirationDateChanged(newValue):
            state.customExpirationDate = newValue
        case let .deactivateThisSendChanged(newValue):
            state.isDeactivateThisSendOn = newValue
        case let .deletionDateChanged(newValue):
            state.deletionDate = newValue
        case let .expirationDateChanged(newValue):
            state.expirationDate = newValue
        case .dismissPressed:
            coordinator.navigate(to: .cancel)
        case let .hideMyEmailChanged(newValue):
            state.isHideMyEmailOn = newValue
        case let .hideTextByDefaultChanged(newValue):
            state.isHideTextByDefaultOn = newValue
        case .optionsPressed:
            state.isOptionsExpanded.toggle()
        case let .passwordChanged(newValue):
            state.password = newValue
        case let .passwordVisibleChanged(newValue):
            state.isPasswordVisible = newValue
        case let .maximumAccessCountChanged(newValue):
            state.maximumAccessCount = newValue
        case let .nameChanged(newValue):
            state.name = newValue
        case let .notesChanged(newValue):
            state.notes = newValue
        case let .textChanged(newValue):
            state.text = newValue
        case let .toastShown(toast):
            state.toast = toast
        case let .typeChanged(newValue):
            updateType(newValue)
        }
    }

    // MARK: Private Methods

    /// Deletes the provided send.
    ///
    /// - Parameter sendView: The send to be deleted.
    ///
    private func deleteSend(_ sendView: SendView) async {
        coordinator.showLoadingOverlay(LoadingOverlayState(title: Localizations.deleting))
        do {
            try await services.sendRepository.deleteSend(sendView)
            coordinator.hideLoadingOverlay()
            coordinator.navigate(to: .deleted)
        } catch {
            let alert = Alert.networkResponseError(error) { [weak self] in
                await self?.deleteSend(sendView)
            }
            coordinator.hideLoadingOverlay()
            coordinator.showAlert(alert)
        }
    }

    /// Presents the file selection alert.
    ///
    private func presentFileSelectionAlert() {
        let alert = Alert.fileSelectionOptions { [weak self] route in
            guard let self else { return }
            coordinator.navigate(to: .fileSelection(route), context: self)
        }
        coordinator.showAlert(alert)
    }

    /// Removes the password from the provided send.
    ///
    /// - Parameter sendView: The send to remove the password from.
    ///
    private func removePassword(_ sendView: SendView) async {
        coordinator.showLoadingOverlay(LoadingOverlayState(title: Localizations.removingSendPassword))
        do {
            let newSend = try await services.sendRepository.removePassword(from: sendView)
            var newState = AddEditSendItemState(sendView: newSend, hasPremium: state.hasPremium)
            newState.isOptionsExpanded = state.isOptionsExpanded
            state = newState

            coordinator.hideLoadingOverlay()
            state.toast = Toast(text: Localizations.sendPasswordRemoved)
        } catch {
            let alert = Alert.networkResponseError(error) { [weak self] in
                await self?.removePassword(sendView)
            }
            coordinator.hideLoadingOverlay()
            coordinator.showAlert(alert)
        }
    }

    /// Saves the current send item.
    ///
    private func saveSendItem() async {
        guard !state.name.isEmpty else {
            let alert = Alert.validationFieldRequired(fieldName: Localizations.name)
            coordinator.showAlert(alert)
            return
        }

        coordinator.showLoadingOverlay(LoadingOverlayState(title: Localizations.saving))
        defer { coordinator.hideLoadingOverlay() }

        let sendView = state.newSendView()
        do {
            let newSendView: SendView
            switch state.mode {
            case .add:
                switch state.type {
                case .file:
                    guard let fileData = state.fileData else { return }
                    newSendView = try await services.sendRepository.addFileSend(sendView, data: fileData)
                case .text:
                    newSendView = try await services.sendRepository.addTextSend(sendView)
                }
            case .edit:
                newSendView = try await services.sendRepository.updateSend(sendView)
            }
            coordinator.hideLoadingOverlay()
            coordinator.navigate(to: .complete(newSendView))
        } catch {
            coordinator.showAlert(.networkResponseError(error) { [weak self] in
                await self?.saveSendItem()
            })
        }
    }

    /// Navigates to the `.share` route for the provided send view.
    ///
    /// - Parameter sendView: The send that is being shared.
    ///
    private func shareSaveURL(_ sendView: SendView) async {
        guard let url = try? await services.sendRepository.shareURL(for: sendView)
        else { return }

        coordinator.navigate(to: .share(url: url))
    }

    /// Attempts to update the send type. If the new value requires premium access and the active
    /// account does not have premium access, this method will display an alert informing the user
    /// that they do not have access to this feature.
    ///
    /// - Parameter newValue: The new value for the Send's type that will be attempted to be set.
    ///
    private func updateType(_ newValue: SendType) {
        guard !newValue.requiresPremium || state.hasPremium else {
            coordinator.showAlert(.defaultAlert(title: Localizations.sendFilePremiumRequired))
            return
        }
        state.type = newValue
    }
}

// MARK: - AddEditSendItemProcessor:FileSelectionDelegate

extension AddEditSendItemProcessor: FileSelectionDelegate {
    func fileSelectionCompleted(fileName: String, data: Data) {
        state.fileName = fileName
        state.fileData = data
    }
}