/**
 * AgentforceSummary
 * Calls the Agentforce / Einstein Generative AI platform to produce a natural-language
 * summary of yesterday's workspace activity and suggest next best actions.
 *
 * Prerequisites:
 *   • Named Credential: "Agentforce_API" pointing to your Einstein Generative AI endpoint
 *   • Permission Set: Einstein_GPT_User assigned to users
 *
 * @author   Workspace 360 Hackathon Team
 * @version  1.0
 */
public with sharing class AgentforceSummary {

    private static final String NAMED_CREDENTIAL = 'callout:Agentforce_API';
    private static final String MODEL_ID         = 'sfdc_ai__DefaultGPT35Turbo'; // swap for GPT-4 / Claude if licensed

    // ─── Public API ───────────────────────────────────────────────────────────

    /**
     * generateSummary – called from LWC on dashboard load.
     * Builds a context payload from yesterday's records and calls Einstein GenAI.
     */
    @AuraEnabled
    public static String generateSummary(List<User_Workspace_Context__c> contextRecords) {
        if (contextRecords == null || contextRecords.isEmpty()) {
            return 'No activity found from yesterday. Ready to start fresh!';
        }

        String prompt = buildPrompt(contextRecords);
        try {
            return callEinsteinGenAI(prompt);
        } catch (Exception e) {
            // Graceful degradation – return a rule-based summary
            return buildFallbackSummary(contextRecords);
        }
    }

    /**
     * generateSummaryAsync – future method for non-blocking generation.
     */
    @future(callout=true)
    public static void generateSummaryAsync(Set<Id> contextIds) {
        List<User_Workspace_Context__c> records = [
            SELECT Record_Name__c, Object_Type__c, Action_Type__c,
                   Stage__c, Amount__c, Session_Timestamp__c
            FROM   User_Workspace_Context__c
            WHERE  Id IN :contextIds
        ];
        String summary = generateSummary(records);
        // Store back on the most recent record
        if (!records.isEmpty()) {
            records[0].AI_Summary__c = summary;
            update records[0];
        }
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private static String buildPrompt(List<User_Workspace_Context__c> records) {
        String userName = UserInfo.getFirstName();
        String sb = 'You are an AI assistant embedded in Salesforce. ';
        sb += 'Provide a concise, action-oriented summary (max 120 words) for ' + userName + ' ';
        sb += 'based on their activity from yesterday. Focus on: open items, ';
        sb += 'recommendations for today, and any high-priority records. ';
        sb += 'Use plain English. Do not use bullet points.\n\nActivity log:\n';

        for (User_Workspace_Context__c r : records) {
            sb += '- ' + r.Action_Type__c + ' on ' + r.Object_Type__c
                + ' "' + r.Record_Name__c + '"';
            if (r.Stage__c != null) sb += ' [Stage: ' + r.Stage__c + ']';
            if (r.Amount__c != null) sb += ' [Amount: $' + r.Amount__c.format() + ']';
            sb += '\n';
        }
        return sb;
    }

    private static String callEinsteinGenAI(String prompt) {
        // Build request per Salesforce Einstein Generative AI REST API spec
        Map<String, Object> payload = new Map<String, Object>{
            'prompt'      => prompt,
            'numGenerations' => 1,
            'parameters'  => new Map<String, Object>{
                'temperature' => 0.4,
                'maxTokens'   => 200
            }
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint(NAMED_CREDENTIAL + '/v1/generations');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-sfdc-app-context', 'EinsteinGPT');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(10000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 200) {
            Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> generations = (List<Object>) resp.get('generations');
            if (generations != null && !generations.isEmpty()) {
                Map<String, Object> gen = (Map<String, Object>) generations[0];
                return (String) gen.get('text');
            }
        }
        throw new CalloutException('Einstein GenAI returned status ' + res.getStatusCode());
    }

    private static String buildFallbackSummary(List<User_Workspace_Context__c> records) {
        Integer edits     = 0;
        Integer views     = 0;
        Integer approvals = 0;
        for (User_Workspace_Context__c r : records) {
            if (r.Action_Type__c == 'Edit')    edits++;
            if (r.Action_Type__c == 'View')    views++;
            if (r.Action_Type__c == 'Approve') approvals++;
        }
        String summary = 'Yesterday you were active across ' + records.size() + ' records — ';
        summary += edits + ' edits, ' + views + ' record views';
        if (approvals > 0) summary += ', and ' + approvals + ' approvals';
        summary += '. Pick up where you left off using the Resume Session button below.';
        return summary;
    }

    // ─── SysAdmin / Dev summary ───────────────────────────────────────────────

    /**
     * generateDevSummary — called for SysAdmin dashboard.
     * Summarises recent production incidents and latest dev activity (SetupAuditTrail).
     */
    @AuraEnabled
    public static String generateDevSummary() {
        try {
            // Get recent incidents (last 24 hours first, fall back to 7 days)
            List<W360IncidentAnalyzer.IncidentRecord> incidents =
                W360IncidentAnalyzer.getRecentErrors(24);
            if (incidents.isEmpty()) {
                incidents = W360IncidentAnalyzer.getRecentErrors(168);
            }

            // Get recent dev activity (last 7 days, current user)
            List<WorkspaceLogger.DevActivityRaw> devActivity =
                WorkspaceLogger.getDevActivity(7);

            return buildDevFallbackSummary(incidents, devActivity);
        } catch (Exception e) {
            return 'Unable to load production summary: ' + e.getMessage();
        }
    }

    private static String buildDevFallbackSummary(
        List<W360IncidentAnalyzer.IncidentRecord> incidents,
        List<WorkspaceLogger.DevActivityRaw> devActivity
    ) {
        String summary = '';

        // Incident part
        if (incidents.isEmpty()) {
            summary += 'No production errors in the last 7 days — org looks healthy. ';
        } else {
            Integer critCount = 0;
            for (W360IncidentAnalyzer.IncidentRecord inc : incidents) {
                if ('Critical'.equalsIgnoreCase(inc.severity)) critCount++;
            }
            W360IncidentAnalyzer.IncidentRecord top = incidents[0];
            String whenWhen = W360AgentUtil.relativeTime(top.occurredAt);
            summary += critCount + ' critical incident' + (critCount != 1 ? 's' : '')
                + ' detected. Most recent: ' + top.apexClass
                + ' — ' + (top.errorMessage != null ? top.errorMessage.left(80) : '')
                + ' (' + whenWhen + '). ';
        }

        // Dev activity part
        if (!devActivity.isEmpty()) {
            summary += 'Latest deployment: ' + devActivity[0].Display + '.';
        }

        return summary;
    }
    
    
    
    
    
}