/**
 * W360GetIncidentDetails
 * ─────────────────────────────────────────────────────────────────────────────
 * Agentforce action: "Why did [class/job] fail? What changed before it?"
 *
 * Given an Apex class name or incident ID:
 *   1. Finds the most recent matching error
 *   2. Queries SetupAuditTrail for dev changes in the 2 hours before
 *   3. Runs AI root-cause analysis combining error + changes
 *   4. Returns a full explanation the agent can relay
 *
 * Example agent triggers:
 *   "Why is OpportunityBatchProcessor failing?"
 *   "What changed before the LeadConversionFlow error?"
 *   "Who deployed something that broke the nightly job?"
 *   "Explain the error in AccountSyncBatch"
 */
public with sharing class W360GetIncidentDetails {

    @InvocableMethod(
        label       = 'W360: Get Incident Details with Dev Changes'
        description = 'Finds the most recent error for a given Apex class or job name, correlates it with SetupAuditTrail changes from the 2 hours before, then returns an AI root-cause analysis explaining what deployment caused the error and how to fix it.'
        category    = 'Workspace360'
    )
    public static List<W360AgentUtil.DetailResponse> getIncidentDetails(
        List<W360AgentUtil.DetailRequest> requests
    ) {
        List<W360AgentUtil.DetailResponse> responses = new List<W360AgentUtil.DetailResponse>();

        for (W360AgentUtil.DetailRequest req : requests) {
            W360AgentUtil.DetailResponse resp = new W360AgentUtil.DetailResponse();
            try {
                Integer lookback = (req.lookbackMinutes != null && req.lookbackMinutes > 0)
                    ? req.lookbackMinutes : 120;

                // Find the matching incident
                W360IncidentAnalyzer.IncidentRecord incident =
                    W360AgentUtil.findIncident(req.incidentIdOrClass);

                if (incident == null) {
                    resp.rootCauseAnalysis =
                        'No recent error found matching "' + req.incidentIdOrClass + '". '
                        + 'The class or job may not have failed in the last 72 hours, '
                        + 'or may not yet be tracked. Try checking the Incidents tab in Workspace 360.';
                    resp.devChangesCount = 0;
                    responses.add(resp);
                    continue;
                }

                // Get correlated dev changes from SetupAuditTrail
                // Pass class name + exception type so the relevance filter can exclude
                // unrelated declarative changes (e.g. Validation Rules for a SOQL limit error)
                List<W360IncidentAnalyzer.DevChangeRecord> changes =
                    String.isNotBlank(incident.occurredAt)
                        ? W360IncidentAnalyzer.getCorrelatedChangesInternal(
                              incident.occurredAt, lookback,
                              incident.apexClass, incident.exceptionType)
                        : new List<W360IncidentAnalyzer.DevChangeRecord>();

                resp.devChangesCount = changes.size();

                // Build correlated changes plain-English summary
                if (changes.isEmpty()) {
                    resp.correlatedChangesSummary =
                        'No dev changes found in the ' + lookback + ' minutes before this error. '
                        + 'The root cause may be data-related rather than a code deployment.';
                } else {
                    List<String> parts = new List<String>();
                    for (W360IncidentAnalyzer.DevChangeRecord c : changes) {
                        parts.add(c.component + ' (' + c.section + ') — ' + c.minutesBefore);
                    }
                    resp.correlatedChangesSummary =
                        changes.size() + ' dev change' + (changes.size() > 1 ? 's' : '')
                        + ' found before the error:\n'
                        + String.join(parts, '\n');
                }

                // Run AI root-cause analysis
                String analysis = W360IncidentAnalyzer.analyzeIncident(
                    incident.errorMessage,
                    incident.exceptionType,
                    incident.stackTrace,
                    JSON.serialize(changes)
                );

                resp.rootCauseAnalysis =
                    'Error in ' + incident.apexClass
                    + ' (' + W360AgentUtil.relativeTime(incident.occurredAt) + '):\n'
                    + incident.errorMessage + '\n\n'
                    + 'DEV CHANGES BEFORE ERROR:\n' + resp.correlatedChangesSummary + '\n\n'
                    + 'ROOT CAUSE:\n' + analysis;

                // Extract the fix recommendation
                String lowerAnalysis = analysis.toLowerCase();
                Integer fixIdx = lowerAnalysis.lastIndexOf('fix:');
                if (fixIdx < 0) fixIdx = lowerAnalysis.lastIndexOf('• fix');
                if (fixIdx >= 0) {
                    resp.recommendedFix = analysis.substring(fixIdx).left(300).trim();
                }

            } catch (Exception e) {
                resp.rootCauseAnalysis = 'Error retrieving incident details: ' + e.getMessage();
                resp.devChangesCount   = 0;
            }
            responses.add(resp);
        }
        return responses;
    }
}