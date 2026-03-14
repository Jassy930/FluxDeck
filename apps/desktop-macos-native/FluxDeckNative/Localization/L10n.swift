import Foundation

enum L10n {
    static let settingsLanguageTitle = "settings.language.title"
    static let settingsLanguageDescription = "settings.language.description"
    static let settingsLanguageOptionSystem = "settings.language.option.system"
    static let settingsLanguageOptionEnglish = "settings.language.option.english"
    static let settingsLanguageOptionSimplifiedChinese = "settings.language.option.simplified_chinese"

    static let settingsSectionAdminApiTitle = "settings.section.admin_api.title"
    static let settingsSectionAdminApiDescription = "settings.section.admin_api.description"
    static let settingsSectionRefreshSyncTitle = "settings.section.refresh_sync.title"
    static let settingsSectionRefreshSyncDescription = "settings.section.refresh_sync.description"
    static let settingsSectionDiagnosticsTitle = "settings.section.diagnostics.title"
    static let settingsSectionDiagnosticsDescription = "settings.section.diagnostics.description"
    static let settingsStatusNeedsAttention = "settings.status.needs_attention"
    static let settingsStatusRefreshing = "settings.status.refreshing"
    static let settingsStatusNotConfigured = "settings.status.not_configured"
    static let settingsStatusReady = "settings.status.ready"
    static let settingsActionApply = "settings.action.apply"
    static let settingsActionReset = "settings.action.reset"
    static let settingsDiagnosticsCurrentEndpoint = "settings.diagnostics.current_endpoint"
    static let settingsDiagnosticsBusy = "settings.diagnostics.busy"
    static let settingsDiagnosticsError = "settings.diagnostics.error"

    static let sidebarBrandSubtitle = "sidebar.brand.subtitle"
    static let shellToolbarWorkspace = "shell.toolbar.workspace"
    static let shellToolbarAdmin = "shell.toolbar.admin"
    static let shellToolbarRefresh = "shell.toolbar.refresh"
    static let shellToolbarLastRefresh = "shell.toolbar.last_refresh"
    static let shellStatusConnectionSyncing = "shell.status.connection.syncing"
    static let shellStatusConnectionOffline = "shell.status.connection.offline"
    static let shellStatusConnectionConnected = "shell.status.connection.connected"

