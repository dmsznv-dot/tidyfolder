import Foundation
public enum PlanValidity {
    public static func isCurrent(plan: TidyPlan, settings: AppSettings, source: URL, destination: URL) -> Bool {
        plan.rules == settings.rules && plan.options == settings.scanOptions && PathSafety.canonical(plan.sourceRoot).path == PathSafety.canonical(source).path && PathSafety.canonical(plan.destinationRoot).path == PathSafety.canonical(destination).path
    }
}
