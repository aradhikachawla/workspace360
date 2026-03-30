/**
 * W360AnalyzeAllIncidents
 * ─────────────────────────────────────────────────────────────────────────────
 * Agentforce action: "Morning health check — what broke and what caused it?"
 *
 * Pulls ALL recent errors and for each one automatically finds the most
 * likely culprit in SetupAuditTrail. Returns a digest the agent can read
 * out as a standup-style summary.
 *
 * Example agent triggers:
 *   "Give me a production health report"
 *   "What broke overnight?"
 *   "Morning standup — what failed and why?"
 *   "Post-deployment health check"
 *   "What did the team deploy that caused errors?"
 */
public with sharing class W360AnalyzeAllIncidents {

    @InvocableMethod(
        label       = 'W360: Production Health Report'
        description = 'Fetches all recent production errors (AsyncApexJob failures, ApexLog errors, and W360 incident log) and for each error finds the most likely culprit in SetupAuditTrail. Returns a standup-style digest: what failed, when, and which recent deployment most likely caused it.'
        category    = 'Workspace360'
    )
    public static List<W360AgentUtil.IncidentResponse> analyzeAllIncidents(
        List<W360AgentUtil.IncidentRequest> requests
    ) {
        List<W360AgentUtil.IncidentResponse> responses = new List<W360AgentUtil.IncidentResponse>();

        for (W360AgentUtil.IncidentRequest req : requests) {
            W360AgentUtil.IncidentResponse resp = new W360AgentUtil.IncidentResponse();
            try {
                Integer hours = (req.hours != null && req.hours > 0) ? req.hours : 24;
                List<W360IncidentAnalyzer.IncidentRecord> incidents =
                    W360IncidentAnalyzer.getRecentErrors(hours);

                resp.incidentCount = incidents.size();

                if (incidents.isEmpty()) {
                    resp.reportData = 'Production Health Report (last ' + hours + ' hours):\n\n'
                        + '✅ No errors found. All systems are healthy.';
                    responses.add(resp);
                    continue;
                }

                // Build per-incident digest lines, top 5 max to avoid response size limits
                List<String> lines = new List<String>();
                Integer limit5 = Math.min(incidents.size(), 5);

                for (Integer i = 0; i < limit5; i++) {
                    W360IncidentAnalyzer.IncidentRecord inc = incidents[i];
                    if (String.isBlank(inc.occurredAt)) continue;

                    // Get correlated changes for this incident
                    List<W360IncidentAnalyzer.DevChangeRecord> changes =
                        W360IncidentAnalyzer.getCorrelatedChangesInternal(inc.occurredAt, 120, inc.apexClass, inc.exceptionType);

                    String severity = '🔴';
                    if ('Warning'.equalsIgnoreCase(inc.severity)) severity = '🟡';
                    if ('Info'.equalsIgnoreCase(inc.severity))    severity = '🔵';

                    String line = severity + ' ' + inc.apexClass
                        + ' [' + inc.hitCount + 'x] '
                        + W360AgentUtil.relativeTime(inc.occurredAt) + '\n'
                        + '   Error: ' + (inc.errorMessage != null
                            ? inc.errorMessage.left(120) : 'No details');

                    if (!changes.isEmpty()) {
                        // Show the most recent correlated change (closest to the error)
                        W360IncidentAnalyzer.DevChangeRecord topChange = changes[0];
                        line += '\n   Likely cause: ' + topChange.component
                            + ' (' + topChange.section + ')'
                            + ' — ' + topChange.minutesBefore;
                    } else {
                        line += '\n   No dev changes found in the 2-hour window.';
                    }

                    lines.add(line);
                }

                String footer = incidents.size() > 5
                    ? '\n\n...and ' + (incidents.size() - 5) + ' more incident'
                      + (incidents.size() - 5 > 1 ? 's' : '') + '. '
                      + 'Open Workspace 360 → Incidents tab for the full list.'
                    : '';

                resp.reportData = 'Production Health Report (last ' + hours + ' hours):\n\n'
                    + String.join(lines, '\n\n')
                    + footer;

                // Top incident class name for agent follow-up
                resp.primaryIncidentClass = incidents[0].apexClass;

            } catch (Exception e) {
                resp.reportData = 'Unable to generate health report: ' + e.getMessage();
            }
            responses.add(resp);
        }
        return responses;
    }
}