    static let commonDurationMilliseconds = "common.duration_milliseconds"
    static let overviewGatewayStatusHealthy = "overview.gateway_status.healthy"
    static let overviewGatewayStatusIdle = "overview.gateway_status.idle"
    static let providersListTitle = "providers.list.title"
    static let providersListLoading = "providers.list.loading"
    static let providersListEmptyTitle = "providers.list.empty.title"
    static let providersListEmptyMessage = "providers.list.empty.message"
    static let providersFieldsEndpoint = "providers.fields.endpoint"
    static let providersFieldsModels = "providers.fields.models"
    static let providersFieldsHealth = "providers.fields.health"
    static let providersFieldsLastFailure = "providers.fields.last_failure"
    static let providersActionsNew = "providers.actions.new"
    static let providersActionsConfigure = "providers.actions.configure"
    static let providersActionsProbe = "providers.actions.probe"
    static let providersActionsDelete = "providers.actions.delete"
    static let providersActionsSubmitting = "providers.actions.submitting"
    static let gatewaysListTitle = "gateways.list.title"
    static let gatewaysListLoading = "gateways.list.loading"
    static let gatewaysListEmptyTitle = "gateways.list.empty.title"
    static let gatewaysListEmptyMessage = "gateways.list.empty.message"
    static let gatewaysFieldsEndpoint = "gateways.fields.endpoint"
    static let gatewaysFieldsProvider = "gateways.fields.provider"
    static let gatewaysFieldsActiveProvider = "gateways.fields.active_provider"
    static let gatewaysFieldsRoutes = "gateways.fields.routes"
    static let gatewaysFieldsHealth = "gateways.fields.health"
    static let gatewaysFieldsAutoStart = "gateways.fields.auto_start"
    static let gatewaysFieldsLastError = "gateways.fields.last_error"
    static let gatewaysActionsNew = "gateways.actions.new"
    static let gatewaysActionsEdit = "gateways.actions.edit"
    static let gatewaysActionsDelete = "gateways.actions.delete"
    static let gatewaysActionsApplying = "gateways.actions.applying"
    static let resourceProviderStatusEnabled = "resource.provider.status.enabled"
    static let resourceProviderStatusDisabled = "resource.provider.status.disabled"
    static let resourceGatewayAutoStartOn = "resource.gateway.auto_start.on"
    static let resourceGatewayAutoStartOff = "resource.gateway.auto_start.off"
    static let resourceGatewayRuntimeRunning = "resource.gateway.runtime.running"
    static let resourceGatewayRuntimeStopped = "resource.gateway.runtime.stopped"
    static let resourceGatewayRuntimeError = "resource.gateway.runtime.error"
    static let resourceGatewayRuntimeUnknown = "resource.gateway.runtime.unknown"
    static let resourceProviderToggleEnable = "resource.provider.toggle.enable"
    static let resourceProviderToggleDisable = "resource.provider.toggle.disable"
    static let resourceGatewayActionStart = "resource.gateway.action.start"
    static let resourceGatewayActionStop = "resource.gateway.action.stop"
    static let resourceHealthHealthy = "resource.health.healthy"
    static let resourceHealthDegraded = "resource.health.degraded"
    static let resourceHealthUnhealthy = "resource.health.unhealthy"
    static let resourceHealthProbing = "resource.health.probing"
    static let resourceHealthUnknown = "resource.health.unknown"
    static let gatewaysValueIdle = "gateways.value.idle"
    static let gatewaysRouteTargetWithHealth = "gateways.route_target.with_health"
    static let gatewaysHealthSummaryFormat = "gateways.health_summary.format"
    static let gatewaysHealthSummaryNone = "gateways.health_summary.none"

    static let logsFiltersTitle = "logs.filters.title"
    static let logsFiltersLoadedCount = "logs.filters.loaded_count"
    static let logsFiltersLoadedRequests = "logs.filters.loaded_requests"
    static let logsFiltersMoreAvailable = "logs.filters.more_available"
    static let logsFiltersGateway = "logs.filters.gateway"
    static let logsFiltersProvider = "logs.filters.provider"
    static let logsFiltersStatus = "logs.filters.status"
    static let logsFiltersErrorsOnly = "logs.filters.errors_only"
    static let logsFiltersClear = "logs.filters.clear"
    static let logsSectionsRequestStream = "logs.sections.request_stream"
    static let logsSectionsExecution = "logs.sections.execution"
    static let logsSectionsDiagnostics = "logs.sections.diagnostics"
    static let logsSectionsUsageJSON = "logs.sections.usage_json"
    static let logsEmptyFiltered = "logs.empty.filtered"
    static let logsActionsLoadMore = "logs.actions.load_more"
    static let logsActionsLoadingMore = "logs.actions.loading_more"
    static let logsDetailRequestID = "logs.detail.request_id"
    static let logsDetailProtocol = "logs.detail.protocol"
    static let logsDetailStream = "logs.detail.stream"
    static let logsDetailFirstByte = "logs.detail.first_byte"
    static let logsDetailTokens = "logs.detail.tokens"
    static let logsDetailErrorStage = "logs.detail.error_stage"
    static let logsDetailErrorType = "logs.detail.error_type"
    static let logsDetailError = "logs.detail.error"
    static let logsStreamStreaming = "logs.stream.streaming"
    static let logsStreamNonStream = "logs.stream.non_stream"

