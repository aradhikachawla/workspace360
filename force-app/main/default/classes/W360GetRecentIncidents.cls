/**
 * W360GetRecentIncidents
 * ─────────────────────────────────────────────────────────────────────────────
 * Agentforce action: "What errors are happening in this org?"
 *
 * Queries AsyncApexJob (real failed jobs), W360_Incident_Log__c (demo), and
 * ApexLog, then returns a plain-English summary the agent relays to the user.
 *
 * Example agent triggers:
 *   "What broke today?"
 *   "Any errors in the last 24 hours?"
 *   "Is OpportunityBatchJob failing?"
 *   "Show me production errors"
 */
public with sharing class W360GetRecentIncidents {

    @InvocableMethod(
        label       = 'W360: Get Recent Production Incidents'
        description = 'Queries AsyncApexJob, ApexLog, and the W360 incident log for recent errors. Returns a plain-English summary of what is failing and how many times.'
        category    = 'Workspace360'
    )
    public static List<W360AgentUtil.IncidentResponse> getRecentIncidents(
        List<W360AgentUtil.IncidentRequest> requests
    ) {
        List<W360AgentUtil.IncidentResponse> responses = new List<W360AgentUtil.IncidentResponse>();

        for (W360AgentUtil.IncidentRequest req : requests) {
            W360AgentUtil.IncidentResponse resp = new W360AgentUtil.IncidentResponse();
            try {
                Integer hours = (req.hours != null && req.hours > 0) ? req.hours : 72;
                Boolean sinceToday = (req.sinceToday == true);
                List<W360IncidentAnalyzer.IncidentRecord> incidents =
                    W360IncidentAnalyzer.getRecentErrors(hours, sinceToday);

                // Optional class name filter
                if (String.isNotBlank(req.className)) {
                    List<W360IncidentAnalyzer.IncidentRecord> filtered =
                        new List<W360IncidentAnalyzer.IncidentRecord>();
                    for (W360IncidentAnalyzer.IncidentRecord inc : incidents) {
                        if (inc.apexClass != null &&
                            inc.apexClass.containsIgnoreCase(req.className)) {
                            filtered.add(inc);
                        }
                    }
                    incidents = filtered;
                }

                resp.incidentCount = incidents.size();

                if (incidents.isEmpty()) {
                    // No errors in this window — check last 7 days to give context
                    List<W360IncidentAnalyzer.IncidentRecord> recent7 =
                        W360IncidentAnalyzer.getRecentErrors(168, false);
                    if (!recent7.isEmpty()) {
                        String windowLabel = sinceToday ? 'today' : 'the last ' + hours + ' hours';
                        resp.incidentSummary = 'No errors in ' + windowLabel + '. '
                            + 'Note: ' + recent7.size() + ' incident'
                            + (recent7.size() > 1 ? 's were' : ' was')
                            + ' found in the last 7 days. The most recent was '
                            + W360AgentUtil.relativeTime(recent7[0].occurredAt)
                            + ' in ' + recent7[0].apexClass + ' (' + recent7[0].severity + '). '
                            + 'To see them, ask: any errors in the last 7 days?';
                    } else {
                        String windowLabel = sinceToday ? 'today' : 'the last ' + hours + ' hours';
                        resp.incidentSummary = 'No production errors in ' + windowLabel
                            + ' — org looks healthy.';
                    }
                } else {
                    resp.incidentSummary = W360AgentUtil.buildStatusLine(incidents, hours, sinceToday);
                    resp.incidentData = W360AgentUtil.buildNumberedList(incidents);
                    resp.primaryIncidentClass = incidents[0].apexClass;
                }
            } catch (Exception e) {
                resp.incidentSummary    = 'Unable to retrieve incident data: ' + e.getMessage();
                resp.incidentCount = 0;
            }
            responses.add(resp);
        }
        return responses;
    }
}