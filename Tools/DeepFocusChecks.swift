import Foundation

@main
enum DeepFocusChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func main() {
        let subgroup = UUID()
        let rules = [
            ActivityClassificationRule(displayName: "Xcode", identifier: "com.apple.dt.Xcode", kind: .application, classification: .flow, subgroupID: subgroup),
            ActivityClassificationRule(displayName: "Docs", identifier: "docs.example.com", kind: .website, classification: .flow, subgroupID: subgroup),
            ActivityClassificationRule(displayName: "Social", identifier: "social.example.com", kind: .website, classification: .brainrot, subgroupID: subgroup)
        ]

        expect(DeepFocusDuration.oneHour.seconds == 3600, "The default duration must represent one hour")
        expect(DeepFocusPolicy.isFlowApplication(bundleIdentifier: "com.apple.dt.Xcode", displayName: "Xcode", rules: rules), "Flow app should be allowed")
        expect(!DeepFocusPolicy.isFlowApplication(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit", rules: rules), "Unclassified app should be blocked")
        expect(DeepFocusPolicy.isFlowWebsite(urlString: "https://project.docs.example.com/page", rules: rules), "Flow subdomain should be allowed")
        expect(!DeepFocusPolicy.isFlowWebsite(urlString: "https://social.example.com/feed", rules: rules), "Non-Flow website should be blocked")
        expect(!DeepFocusPolicy.isFlowWebsite(urlString: "not a URL", rules: rules), "Unreadable website should be blocked")

        let now = Date(timeIntervalSince1970: 1_000)
        expect(DeepFocusPolicy.fiveMinuteWarningDate(endDate: now.addingTimeInterval(3_600), now: now) == now.addingTimeInterval(3_300), "Five-minute warning should be scheduled correctly")
        expect(DeepFocusPolicy.fiveMinuteWarningDate(endDate: now.addingTimeInterval(120), now: now) == nil, "Expired warning should not be scheduled")
        print("Deep Focus policy checks passed")
    }
}
