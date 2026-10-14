public enum ApplicationToggleDecision: Equatable {
    case launch, show, minimize

    public static func resolve(isRunning: Bool, isFrontmost: Bool, hasVisibleWindow: Bool) -> Self {
        if !isRunning { return .launch }
        return isFrontmost && hasVisibleWindow ? .minimize : .show
    }
}