    static let topologyViewTitle = "topology.view.title"
    static let topologyViewSubtitle = "topology.view.subtitle"
    static let topologyControlsMetric = "topology.controls.metric"
    static let topologyControlsFlow = "topology.controls.flow"
    static let topologyControlsHighlight = "topology.controls.highlight"
    static let topologyColumnsEntrypoints = "topology.columns.entrypoints"
    static let topologyColumnsGateways = "topology.columns.gateways"
    static let topologyColumnsProviders = "topology.columns.providers"
    static let topologyMetricTokens = "topology.metric.tokens"
    static let topologyMetricRequests = "topology.metric.requests"
    static let topologyFlowByModel = "topology.flow.by_model"
    static let topologyFlowTotalOnly = "topology.flow.total_only"
    static let topologyHighlightTop3 = "topology.highlight.top3"
    static let topologyHighlightTop5 = "topology.highlight.top5"
    static let topologyHighlightAll = "topology.highlight.all"
    static let topologySummaryHotPaths = "topology.summary.hot_paths"
    static let topologySummaryModelMix = "topology.summary.model_mix"
    static let topologyEmptyActiveRoutes = "topology.empty.active_routes"
    static let topologyEmptyAwaitingTraffic = "topology.empty.awaiting_traffic"
    static let topologyHotPathTopModel = "topology.hot_path.top_model"
    static let topologyTooltipModel = "topology.tooltip.model"
    static let topologyLabelTotal = "topology.label.total"
    static let topologyMetricTokensShort = "topology.metric.tokens_short"
    static let topologyMetricRequestsShort = "topology.metric.requests_short"
    static let topologyMetricCachedShort = "topology.metric.cached_short"
    static let topologyMetricErrorsShort = "topology.metric.errors_short"
    static let topologyUnknownProvider = "topology.node.unknown_provider"

    static let adminErrorReferencedProviderConflict = "admin.error.provider_referenced_by_gateways"
    static let adminErrorRequestFailedHttp = "admin.error.request_failed_http"
    static let adminProviderProbeStarted = "admin.provider.notice.probe_started"
    static let adminGatewayUpdateSaved = "admin.gateway.notice.update_saved"
    static let adminGatewayUpdateSavedRestarted = "admin.gateway.notice.update_saved_restarted"
    static let adminGatewayUpdateSavedRestartFailed = "admin.gateway.notice.update_saved_restart_failed"
    static let adminGatewayDeleted = "admin.gateway.notice.deleted"
    static let adminGatewayDeletedStopped = "admin.gateway.notice.deleted_stopped"
    static let commonValueYes = "common.value.yes"
    static let commonValueNo = "common.value.no"
    static let overviewNetworkNoGateway = "overview.network.no_gateway"
    static let logsCompactPrefixKey = "logs.compact.prefix"
    static let logsCompactEmptyKey = "logs.compact.empty"
    static let logsCompactInputKey = "logs.compact.input"
    static let logsCompactOutputKey = "logs.compact.output"
    static let logsCompactCachedKey = "logs.compact.cached"
    static let logsCompactTotalKey = "logs.compact.total"
    static let trafficLabelOtherModel = "traffic.label.other_model"
    static let gatewayFormRouteTargetsPreviewTitle = "gateway_form.route_targets.preview_title"
    static let gatewayFormRouteTargetsPreviewCaption = "gateway_form.route_targets.preview_caption"
    static let gatewayFormRouteTargetsPrimary = "gateway_form.route_targets.primary"
    static let gatewayFormRouteTargetsBackup = "gateway_form.route_targets.backup"
    static let gatewayFormRouteTargetsDefault = "gateway_form.route_targets.default"
    static let gatewayFormRouteTargetsPickerProvider = "gateway_form.route_targets.picker_provider"
    static let gatewayFormRouteTargetsMoveUp = "gateway_form.route_targets.move_up"
    static let gatewayFormRouteTargetsMoveDown = "gateway_form.route_targets.move_down"
    static let gatewayFormRouteTargetsAdd = "gateway_form.route_targets.add"
    static let gatewayFormRouteTargetsPrimaryHint = "gateway_form.route_targets.primary_hint"

    static func string(_ key: String, locale: Locale = .autoupdatingCurrent) -> String {
        bundle(locale: locale).localizedString(forKey: key, value: key, table: nil)
    }

