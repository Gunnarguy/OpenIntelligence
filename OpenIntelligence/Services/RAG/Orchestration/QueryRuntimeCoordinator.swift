//
//  QueryRuntimeCoordinator.swift
//  OpenIntelligence
//
//  Extracted from RAGService.swift to own query-level configuration
//  resolution and execution path routing.
//
//  This coordinator resolves:
//  - Quality mode (Standard / Deep Think / Maximum)
//  - Execution policy (extractive vs generative vs agentic)
//  - PCC / cloud eligibility
//  - Adaptive thermal/battery pipeline config
//  - Query profiling and execution planning
//  - Agentic vs standard pipeline routing decision
//
//  RAGService delegates to this coordinator at the start of every query,
//  receiving a fully resolved QueryRuntimeContext.
//

import Foundation

// MARK: - Execution Path

/// The resolved execution path for a query.
enum QueryExecutionPath {
    /// Single-pass retrieval pipeline (Standard mode)
    case standard
    /// Multi-session agentic orchestrator (Deep Think / Maximum)
    case agentic
    /// Forced agentic via user "Go Deeper" action
    case forcedAgentic
    /// Planner auto-escalated a Standard query to agentic
    case plannerEscalated
}

// MARK: - Query Runtime Context

/// A snapshot of all resolved configuration for a single query execution.
/// Created by `QueryRuntimeCoordinator` and consumed by the pipeline.
struct QueryRuntimeContext {
    // -- Execution Path --
    let executionPath: QueryExecutionPath
    let qualityMode: RAGQualityMode
    let qualityModeDisplayName: String

    // -- Infrastructure --
    let inferenceConfig: InferenceConfig
    let reliabilityModeEnabled: Bool
    let allowUngroundedFallback: Bool
    let networkAvailable: Bool

    // -- PCC / Cloud --
    let isAppleFMService: Bool
    let cloudEligible: Bool
    let initialWantsCloudContext: Bool
    let pccSuppressed: Bool
    let initialCloudConsentState: CloudConsentState

    // -- Query Intelligence --
    let queryProfile: QueryProfile
    let queryPlan: QueryExecutionPlan
    let queryComplexity: QueryComplexity

    // -- Adaptive Pipeline --
    let adaptiveConfig: AdaptivePipelineConfig
    let adaptiveOptimizationLevel: PipelineOptimizationLevel

    // -- Settings --
    let raptorSummariesEnabled: Bool
    let raptorRoutingEnabled: Bool
    let developerTuningEnabled: Bool

    // -- Routing & Budget (for Metadata) --
    let executionRoute: ResponseMetadata.ExecutionRoute
    let tokenBudget: ResponseMetadata.TokenBudget

    /// Whether the execution path is any form of agentic
    var isAgentic: Bool {
        switch executionPath {
        case .agentic, .forcedAgentic, .plannerEscalated:
            return true
        case .standard:
            return false
        }
    }
}

// MARK: - QueryRuntimeCoordinator

/// Resolves all query-scoped configuration and determines the execution path.
///
/// This coordinator is the first stop for every query. It reads settings,
/// device state, model availability, and query intelligence to produce a
/// fully resolved `QueryRuntimeContext` that the pipeline can execute against
/// without needing to re-read scattered state.
///
/// Extracted from `RAGService.queryInternal` (lines 6950–7118) to reduce
/// the mega-orchestrator's responsibilities.
@MainActor
final class QueryRuntimeCoordinator {

    // MARK: - Dependencies (weak to avoid retain cycles with RAGService)

    private weak var settingsStore: SettingsStore?

    // MARK: - Init

    init(settingsStore: SettingsStore?) {
        self.settingsStore = settingsStore
    }

    /// Update the settings store reference (called when RAGService rebinds).
    func updateSettingsStore(_ store: SettingsStore?) {
        self.settingsStore = store
    }

    // MARK: - Resolve

