import FennecCore

public enum FillerDetectorFactory {
    public static func make() -> any FillerDetector {
        HeuristicFillerDetector()
    }
}