    static func formatted(_ key: String, locale: Locale = .autoupdatingCurrent, _ arguments: CVarArg...) -> String {
        let format = string(key, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    static func modelCount(_ count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let key = count == 1 ? "common.model_count.one" : "common.model_count.other"
        return formatted(key, locale: locale, Int64(count))
    }

    static func runningGatewayCount(_ count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let key = count == 1 ? "shell.status.gateway_count.one" : "shell.status.gateway_count.other"
        return formatted(key, locale: locale, Int64(count))
    }

    static func alertCount(_ count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let key = count == 1 ? "shell.status.alert_count.one" : "shell.status.alert_count.other"
        return formatted(key, locale: locale, Int64(count))
    }

    static func lastRefresh(_ text: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(shellToolbarLastRefresh, locale: locale, text)
    }

    static func shellConnectionState(_ state: ShellConnectionState, locale: Locale = .autoupdatingCurrent) -> String {
        switch state {
        case .syncing:
            return string(shellStatusConnectionSyncing, locale: locale)
        case .offline:
            return string(shellStatusConnectionOffline, locale: locale)
        case .connected:
            return string(shellStatusConnectionConnected, locale: locale)
        }
    }

    static func settingsStatus(_ status: SettingsPanelStatus, locale: Locale = .autoupdatingCurrent) -> String {
        switch status {
        case .needsAttention:
            return string(settingsStatusNeedsAttention, locale: locale)
        case .refreshing:
            return string(settingsStatusRefreshing, locale: locale)
        case .notConfigured:
            return string(settingsStatusNotConfigured, locale: locale)
        case .ready:
            return string(settingsStatusReady, locale: locale)
        }
    }

    static func overviewGatewayStatus(_ status: OverviewDashboardModel.GatewayStatus, locale: Locale = .autoupdatingCurrent) -> String {
        switch status {
        case .healthy:
            return string(overviewGatewayStatusHealthy, locale: locale)
        case .idle:
            return string(overviewGatewayStatusIdle, locale: locale)
        }
    }

    static func providerStatus(_ isEnabled: Bool, locale: Locale = .autoupdatingCurrent) -> String {
        string(isEnabled ? resourceProviderStatusEnabled : resourceProviderStatusDisabled, locale: locale)
    }

    static func autoStart(_ isEnabled: Bool, locale: Locale = .autoupdatingCurrent) -> String {
        string(isEnabled ? resourceGatewayAutoStartOn : resourceGatewayAutoStartOff, locale: locale)
    }

    static func providerToggleAction(isEnabled: Bool, locale: Locale = .autoupdatingCurrent) -> String {
        string(isEnabled ? resourceProviderToggleDisable : resourceProviderToggleEnable, locale: locale)
    }

    static func providerHealthStatus(_ status: String, locale: Locale = .autoupdatingCurrent) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "healthy":
            return string(resourceHealthHealthy, locale: locale)
        case "degraded":
            return string(resourceHealthDegraded, locale: locale)
        case "unhealthy":
            return string(resourceHealthUnhealthy, locale: locale)
        case "probing":
            return string(resourceHealthProbing, locale: locale)
        default:
            return string(resourceHealthUnknown, locale: locale)
        }
    }

    static func gatewayRuntimeStatus(_ category: GatewayRuntimeCategory, locale: Locale = .autoupdatingCurrent) -> String {
        switch category {
        case .running:
            return string(resourceGatewayRuntimeRunning, locale: locale)
        case .stopped:
            return string(resourceGatewayRuntimeStopped, locale: locale)
        case .error:
            return string(resourceGatewayRuntimeError, locale: locale)
        case .unknown:
            return string(resourceGatewayRuntimeUnknown, locale: locale)
        }
    }

    static func gatewayRuntimeAction(_ category: GatewayRuntimeCategory, locale: Locale = .autoupdatingCurrent) -> String {
        string(category == .running ? resourceGatewayActionStop : resourceGatewayActionStart, locale: locale)
    }

