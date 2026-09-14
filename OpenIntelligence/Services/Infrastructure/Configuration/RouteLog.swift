//
//  RouteLog.swift
//  OpenIntelligence
//
//  One line per generation to the unified log, naming where the answer was written.
//
//  WHY THIS EXISTS, SEPARATELY FROM `LoggingConfiguration`
//
//  Until 2026-09-14 a Release build, which is what TestFlight installs, emitted nothing to the
//  unified logging system about routing. Not less; nothing. Every route-naming statement went
//  through the `Log` facade, whose only console output is a `print()` inside `#if DEBUG`, and
//  `print` writes to stdout, which Console.app never sees even from a Debug build on a device.
//  Two further gates would have silenced it anyway: Release defaults the facade to `.error` with
//  no categories enabled. So the one question a tester can ask, "did that answer come from the
//  device or from Private Cloud Compute", had no answer outside the app.
//
//  This is deliberately NOT a new sink inside the facade. The facade's `.llm` lines can carry
//  prompt and response text at debug level, and `Docs/PRIVACY_AND_ROUTING.md` section 8 forbids
//  any of that reaching telemetry. Routing the whole facade into the unified log would have
//  shipped the leak along with the fix. This type instead accepts only enum cases, identifiers and
//  a count, so no call site can hand it a query, a passage or an answer, whatever it intended.
//
//  WHY `.notice`, AND WHY `privacy: .public`
//
//  `notice` is the default log level: persisted to disk and shown by Console.app without any
//  "include info/debug" toggle, which is the whole point. `info` lives in memory and is only
//  written out when a fault happens nearby, so a healthy app would still show nothing. The
//  interpolations are marked public because the unified log redacts dynamic strings to `<private>`
//  by default; that redaction is right for user data and wrong for a target name, and everything
//  this line contains is a target name, a reason code or an identifier by construction.
//
//  READING IT: `Docs/ai/RUNBOOK.md`, "Reading the route from Console.app".
//

import Foundation
import os

// MARK: - The line, as a value

/// The rendered line and nothing else. Pure, so it can be tested without the unified log.
struct RouteLogLine: Equatable, Sendable {

    /// What the plan asked for versus what ran, at the moment the session was resolved.
    static func started(
        actualTarget: ModelExecutionTarget,
        reasoningLevel: String?,
        plan: ModelExecutionPlan?
    ) -> RouteLogLine {
        RouteLogLine(
            rendered:
                "route started actual=\(actualTarget.rawValue)"
                + " intended=\(plan?.intendedTarget.rawValue ?? "direct")"
                + " reasoning=\(reasoningLevel ?? "none")"
                + planSuffix(plan?.id, plan?.policyVersion)
        )
    }

    /// What ran, once the answer is complete and the receipt is written.
    static func completed(
        actualTarget: ModelExecutionTarget,
        receipt: ModelExecutionReceipt?
    ) -> RouteLogLine {
        RouteLogLine(
            rendered:
                "route completed actual=\(actualTarget.rawValue)"
                + " intended=\(receipt?.intendedTarget.rawValue ?? "direct")"
                + " fallback=\(receipt?.fallbackReason?.rawValue ?? "none")"
                + " attempts=\(receipt?.attempts.count ?? 1)"
                + planSuffix(receipt?.planID, receipt?.policyVersion)
        )
    }

    let rendered: String

    /// A plan is named by the first eight characters of its UUID, enough to match a receipt in the
    /// app's own diagnostics and not enough to be mistaken for content. `direct` is a generation
    /// with no plan behind it, which is what title generation and the benchmark harness do.
    private static func planSuffix(_ id: UUID?, _ policyVersion: String?) -> String {
        guard let id else { return " plan=direct policy=none" }
        return " plan=\(String(id.uuidString.prefix(8))) policy=\(policyVersion ?? "none")"
    }
}

// MARK: - The sink

enum RouteLog {

    /// The subsystem is the bundle identifier, which is Apple's convention and what a reader
    /// filtering Console.app will reach for first. The two older `OSLog` subsystems in this app
    /// (`OpenIntelligence` for the RAGEngine signposts, `com.openintelligence` for the evidence
    /// store) predate this and are left alone; a routing predicate should not have to know them.
    static let subsystem = "Gunndamental.OpenIntelligence"
    static let category = "routing"

    private static let logger = Logger(subsystem: subsystem, category: category)

    static func started(
        actualTarget: ModelExecutionTarget,
        reasoningLevel: String?,
        plan: ModelExecutionPlan?
    ) {
        emit(RouteLogLine.started(actualTarget: actualTarget, reasoningLevel: reasoningLevel, plan: plan))
    }

    static func completed(actualTarget: ModelExecutionTarget, receipt: ModelExecutionReceipt?) {
        emit(RouteLogLine.completed(actualTarget: actualTarget, receipt: receipt))
    }

    private static func emit(_ line: RouteLogLine) {
        // Every token in `rendered` is an enum raw value, a UUID prefix, a version constant or a
        // count; see `RouteLogLine`. That is what makes `.public` correct here and nowhere else.
        logger.notice("\(line.rendered, privacy: .public)")
    }
}

#if canImport(FoundationModels)
    import FoundationModels

    @available(iOS 26.0, macOS 26.0, *)
    extension RouteLog {

        /// The call-site form: takes the resolved Foundation Models route so the mapping from
        /// route to public target name and reasoning level lives here, once, and not in each of
        /// `LLMService`'s generation paths.
        static func started(route: AppleFoundationModelRoute, plan: ModelExecutionPlan?) {
            started(
                actualTarget: Self.target(for: route),
                reasoningLevel: Self.reasoningLevel(for: route),
                plan: plan
            )
        }

        /// The same collapse `LLMService` applies when it writes a receipt: only Private Cloud
        /// Compute is a distinct target; both on-device routes and `.automatic` are on-device.
        static func target(for route: AppleFoundationModelRoute) -> ModelExecutionTarget {
            if case .privateCloudCompute = route { return .privateCloudCompute }
            return .onDevice
        }

        /// The reasoning level is only meaningful on Private Cloud Compute, and `.none` is a real
        /// level there, distinct from an on-device route that has no level at all.
        static func reasoningLevel(for route: AppleFoundationModelRoute) -> String? {
            if case .privateCloudCompute(let reasoning) = route { return reasoning.rawValue }
            return nil
        }
    }
#endif