    /// Resolve all query-scoped configuration and determine the execution path.
    ///
    /// - Parameters:
    ///   - question: The user's query text
    ///   - qualityModeOverride: Optional quality mode override from the caller
    ///   - isAppleFMService: Whether the active LLM service is Apple Foundation Models
    ///   - isPCCSuppressed: Whether PCC is currently suppressed (cooldown)
    ///   - cloudConsent: Current cloud consent state for Apple PCC
    ///   - forceAgentic: Whether the user forced agentic mode (e.g., "Go Deeper")
    ///   - inferenceConfig: The base inference config (will be mutated for PCC routing)
    /// - Returns: A fully resolved `QueryRuntimeContext`
    func resolveContext(
        question: String,
        qualityModeOverride: RAGQualityMode?,
        isAppleFMService: Bool,
        isPCCSuppressed: Bool,
        cloudConsent: CloudConsentState,
        forceAgentic: Bool,
        inferenceConfig: InferenceConfig
    ) async -> QueryRuntimeContext {

        var config = inferenceConfig
        if config.fmPreference == .core3B || config.fmPreference == .advanced20B {
            config.allowPrivateCloudCompute = false
            config.executionContext = .onDeviceOnly
        }
        let networkAvailable = NetworkMonitor.shared.isConnected
        let reliabilityModeEnabled = settingsStore?.reliabilityModeEnabled ?? true

        // -- PCC / Cloud Eligibility --

        let cloudConsentAllowed = cloudConsent == .allowed
        let cloudEligible =
            isAppleFMService
                && networkAvailable
                && config.allowPrivateCloudCompute
                && config.executionContext != .onDeviceOnly
                && !isPCCSuppressed
        let initialWantsCloudContext = cloudEligible && cloudConsentAllowed

        // -- Execution Context Selection --

        #if targetEnvironment(simulator)
            if isAppleFMService {
                config.executionContext = .onDeviceOnly
                config.allowPrivateCloudCompute = false
                Log.info("[QueryRuntime] Simulator → onDeviceOnly (PCC unavailable)", category: .pipeline)
            }
        #else
            if isAppleFMService {
                if !networkAvailable {
                    config.executionContext = .onDeviceOnly
                    config.allowPrivateCloudCompute = false
                    Log.info("[QueryRuntime] Offline → onDeviceOnly (4096 tokens)", category: .pipeline)
                } else if isPCCSuppressed {
                    config.executionContext = .onDeviceOnly
                    config.allowPrivateCloudCompute = false
                    Log.info("[QueryRuntime] PCC suppressed → onDeviceOnly (context cooldown)", category: .pipeline)
                } else if !config.allowPrivateCloudCompute {
                    config.executionContext = .onDeviceOnly
                    Log.info("[QueryRuntime] PCC disabled → onDeviceOnly", category: .pipeline)
                } else {
                    if config.executionContext == .automatic {
                        config.executionContext = .preferCloud
                        Log.info("[QueryRuntime] Network available → preferCloud (PCC capable)", category: .pipeline)
                    } else if config.executionContext == .cloudOnly, !cloudConsentAllowed {
                        config.executionContext = .preferCloud
                        Log.info("[QueryRuntime] PCC consent pending → preferCloud (allow fallback)", category: .pipeline)
                    }
                }
            }
        #endif

        // -- Quality Mode Resolution --

        let qualityMode = qualityModeOverride ?? settingsStore?.ragQualityMode ?? .standard
        config.qualityMode = qualityMode

        // -- Query Profiling & Execution Planning --

        let queryProfile = await QueryProfileService.shared.buildProfile(
            for: question,
            routingEnabled: false
        )

        let queryPlan = await QueryExecutionPlannerService.shared.buildPlan(
            for: question,
            profile: queryProfile,
            requestedQualityMode: qualityMode,
            allowToolCalling: qualityMode.usesAgenticOrchestrator
        )

        // Disable auto-escalation for Apple FMs because PCC context limits and 3B fallbacks
        // often cause infinite generation loops during 8-session agentic chains.
        let plannerEscalated = qualityMode.canonical == .standard && queryPlan.shouldAutoEscalateToAgentic && !isAppleFMService
        let executionPath: QueryExecutionPath
        if forceAgentic {
            executionPath = .forcedAgentic
            Log.info("[QueryRuntime] Query FORCED to agentic mode by user request", category: .pipeline)
        } else if plannerEscalated {
            executionPath = .plannerEscalated
            Log.info("[QueryRuntime] Planner escalated Standard query to agentic: \(queryPlan.reasoning)", category: .pipeline)
        } else if qualityMode.isUnlimitedMode {
            executionPath = .agentic
            Log.info("[QueryRuntime] Using Maximum mode (user selected)", category: .pipeline)
        } else if qualityMode.usesAgenticOrchestrator {
            executionPath = .agentic
            Log.info("[QueryRuntime] Using Deep Think mode (user selected)", category: .pipeline)
        } else {
            executionPath = .standard
            Log.info("[QueryRuntime] Using Standard mode", category: .pipeline)
        }

        // -- Adaptive Pipeline Config --

        let queryComplexity = queryProfile.adaptiveComplexity
        let adaptiveConfig = AdaptivePipelineOptimizer.shared.configForQuery(complexity: queryComplexity)
        let adaptiveOptLevel = AdaptivePipelineOptimizer.shared.currentOptimizationLevel
        if adaptiveOptLevel != .full {
            Log.info("[QueryRuntime] Pipeline adjusted to \(adaptiveOptLevel.rawValue) mode", category: .pipeline)
        }

        // -- Settings --

        let raptorSummariesEnabled = settingsStore?.enableDocumentSummaries ?? true
        let raptorRoutingEnabled = settingsStore?.enableQueryRouting ?? true
        let developerTuningEnabled = settingsStore?.developerRAGTuningEnabled ?? false
        let allowUngroundedFallback = reliabilityModeEnabled || developerTuningEnabled

        // -- Build Metadata Components --

        let isOnDevice = config.executionContext == .onDeviceOnly
        let route = ResponseMetadata.ExecutionRoute(
            path: isOnDevice ? "On-Device" : (isAppleFMService ? "Private Cloud Compute" : "Local/Cloud API"),
            reason: queryPlan.reasoning,
            policyApplied: isAppleFMService ? "Apple Foundation Routing" : nil,
            emoji: isOnDevice ? "📱" : (isAppleFMService ? "☁️" : "🌐")
        )

        let totalLimit = FoundationModelTokenBudget.tokenBudget(isAppleFMOnDevice: isOnDevice)
        let budget = ResponseMetadata.TokenBudget(
            totalLimit: totalLimit,
            systemPrompt: 800, // Estimated overhead
            retrievedContext: 0, // Will be updated after retrieval
            generation: 1024, // Reserved for output
            remaining: totalLimit - 800 - 1024
        )

        // -- Build Context --

        return QueryRuntimeContext(
            executionPath: executionPath,
            qualityMode: qualityMode,
            qualityModeDisplayName: qualityMode.displayName,
            inferenceConfig: config,
            reliabilityModeEnabled: reliabilityModeEnabled,
            allowUngroundedFallback: allowUngroundedFallback,
            networkAvailable: networkAvailable,
            isAppleFMService: isAppleFMService,
            cloudEligible: cloudEligible,
            initialWantsCloudContext: initialWantsCloudContext,
            pccSuppressed: isPCCSuppressed,
            initialCloudConsentState: cloudConsent,
            queryProfile: queryProfile,
            queryPlan: queryPlan,
            queryComplexity: queryComplexity,
            adaptiveConfig: adaptiveConfig,
            adaptiveOptimizationLevel: adaptiveOptLevel,
            raptorSummariesEnabled: raptorSummariesEnabled,
            raptorRoutingEnabled: raptorRoutingEnabled,
            developerTuningEnabled: developerTuningEnabled,
            executionRoute: route,
            tokenBudget: budget
        )
    }
}
