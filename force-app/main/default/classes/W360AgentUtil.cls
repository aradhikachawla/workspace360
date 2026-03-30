/**
 * W360AgentUtil
 * ─────────────────────────────────────────────────────────────────────────────
 * Shared input/output types and helper methods used by all three
 * Workspace 360 Agentforce action classes:
 *   - W360GetRecentIncidents
 *   - W360GetIncidentDetails
 *   - W360AnalyzeAllIncidents
 */
public with sharing class W360AgentUtil {

    // ── Input types ───────────────────────────────────────────────────────────

    public class IncidentRequest {
        @InvocableVariable(
            label       = 'Hours to look back'
            description = 'How many hours back to search for errors. Default 72. For today use hours=24 and sinceToday=true.'
        )
        public Integer hours;

        @InvocableVariable(
            label       = 'Since Today (midnight)'
            description = 'Set to true when the user asks about today specifically. Uses midnight of the current day as the cutoff instead of rolling hours.'
        )
        public Boolean sinceToday;

        @InvocableVariable(
            label       = 'Apex Class Name filter'
            description = 'Optional: filter results to a specific Apex class name'
        )
        public String className;
    }

    public class DetailRequest {
        @InvocableVariable(
            label       = 'Incident ID or Apex Class Name'
            description = 'The Id of a W360 incident record, or the name of an Apex class/job to look up'
        )
        public String incidentIdOrClass;

        @InvocableVariable(
            label       = 'Lookback Minutes'
            description = 'How many minutes before the error to scan for dev changes. Default 120.'
        )
        public Integer lookbackMinutes;
    }

    // ── Output types ──────────────────────────────────────────────────────────

    public class IncidentResponse {
        @InvocableVariable(label='Incident Summary'           description='One-line status: e.g. 4 incidents found (3 Critical, 1 Warning) in the last 120 hours.')
        public String  incidentSummary;

        @InvocableVariable(label='Incident Data' description='Numbered list of incidents: #1 Class - Error - Severity - Hits - When. One per line. Use this to show the full list.')
        public String  incidentData;

        // incidentCount intentionally removed from @InvocableVariable —
        // Agentforce was printing the raw integer (e.g. "2") as standalone output.
        // Count is already embedded in incidentSummary text.
        public Integer incidentCount;

        @InvocableVariable(label='Primary Incident Class'    description='Apex class name of the most critical incident, for use in follow-up GetIncidentDetails call')
        public String  primaryIncidentClass;

        @InvocableVariable(label='Report Data'  description='Used by AnalyzeAllIncidents only: full standup-style digest with correlated changes per incident')
        public String  reportData;
    }

    public class DetailResponse {
        @InvocableVariable(label='Root Cause Analysis'      description='Full AI-generated root-cause analysis')
        public String  rootCauseAnalysis;

        @InvocableVariable(label='Correlated Changes Summary' description='Dev changes found before the error')
        public String  correlatedChangesSummary;

        // devChangesCount intentionally removed from @InvocableVariable — same bare-number risk.
        public Integer devChangesCount;

        @InvocableVariable(label='Recommended Fix'          description='Specific fix extracted from the AI analysis')
        public String  recommendedFix;
    }

    // ── Shared helpers ────────────────────────────────────────────────────────

    /**
     * Find the most recent incident matching an Id or class name.
     */
    public static W360IncidentAnalyzer.IncidentRecord findIncident(String idOrClass) {
        if (String.isBlank(idOrClass)) return null;
        List<W360IncidentAnalyzer.IncidentRecord> all =
            W360IncidentAnalyzer.getRecentErrors(72);

        for (W360IncidentAnalyzer.IncidentRecord r : all) {
            if (idOrClass.equals(r.id)) return r;                                    // exact Id
        }
        for (W360IncidentAnalyzer.IncidentRecord r : all) {
            if (r.apexClass != null && r.apexClass.containsIgnoreCase(idOrClass)) return r; // class name
        }
        for (W360IncidentAnalyzer.IncidentRecord r : all) {
            if (r.errorMessage != null && r.errorMessage.containsIgnoreCase(idOrClass)) return r; // message
        }
        return null;
    }

    /**
     * Convert an ISO timestamp to a human-readable relative string.
     * e.g. "15 minutes ago", "2 hours ago"
     */
    public static String relativeTime(String isoTimestamp) {
        if (String.isBlank(isoTimestamp)) return 'unknown time';
        try {
            Datetime dt = (Datetime) JSON.deserialize('"' + isoTimestamp + '"', Datetime.class);
            Long mins = (Datetime.now().getTime() - dt.getTime()) / 60000;
            if (mins < 2)    return 'just now';
            if (mins < 60)   return mins + ' minutes ago';
            if (mins < 120)  return '1 hour ago';
            if (mins < 1440) return (mins / 60) + ' hours ago';
            return (mins / 1440) + ' days ago';
        } catch (Exception e) {
            return isoTimestamp;
        }
    }

    /**
     * One-line status: "4 incidents found (3 Critical, 1 Warning) in the last 120 hours."
     */
    public static String buildStatusLine(
        List<W360IncidentAnalyzer.IncidentRecord> incidents, Integer hours
    ) {
        return buildStatusLine(incidents, hours, false);
    }

    public static String buildStatusLine(
        List<W360IncidentAnalyzer.IncidentRecord> incidents, Integer hours, Boolean sinceToday
    ) {
        String windowLabel = (sinceToday == true) ? 'today' : 'the last ' + hours + ' hours';
        if (incidents.isEmpty()) {
            return 'No production errors in ' + windowLabel + '. All systems healthy.';
        }
        Integer critCount = 0, warnCount = 0;
        for (W360IncidentAnalyzer.IncidentRecord inc : incidents) {
            if ('Critical'.equalsIgnoreCase(inc.severity)) critCount++;
            else warnCount++;
        }
        return incidents.size() + ' incident'
            + (incidents.size() > 1 ? 's' : '') + ' found in ' + windowLabel + ' ('
            + critCount + ' Critical, ' + warnCount + ' Warning).';
    }

    /**
     * Numbered incident list. Each line: #N Class - Error - Severity - Nx hits - When
     * The agent uses this directly — no other formatting needed.
     */
    public static String buildNumberedList(
        List<W360IncidentAnalyzer.IncidentRecord> incidents
    ) {
        List<String> lines = new List<String>();
        for (Integer i = 0; i < incidents.size(); i++) {
            W360IncidentAnalyzer.IncidentRecord inc = incidents[i];
            String errShort = inc.errorMessage != null ? inc.errorMessage.left(100) : 'No details';
            Integer dotIdx  = errShort.indexOf('.');
            if (dotIdx > 0 && dotIdx < 80) errShort = errShort.left(dotIdx);
            lines.add(
                '#' + (i + 1) + ' ' + (inc.apexClass != null ? inc.apexClass : 'Unknown')
                + ' — ' + errShort
                + ' — ' + (inc.severity != null ? inc.severity : 'Unknown')
                + ' — ' + (inc.hitCount != null ? inc.hitCount : 1) + ' hit'
                + (inc.hitCount != null && inc.hitCount > 1 ? 's' : '')
                + ' — ' + relativeTime(inc.occurredAt)
            );
        }
        return String.join(lines, '\n');
    }
}