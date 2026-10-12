public enum DisplayPolicy {
    public static func canTurnOff(hasBuiltIn: Bool, activeExternalCount: Int) -> Bool {
        hasBuiltIn && activeExternalCount > 0
    }

    public static func shouldRestore(disabledByApp: Bool, activeExternalCount: Int) -> Bool {
        disabledByApp && activeExternalCount == 0
    }
}
