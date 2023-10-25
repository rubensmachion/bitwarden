/// A coordinator that manages navigation in the generator tab.
///
final class GeneratorCoordinator: Coordinator {
    // MARK: Types

    typealias Services = HasGeneratorRepository

    // MARK: Properties

    /// The services used by this coordinator.
    let services: Services

    /// The stack navigator that is managed by this coordinator.
    let stackNavigator: StackNavigator

    // MARK: Initialization

    /// Creates a new `GeneratorCoordinator`.
    ///
    /// - Parameters:
    ///   - services: The services used by this coordinator.
    ///   - stackNavigator: The stack navigator that is managed by this coordinator.
    ///
    init(
        services: Services,
        stackNavigator: StackNavigator
    ) {
        self.services = services
        self.stackNavigator = stackNavigator
    }

    // MARK: Methods

    func hideLoadingOverlay() {
        stackNavigator.hideLoadingOverlay()
    }

    func navigate(to route: GeneratorRoute, context: AnyObject?) {
        switch route {
        case .generator:
            showGenerator()
        }
    }

    func showLoadingOverlay(_ state: LoadingOverlayState) {
        stackNavigator.showLoadingOverlay(state)
    }

    func start() {
        navigate(to: .generator)
    }

    // MARK: Private Methods

    /// Shows the generator screen.
    ///
    private func showGenerator() {
        let processor = GeneratorProcessor(
            coordinator: asAnyCoordinator(),
            services: services,
            state: GeneratorState()
        )
        let view = GeneratorView(store: Store(processor: processor))
        stackNavigator.push(view)
    }
}