    static func logsLoaded(_ count: Int, hasMore: Bool, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(hasMore ? logsFiltersLoadedRequests : logsFiltersLoadedCount, locale: locale, Int64(count))
    }

    static func logsStream(_ isStreaming: Bool, locale: Locale = .autoupdatingCurrent) -> String {
        string(isStreaming ? logsStreamStreaming : logsStreamNonStream, locale: locale)
    }

    static func logsCompactInput(_ value: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(logsCompactInputKey, locale: locale, value)
    }

    static func logsCompactOutput(_ value: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(logsCompactOutputKey, locale: locale, value)
    }

    static func logsCompactCached(_ value: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(logsCompactCachedKey, locale: locale, value)
    }

    static func logsCompactTotal(_ value: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(logsCompactTotalKey, locale: locale, value)
    }

    static func topologyMetricTitle(_ mode: TopologyMetricMode, locale: Locale = .autoupdatingCurrent) -> String {
        string(mode.titleKey, locale: locale)
    }

    static func topologyFlowTitle(_ mode: TopologyFlowMode, locale: Locale = .autoupdatingCurrent) -> String {
        string(mode.titleKey, locale: locale)
    }

    static func topologyHighlightTitle(_ mode: TopologyHighlightMode, locale: Locale = .autoupdatingCurrent) -> String {
        string(mode.titleKey, locale: locale)
    }

    static func topologyHotPathTopModel(_ modelName: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(topologyHotPathTopModel, locale: locale, modelName)
    }

    static func topologyTooltipModel(_ modelName: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(topologyTooltipModel, locale: locale, modelName)
    }

    static func topologyTokenValue(_ value: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(topologyMetricTokensShort, locale: locale, value)
    }

    static func topologyRequestValue(_ value: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(topologyMetricRequestsShort, locale: locale, value)
    }

    static func topologyCachedValue(_ value: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(topologyMetricCachedShort, locale: locale, value)
    }

    static func topologyErrorValue(_ value: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(topologyMetricErrorsShort, locale: locale, value)
    }

    static func adminGatewayUpdateSaved(locale: Locale = .autoupdatingCurrent) -> String {
        string(adminGatewayUpdateSaved, locale: locale)
    }

    static func adminGatewayUpdateSavedRestarted(locale: Locale = .autoupdatingCurrent) -> String {
        string(adminGatewayUpdateSavedRestarted, locale: locale)
    }

    static func adminGatewayUpdateSavedRestartFailed(_ detail: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(adminGatewayUpdateSavedRestartFailed, locale: locale, detail)
    }

    static func adminGatewayDeleted(locale: Locale = .autoupdatingCurrent) -> String {
        string(adminGatewayDeleted, locale: locale)
    }

    static func adminGatewayDeletedStopped(locale: Locale = .autoupdatingCurrent) -> String {
        string(adminGatewayDeletedStopped, locale: locale)
    }

    static func adminErrorProviderReferencedByGateways(_ ids: String, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(adminErrorReferencedProviderConflict, locale: locale, ids)
    }

    static func adminErrorRequestFailedHttp(_ statusCode: Int, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(adminErrorRequestFailedHttp, locale: locale, Int64(statusCode))
    }

    static func durationMilliseconds(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        formatted(commonDurationMilliseconds, locale: locale, Int64(value))
    }

    private static func bundle(locale: Locale) -> Bundle {
        let languageCode = locale.language.languageCode?.identifier
        let scriptCode = locale.language.script?.identifier
        let regionCode = locale.region?.identifier

        let compositeCandidates = [
            [languageCode, scriptCode].compactMap { $0 }.joined(separator: "-"),
            [languageCode, regionCode].compactMap { $0 }.joined(separator: "-")
        ]

        let candidates = ([locale.identifier] + compositeCandidates + [languageCode].compactMap { $0 })
            .filter { !$0.isEmpty }

        for candidate in candidates {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }

        return .main
    }
}
