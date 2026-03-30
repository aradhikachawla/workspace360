/**
 * W360IncidentAnalyzer
 * ─────────────────────────────────────────────────────────────────────────────
 * Powers the Workspace 360 "Prod Incidents" tab.
 *
 * Responsibilities:
 *   1. getRecentErrors()      — Query ApexLog / EventLogFile for recent exceptions
 *   2. getCorrelatedChanges() — Given an error timestamp, return dev changes made
 *                               BEFORE that error that are likely root-cause candidates
 *   3. analyzeIncident()      — Agentforce AI: correlate error message + dev changes
 *                               and produce a plain-English root-cause analysis
 *
 * Sample data helper (for demo / scratch orgs):
 *   seedDemoIncidents()       — Insert fake ApexLog-style records into a
 *                               W360_Incident_Log__c custom object so you can
 *                               test without real errors.  See the companion
 *                               Workspace360IncidentSeeder.cls for setup.
 */
public with sharing class W360IncidentAnalyzer {

    // ── Inner DTO classes ─────────────────────────────────────────────────────

    public class IncidentRecord {
        @AuraEnabled public String  id            { get; set; }
        @AuraEnabled public String  errorMessage  { get; set; }
        @AuraEnabled public String  exceptionType { get; set; }
        @AuraEnabled public String  stackTrace    { get; set; }
        @AuraEnabled public String  apexClass     { get; set; }
        @AuraEnabled public String  triggeredBy   { get; set; }
        @AuraEnabled public String  occurredAt    { get; set; }  // ISO string
        @AuraEnabled public String  severity      { get; set; }  // Critical / Warning / Info
        @AuraEnabled public Integer hitCount      { get; set; }
        @AuraEnabled public String  source        { get; set; }  // 'ApexLog' | 'Demo'
    }

    public class DevChangeRecord {
        @AuraEnabled public String action       { get; set; }
        @AuraEnabled public String section      { get; set; }
        @AuraEnabled public String component    { get; set; }
        @AuraEnabled public String detail       { get; set; }
        @AuraEnabled public String changedAt    { get; set; }  // ISO string
        @AuraEnabled public String minutesBefore { get; set; } // e.g. "12 min before error"
    }

    public class IncidentContext {
        @AuraEnabled public IncidentRecord      incident    { get; set; }
        @AuraEnabled public List<DevChangeRecord> devChanges { get; set; }
        @AuraEnabled public String              aiAnalysis  { get; set; }
    }

    // ── 1. Fetch recent errors ────────────────────────────────────────────────
    /**
     * Returns recent error incidents from three sources, merged and sorted:
     *   (a) AsyncApexJob           — REAL batch/queueable/scheduled job failures
     *   (b) W360_Incident_Log__c   — demo/custom log object
     *   (c) ApexLog                — Apex debug logs flagged as errors
     *
     * AsyncApexJob is the primary real-org source. It surfaces every failed
     * Batch, Queueable, Scheduled, and Future job automatically with the full
     * ExtendedStatus exception message — no org setup needed.
     */
    @AuraEnabled(cacheable=false)
    public static List<IncidentRecord> getRecentErrors(Integer hours) {
        return getRecentErrors(hours, false);
    }

    @AuraEnabled(cacheable=false)
    public static List<IncidentRecord> getRecentErrorsSinceToday(Integer hours) {
        return getRecentErrors(hours, true);
    }

    public static List<IncidentRecord> getRecentErrors(Integer hours, Boolean sinceToday) {
        if (hours == null || hours < 1) hours = 72;
        Datetime cutoff;
        if (sinceToday == true) {
            // Midnight of today in org local time
            Date today = Date.today();
            cutoff = Datetime.newInstance(today, Time.newInstance(0, 0, 0, 0));
        } else {
            cutoff = Datetime.now().addHours(-hours);
        }
        List<IncidentRecord> results = new List<IncidentRecord>();

        // ── (a) AsyncApexJob — real failed jobs (PRIMARY source) ─────────────
        // Covers: BatchApex, Queueable, ScheduledApex, Future, Platform Events.
        // ExtendedStatus contains the actual exception message from the job run.
        try {
            List<AsyncApexJob> failedJobs = [
                SELECT Id, ApexClass.Name, JobType, Status,
                       ExtendedStatus, NumberOfErrors,
                       CreatedDate, CompletedDate,
                       CreatedBy.Name, MethodName
                FROM   AsyncApexJob
                WHERE  CreatedDate >= :cutoff
                AND    Status IN ('Failed', 'Aborted')
                ORDER BY CreatedDate DESC
                LIMIT  50
            ];
            for (AsyncApexJob job : failedJobs) {
                IncidentRecord r = new IncidentRecord();
                r.id            = job.Id;
                r.errorMessage  = String.isNotBlank(job.ExtendedStatus)
                    ? job.ExtendedStatus
                    : job.Status + ' — no extended status available';
                r.exceptionType = job.JobType + 'Job';
                r.stackTrace    = 'Job Type: ' + job.JobType
                    + '\nApex Class: ' + (job.ApexClass != null ? job.ApexClass.Name : 'Unknown')
                    + (String.isNotBlank(job.MethodName) ? '\nMethod: ' + job.MethodName : '')
                    + '\nRecords with Errors: ' + job.NumberOfErrors
                    + '\nFinal Status: ' + job.Status;
                r.apexClass     = job.ApexClass != null ? job.ApexClass.Name : 'Unknown';
                r.triggeredBy   = 'Async job — enqueued by '
                    + (job.CreatedBy != null ? job.CreatedBy.Name : 'System');
                r.occurredAt    = (job.CompletedDate != null ? job.CompletedDate : job.CreatedDate)
                    .formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
                r.severity      = job.NumberOfErrors > 5 ? 'Critical' : 'Warning';
                r.hitCount      = job.NumberOfErrors > 0 ? job.NumberOfErrors : 1;
                r.source        = 'AsyncApexJob';
                results.add(r);
            }
        } catch (Exception e) {
            System.debug('W360IncidentAnalyzer: AsyncApexJob query failed — ' + e.getMessage());
        }

        // ── (b) Demo / Custom incident log ────────────────────────────────────
        try {
            List<W360_Incident_Log__c> demoLogs = [
                SELECT Id, Error_Message__c, Exception_Type__c, Stack_Trace__c,
                       Apex_Class__c, Triggered_By__c, Occurred_At__c,
                       Severity__c, Hit_Count__c
                FROM   W360_Incident_Log__c
                WHERE  Occurred_At__c >= :cutoff
                ORDER BY Occurred_At__c DESC
                LIMIT  50
            ];
            for (W360_Incident_Log__c log : demoLogs) {
                IncidentRecord r = new IncidentRecord();
                r.id            = log.Id;
                r.errorMessage  = log.Error_Message__c;
                r.exceptionType = log.Exception_Type__c;
                r.stackTrace    = log.Stack_Trace__c;
                r.apexClass     = log.Apex_Class__c;
                r.triggeredBy   = log.Triggered_By__c;
                r.occurredAt    = log.Occurred_At__c != null
                    ? log.Occurred_At__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : null;
                r.severity      = log.Severity__c;
                r.hitCount      = log.Hit_Count__c != null ? Integer.valueOf(log.Hit_Count__c) : 1;
                r.source        = 'Demo';
                results.add(r);
            }
        } catch (Exception e) {
            System.debug('W360IncidentAnalyzer: W360_Incident_Log__c not available — ' + e.getMessage());
        }

        // ── (c) ApexLog (error-level entries) ────────────────────────────────
        try {
            List<ApexLog> apexLogs = [
                SELECT Id, Operation, Request, Status, SystemModstamp
                FROM   ApexLog
                WHERE  SystemModstamp >= :cutoff
                AND    Status != 'Success'
                ORDER BY SystemModstamp DESC
                LIMIT  20
            ];
            for (ApexLog al : apexLogs) {
                IncidentRecord r = new IncidentRecord();
                r.id            = al.Id;
                r.errorMessage  = al.Status + ' — ' + al.Operation;
                r.exceptionType = 'ApexLog';
                r.apexClass     = al.Operation;
                r.triggeredBy   = al.Request;
                r.occurredAt    = al.SystemModstamp != null
                    ? al.SystemModstamp.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : null;
                r.severity      = 'Warning';
                r.hitCount      = 1;
                r.source        = 'ApexLog';
                results.add(r);
            }
        } catch (Exception e) {
            System.debug('W360IncidentAnalyzer: ApexLog query failed — ' + e.getMessage());
        }

        // Deduplicate by Apex class name only — same class = same incident regardless of message variant
        // Keep the record with the highest hitCount and best severity (Critical beats Warning)
        Map<String, IncidentRecord> deduped = new Map<String, IncidentRecord>();
        for (IncidentRecord r : results) {
            String key = (r.apexClass != null ? r.apexClass.toLowerCase() : 'unknown');
            if (!deduped.containsKey(key)) {
                deduped.put(key, r);
            } else {
                IncidentRecord existing = deduped.get(key);
                Integer existHits = existing.hitCount != null ? existing.hitCount : 1;
                Integer newHits   = r.hitCount != null ? r.hitCount : 1;
                // Prefer Critical over Warning; then prefer higher hit count
                Boolean newIsCritical      = 'Critical'.equalsIgnoreCase(r.severity);
                Boolean existingIsCritical = 'Critical'.equalsIgnoreCase(existing.severity);
                if ((newIsCritical && !existingIsCritical) || newHits > existHits) {
                    // Merge: keep highest hit count, critical severity, and best stack trace
                    r.hitCount = Math.max(newHits, existHits);
                    r.severity = 'Critical';
                    // Prefer the entry with a detailed stack trace
                    if (String.isBlank(r.stackTrace) && String.isNotBlank(existing.stackTrace)) {
                        r.stackTrace = existing.stackTrace;
                    }
                    deduped.put(key, r);
                }
            }
        }

        // Sort deduplicated results by occurredAt descending
        List<IncidentRecord> unique = deduped.values();
        unique.sort(new IncidentComparator());
        if (unique.size() <= 30) return unique;
        List<IncidentRecord> trimmed = new List<IncidentRecord>();
        for (Integer i = 0; i < 30; i++) trimmed.add(unique[i]);
        return trimmed;
    }


    // ── 2. Correlate dev changes to an error timestamp ────────────────────────

    /**
     * Given an error's ISO timestamp and the failing class/component name,
     * returns SetupAuditTrail entries made within [lookbackMinutes] BEFORE the
     * error that are plausibly related to it.
     *
     * Relevance rules (applied in order, highest score wins):
     *   +3  Component name contains a token from the failing class name
     *   +2  Same Salesforce object is referenced in both component name and class name
     *   +1  Same metadata type as the error (e.g. Apex error → Apex changes ranked higher)
     *    0  Everything else (timing only) — included but ranked last
     *  SKIP  Validation Rules / Workflow Rules / Custom Fields when the failing
     *        component is a pure Apex class with a governor-limit error — these
     *        are declarative changes that cannot cause SOQL/CPU limit exceptions.
     *
     * Default lookback: 120 minutes (2 hours before the error).
     */
    @AuraEnabled(cacheable=false)
    public static List<DevChangeRecord> getCorrelatedChanges(
        String errorTimestampIso,
        Integer lookbackMinutes
    ) {
        return getCorrelatedChangesInternal(errorTimestampIso, lookbackMinutes, null, null);
    }

    // Internal method called by Apex (W360GetIncidentDetails, W360AnalyzeAllIncidents).
    // Not @AuraEnabled — Salesforce does not permit @AuraEnabled overloads.
    public static List<DevChangeRecord> getCorrelatedChangesInternal(
        String errorTimestampIso,
        Integer lookbackMinutes,
        String failingClassName,
        String exceptionType
    ) {
        if (String.isBlank(errorTimestampIso)) return new List<DevChangeRecord>();
        if (lookbackMinutes == null || lookbackMinutes < 1) lookbackMinutes = 120;

        Datetime errorTime;
        try {
            errorTime = (Datetime) JSON.deserialize('"' + errorTimestampIso + '"', Datetime.class);
        } catch (Exception e) {
            return new List<DevChangeRecord>();
        }

        Datetime windowStart = errorTime.addMinutes(-lookbackMinutes);

        // Is this a governor-limit error? (SOQL/CPU/heap limits are caused by Apex/Flow logic,
        // never by declarative metadata like Validation Rules or custom fields alone.)
        // Errors that are NEVER caused by declarative metadata changes
        // (Validation Rules / Workflow Rules / Custom Fields cannot cause these)
        // Note: DmlException is intentionally excluded — REQUIRED_FIELD_MISSING and
        // FIELD_CUSTOM_VALIDATION_EXCEPTION can legitimately be caused by validation rules.
        Boolean isGovernorLimitError = String.isNotBlank(exceptionType)
            && (exceptionType.containsIgnoreCase('LimitException')
                || exceptionType.containsIgnoreCase('UNABLE_TO_LOCK_ROW')
                || exceptionType.containsIgnoreCase('CalloutException')
                || exceptionType.containsIgnoreCase('NullPointerException'));

        // Tokenise the failing class name for relevance matching
        // e.g. "OpportunityTriggerHandler" → ['opportunity', 'trigger', 'handler']
        Set<String> classTokens = new Set<String>();
        if (String.isNotBlank(failingClassName)) {
            // Split on capital letters (camelCase / PascalCase) and underscores
            String spaced = failingClassName.replaceAll('([A-Z])', ' $1').toLowerCase();
            for (String tok : spaced.split('[_\\s]+')) {
                if (tok.length() > 3) classTokens.add(tok.trim());
            }
        }

        Set<String> devSections = new Set<String>{
            'Apex Class', 'Apex Classes', 'Apex Trigger', 'Apex Triggers',
            'Lightning Component', 'Aura Component', 'Lightning Web Component',
            'Lightning Page', 'Lightning Pages', 'Flow', 'Process Builder',
            'Custom Object', 'Custom Objects', 'Custom Field', 'Custom Object Definition',
            'Validation Rule', 'Workflow Rule',
            'Profile', 'Permission Set',
            'Static Resource', 'Custom Label', 'Custom Metadata'
        };

        List<SetupAuditTrail> trails = [
            SELECT Id, Action, Section, Display, CreatedBy.Name, CreatedDate
            FROM   SetupAuditTrail
            WHERE  CreatedDate >= :windowStart
            AND    CreatedDate <= :errorTime
            ORDER BY CreatedDate DESC
            LIMIT  100
        ];

        // Deduplicate: keep only the MOST RECENT entry per component name.
        Map<String, DevChangeRecord> seen = new Map<String, DevChangeRecord>();
        Map<String, Integer> scores = new Map<String, Integer>();

        for (SetupAuditTrail t : trails) {
            Boolean relevant = false;
            for (String s : devSections) {
                if (t.Section != null && t.Section.containsIgnoreCase(s)) { relevant = true; break; }
            }
            if (!relevant) continue;

            String componentName = extractName(t.Display);
            String sectionLower  = t.Section != null ? t.Section.toLowerCase() : '';
            String compLower     = componentName.toLowerCase();

            // Skip test classes
            if (sectionLower.contains('apex class') && componentName.endsWithIgnoreCase('Test')) continue;

            // Skip Workspace360 app internals
            if (componentName.startsWithIgnoreCase('W360')
                || componentName.startsWithIgnoreCase('Workspace360')
                || componentName.startsWithIgnoreCase('workspace360')
                || componentName.equalsIgnoreCase('AgentforceSummary')
                || componentName.equalsIgnoreCase('WorkspaceLogger')
                || componentName.equalsIgnoreCase('W360LiveDemoSeeder')
                || componentName.equalsIgnoreCase('Workspace360IncidentSeeder')
                || componentName.equalsIgnoreCase('Workspace360DemoSeeder')
                || componentName.equalsIgnoreCase('Workspace360BackgroundTrackerController')) continue;

            // ── Relevance gate: skip declarative-only changes for governor limit errors ──
            // Validation Rules, Workflow Rules, and Custom Fields cannot cause SOQL/CPU
            // governor limit exceptions or callout timeouts — skip them to avoid noise.
            if (isGovernorLimitError) {
                if (sectionLower.contains('validation rule')
                    || sectionLower.contains('workflow rule')
                    || sectionLower.contains('custom field')) continue;
            }

            String dedupeKey = componentName + '||' + (t.Section != null ? t.Section : '');
            if (seen.containsKey(dedupeKey)) continue;

            Long minutesDiff = (errorTime.getTime() - t.CreatedDate.getTime()) / 60000;

            DevChangeRecord c = new DevChangeRecord();
            c.action        = t.Action;
            c.section       = t.Section;
            c.component     = componentName;
            c.detail        = t.Display;
            c.changedAt     = t.CreatedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
            c.minutesBefore = minutesDiff + ' min before error';
            seen.put(dedupeKey, c);

            // ── Relevance score ──────────────────────────────────────────────
            Integer score = 0;
            // +3: component name shares a token with the failing class
            for (String tok : classTokens) {
                if (compLower.contains(tok)) { score += 3; break; }
            }
            // +2: same Salesforce object referenced (e.g. "Opportunity" in both)
            for (String tok : classTokens) {
                if (tok.length() > 5 && compLower.contains(tok)) { score += 2; break; }
            }
            // +1: same broad metadata type (Apex error → Apex change)
            if (String.isNotBlank(failingClassName)) {
                Boolean isApexClass = !failingClassName.contains('Flow') && !failingClassName.contains('Trigger');
                if (isApexClass && (sectionLower.contains('apex class') || sectionLower.contains('apex trigger'))) score += 1;
                if (failingClassName.containsIgnoreCase('Flow') && sectionLower.contains('flow')) score += 1;
            }
            scores.put(dedupeKey, score);
        }

        // Sort by score descending, then by minutesBefore ascending (closer = more suspicious)
        List<DevChangeRecord> result = seen.values();
        result.sort(new ChangeRelevanceComparator(scores, seen));

        // Return at most 5 changes — beyond that the signal-to-noise ratio drops sharply
        if (result.size() <= 5) return result;
        List<DevChangeRecord> trimmed = new List<DevChangeRecord>();
        for (Integer i = 0; i < 5; i++) trimmed.add(result[i]);
        return trimmed;
    }

    // Comparator: highest relevance score first; tie-break by minutesBefore (numeric ascending)
    private class ChangeRelevanceComparator implements Comparator<DevChangeRecord> {
        private Map<String, Integer> scores;
        private Map<String, DevChangeRecord> seen;
        public ChangeRelevanceComparator(Map<String, Integer> s, Map<String, DevChangeRecord> m) {
            scores = s; seen = m;
        }
        public Integer compare(DevChangeRecord a, DevChangeRecord b) {
            String keyA = a.component + '||' + (a.section != null ? a.section : '');
            String keyB = b.component + '||' + (b.section != null ? b.section : '');
            Integer scoreA = scores.containsKey(keyA) ? scores.get(keyA) : 0;
            Integer scoreB = scores.containsKey(keyB) ? scores.get(keyB) : 0;
            if (scoreB != scoreA) return scoreB - scoreA; // higher score first
            // tie-break: parse minutesBefore numeric value
            Integer minA = parseMins(a.minutesBefore);
            Integer minB = parseMins(b.minutesBefore);
            return minA - minB; // closer to error first
        }
        private Integer parseMins(String s) {
            if (String.isBlank(s)) return 9999;
            try { return Integer.valueOf(s.split(' ')[0]); } catch (Exception e) { return 9999; }
        }
    }

    // ── 3. AI Analysis via Einstein / Agentforce ──────────────────────────────

    /**
     * Takes an incident + correlated changes and asks Agentforce to:
     *   - Identify which change most likely caused the error
     *   - Explain the mechanism (e.g. "trigger X now fires on update, causing SOQL limit")
     *   - Suggest a remediation step
     *
     * Falls back gracefully if AI is unavailable.
     */
    @AuraEnabled(cacheable=false)
    public static String analyzeIncident(
        String errorMessage,
        String exceptionType,
        String stackTrace,
        String devChangesJson
    ) {
        try {
            String prompt = buildAnalysisPrompt(errorMessage, exceptionType, stackTrace, devChangesJson);

            // Use the same Named Credential + Einstein GenAI endpoint as AgentforceSummary.
            // If the callout fails for any reason (no credential, timeout, no license),
            // we catch and fall through to the heuristic engine below.
            Map<String, Object> payload = new Map<String, Object>{
                'prompt'         => prompt,
                'numGenerations' => 1,
                'parameters'     => new Map<String, Object>{
                    'temperature' => 0.3,
                    'maxTokens'   => 400
                }
            };
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:Agentforce_API/v1/generations');
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('x-sfdc-app-context', 'EinsteinGPT');
            req.setBody(JSON.serialize(payload));
            req.setTimeout(12000);

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> generations = (List<Object>) resp.get('generations');
                if (generations != null && !generations.isEmpty()) {
                    Map<String, Object> gen = (Map<String, Object>) generations[0];
                    String text = (String) gen.get('text');
                    if (String.isNotBlank(text)) return text;
                }
            }
        } catch (Exception e) {
            System.debug('W360IncidentAnalyzer.analyzeIncident AI call: ' + e.getMessage());
        }

        // Graceful fallback — deterministic heuristic analysis (always works, no callout needed)
        return buildFallbackAnalysis(errorMessage, exceptionType, devChangesJson);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static String buildAnalysisPrompt(
        String errorMessage, String exType, String stack, String changesJson
    ) {
        Boolean isGovernorLimit = String.isNotBlank(exType)
            && (exType.containsIgnoreCase('LimitException')
                || exType.containsIgnoreCase('UNABLE_TO_LOCK_ROW')
                || exType.containsIgnoreCase('CalloutException'));

        String extraInstruction = isGovernorLimit
            ? 'IMPORTANT: This is a governor limit / runtime error. '
                + 'Validation Rules, Workflow Rules, and Custom Field changes CANNOT cause this type of error — '
                + 'do not cite them as root cause. Focus only on Apex, Flow, Trigger, or architectural changes.\n'
            : '';

        return 'You are a Salesforce expert analyzing a production incident.\n\n'
            + '## Error\n'
            + 'Type: ' + (String.isBlank(exType) ? 'Unknown' : exType) + '\n'
            + 'Message: ' + (String.isBlank(errorMessage) ? '(none)' : errorMessage) + '\n'
            + (String.isBlank(stack) ? '' : 'Stack Trace (partial):\n' + stack.left(500) + '\n')
            + '\n## Recent Dev Changes (made BEFORE this error, pre-filtered for relevance)\n'
            + (String.isBlank(changesJson) ? 'No related changes recorded.' : changesJson)
            + '\n\n## Your Task\n'
            + extraInstruction
            + 'In 3–5 bullet points:\n'
            + '1. Which change most likely caused this error and why (only cite changes that can mechanically cause this error type)\n'
            + '2. The mechanism (e.g. governor limit, null reference, field rename, lock contention)\n'
            + '3. A concrete remediation step (e.g. "Roll back X" or "Add null check in Y")\n'
            + 'If no listed change could plausibly cause this error, say so clearly and focus on the code pattern instead.\n'
            + 'Be concise and technical. No preamble.';
    }

    private static String buildFallbackAnalysis(String errorMessage, String exType, String changesJson) {
        String em = errorMessage != null ? errorMessage.toLowerCase() : '';
        String sb = '';

        if (em.contains('list has no rows') || em.contains('sobject')) {
            sb += '• Likely cause: A SOQL query is returning 0 rows and the result is assigned to a single SObject variable without null-checking.\n';
            sb += '• Look for recent Apex changes that modified WHERE clauses or removed record filters.\n';
            sb += '• Fix: Add a list-based query with an isEmpty() guard, or wrap in try/catch.\n';
        } else if (em.contains('too many soql') || em.contains('governor')) {
            sb += '• Likely cause: A recent Apex or Flow change introduced a SOQL query inside a loop.\n';
            sb += '• Check if any Apex class changed in the 2 hours before this error placed a SELECT inside a for-loop.\n';
            sb += '• Fix: Bulk-query outside the loop and use a Map for lookup.\n';
        } else if (em.contains('null') || em.contains('npe')) {
            sb += '• Likely cause: A null pointer — a field, relationship, or variable is being accessed without a null check.\n';
            sb += '• Check recently changed Apex for missing != null guards on relationship fields.\n';
            sb += '• Fix: Add defensive null checks before dereferencing.\n';
        } else if (em.contains('validation') || em.contains('required field')) {
            sb += '• Likely cause: A recently added Validation Rule or required Custom Field is blocking DML.\n';
            sb += '• Check the Field and Validation Rule changes in the correlated changes list.\n';
            sb += '• Fix: Review the new rule logic and ensure automation populates the required field.\n';
        } else {
            sb += '• Review the correlated dev changes above — focus on changes made closest to the error timestamp.\n';
            sb += '• Check if any Apex class, Flow, or Trigger was modified and re-deployed in the window.\n';
            sb += '• Consider rolling back the most recent change and monitoring if the error stops.\n';
        }

        sb += '\n_AI analysis ran in fallback mode — Einstein Trust Layer unavailable in this org tier._';
        return sb;
    }

    private static String extractName(String display) {
        if (String.isBlank(display)) return '(unknown)';
        String d = display.trim();
        List<String> verbs = new List<String>{
            'Changed ','Created ','Deleted ','Deployed ','Installed ','Activated ','Deactivated ','Saved '
        };
        for (String v : verbs) {
            if (d.startsWithIgnoreCase(v)) { d = d.substring(v.length()).trim(); break; }
        }
        List<String> suffixes = new List<String>{
            ' Apex Class code',' Apex Class',' Apex Trigger',
            ' Lightning Web Component',' Lightning Component',' Aura Component',
            ' Lightning Page',' Flow Definition',' Flow',
            ' Custom Object Definition',' Custom Object',' Custom Field',
            ' Validation Rule',' Workflow Rule',' Permission Set',' Profile',
            ' Static Resource',' Custom Label',' Custom Metadata',' code'
        };
        for (String s : suffixes) {
            if (d.endsWithIgnoreCase(s)) { d = d.substring(0, d.length() - s.length()).trim(); break; }
        }
        return String.isBlank(d) ? display : d;
    }

    // ── Comparator: sort by occurredAt descending ─────────────────────────────
    private class IncidentComparator implements Comparator<IncidentRecord> {
        public Integer compare(IncidentRecord a, IncidentRecord b) {
            String ta = a.occurredAt != null ? a.occurredAt : '';
            String tb = b.occurredAt != null ? b.occurredAt : '';
            return tb.compareTo(ta); // descending
        }
    }
}