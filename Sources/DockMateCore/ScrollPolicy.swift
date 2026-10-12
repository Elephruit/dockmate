import CoreGraphics

public enum ScrollPolicy {
    public static func shouldReverse(_ event: CGEvent) -> Bool {
        // Wheel mice emit discrete events. Trackpads and touch mice emit continuous
        // events; leave those alone to preserve the user's trackpad preference.
        event.type == .scrollWheel
            && event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
            && event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0
            && event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0
            && event.getIntegerValueField(.eventSourceUnixProcessID) == 0
    }

    public static func reverse(_ event: CGEvent) {
        let lines: [CGEventField] = [
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
            .scrollWheelEventDeltaAxis3
        ]
        let points: [CGEventField] = [.scrollWheelEventPointDeltaAxis1,
            .scrollWheelEventPointDeltaAxis2, .scrollWheelEventPointDeltaAxis3]
        let fixed: [CGEventField] = [.scrollWheelEventFixedPtDeltaAxis1,
            .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis3]
        // Quartz may recalculate sibling representations when a delta is set.
        // Snapshot every original value before writing any field.
        let lineValues = lines.map { event.getIntegerValueField($0) }
        let pointValues = points.map { event.getIntegerValueField($0) }
        let fixedValues = fixed.map { event.getDoubleValueField($0) }
        for (field, value) in zip(lines, lineValues) {
            event.setIntegerValueField(field, value: value == .min ? .max : -value)
        }
        for (field, value) in zip(fixed, fixedValues) {
            event.setDoubleValueField(field, value: -value)
        }
        for (field, value) in zip(points, pointValues) {
            event.setIntegerValueField(field, value: value == .min ? .max : -value)
        }
    }
}
