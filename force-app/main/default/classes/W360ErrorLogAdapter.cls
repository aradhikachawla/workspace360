/**
 * W360ErrorLogAdapter
 * ─────────────────────────────────────────────────────────────────────────────
 * Reads from ANY existing error log object in this org and syncs records into
 * W360_Incident_Log__c so the Workspace360 incident dashboard and Agentforce
 * agent can surface them with correlated dev changes.
 *
 * Zero code changes required in the customer's existing triggers or flows.
 * Configuration is done entirely through W360_Error_Source__mdt Custom Metadata.
 *
 * ── How it works ─────────────────────────────────────────────────────────────
 *  1. Read all active W360_Error_Source__mdt records (one per error log table)
 *  2. For each source: dynamically query their error log object for recent records
 *  3. Map their fields → W360_Incident_Log__c fields using the configured mapping
 *  4. Upsert into W360_Incident_Log__c (dedup by source record Id)
 *
 * ── Setup instructions for sysadmin ─────────────────────────────────────────
 *  1. Deploy this class + the W360_Error_Source__mdt metadata type
 *  2. Go to Setup → Custom Metadata Types → W360 Error Source → Manage Records
 *  3. Click New and fill in:
 *       Label:                    My Org Error Log          (any name)
 *       Source Object API Name:   Error_Log__c              (their object)
 *       Error Message Field:      Message__c                (their field)
 *       Class Name Field:         Class_Name__c             (their field, optional)
 *       Timestamp Field:          Occurred_At__c            (their field, optional — defaults to CreatedDate)
 *       Severity Field:           Severity__c               (their field, optional)
 *       Stack Trace Field:        Stack_Trace__c            (their field, optional)
 *       Exception Type Field:     Exception_Type__c         (their field, optional)
 *       Lookback Hours:           24
 *       Min Severity:             Warning
 *       Is Active:                ✅
 *  4. Schedule W360ErrorLogAdapterScheduler to run hourly
 *
 * ── Supported severity value mappings ───────────────────────────────────────
 *  Their value → W360 value
 *  ERROR / FATAL / Critical / P1 / HIGH  → Critical
 *  WARN  / Warning / P2 / MEDIUM         → Warning
 *  INFO  / Info / DEBUG / LOW            → Info
 *
 * @author  Workspace 360
 * @version 1.0
 */
public with sharing class W360ErrorLogAdapter {

    // ── External Id field on W360_Incident_Log__c for upsert dedup ───────────
    // Stores the source record's Id so we never create duplicate W360 incidents
    // for the same source error record across multiple sync runs.
    // Field must exist: Source_Record_Id__c (Text 18, External ID, Unique)
    private static final String EXTERNAL_ID_FIELD = 'Source_Record_Id__c';

    // ── Result DTO returned to callers / scheduler ────────────────────────────
    public class SyncResult {
        public Integer sourcesProcessed = 0;
        public Integer recordsSynced    = 0;
        public Integer recordsSkipped   = 0;
        public Integer errors           = 0;
        public List<String> messages    = new List<String>();

        public String summary() {
            return 'W360ErrorLogAdapter: '
                + sourcesProcessed + ' source(s) processed, '
                + recordsSynced    + ' record(s) synced, '
                + recordsSkipped   + ' skipped, '
                + errors           + ' error(s).';
        }
    }

    // ── Main entry point ──────────────────────────────────────────────────────

    /**
     * syncAll — reads all active W360_Error_Source__mdt configs and syncs each one.
     * Called by the scheduler every hour.
     */
    public static SyncResult syncAll() {
        SyncResult result = new SyncResult();

        List<W360_Error_Source__mdt> sources = [
            SELECT  DeveloperName, MasterLabel,
                    Source_Object_API_Name__c,
                    Error_Message_Field__c,
                    Class_Name_Field__c,
                    Timestamp_Field__c,
                    Severity_Field__c,
                    Stack_Trace_Field__c,
                    Exception_Type_Field__c,
                    Is_Active__c,
                    Lookback_Hours__c,
                    Min_Severity__c
            FROM    W360_Error_Source__mdt
            WHERE   Is_Active__c = true
        ];

        if (sources.isEmpty()) {
            result.messages.add('No active W360_Error_Source__mdt records found. '
                + 'Go to Setup → Custom Metadata Types → W360 Error Source → Manage Records to configure.');
            return result;
        }

        for (W360_Error_Source__mdt src : sources) {
            try {
                SyncResult partial = syncSource(src);
                result.sourcesProcessed++;
                result.recordsSynced  += partial.recordsSynced;
                result.recordsSkipped += partial.recordsSkipped;
                result.errors         += partial.errors;
                result.messages.addAll(partial.messages);
            } catch (Exception e) {
                result.errors++;
                result.messages.add('ERROR syncing source "' + src.MasterLabel + '": ' + e.getMessage());
                System.debug(LoggingLevel.ERROR, 'W360ErrorLogAdapter.syncAll: ' + e.getMessage());
            }
        }

        System.debug(LoggingLevel.INFO, result.summary());
        return result;
    }

    // ── Sync a single source ──────────────────────────────────────────────────

    private static SyncResult syncSource(W360_Error_Source__mdt src) {
        SyncResult result = new SyncResult();

        // Validate required config
        if (String.isBlank(src.Source_Object_API_Name__c)) {
            result.messages.add('SKIP "' + src.MasterLabel + '": Source Object API Name is blank.');
            result.recordsSkipped++;
            return result;
        }
        if (String.isBlank(src.Error_Message_Field__c)) {
            result.messages.add('SKIP "' + src.MasterLabel + '": Error Message Field is blank.');
            result.recordsSkipped++;
            return result;
        }

        // Resolve field names — use defaults where not configured
        String timestampField  = String.isNotBlank(src.Timestamp_Field__c)
            ? src.Timestamp_Field__c : 'CreatedDate';
        Integer lookbackHours  = (src.Lookback_Hours__c != null && src.Lookback_Hours__c > 0)
            ? Integer.valueOf(src.Lookback_Hours__c) : 24;
        String minSeverity     = String.isNotBlank(src.Min_Severity__c)
            ? src.Min_Severity__c : 'Warning';

        // Build dynamic SOQL — only SELECT fields that are configured
        Set<String> fieldsToQuery = new Set<String>{ 'Id', timestampField, src.Error_Message_Field__c };
        if (String.isNotBlank(src.Class_Name_Field__c))      fieldsToQuery.add(src.Class_Name_Field__c);
        if (String.isNotBlank(src.Severity_Field__c))        fieldsToQuery.add(src.Severity_Field__c);
        if (String.isNotBlank(src.Stack_Trace_Field__c))     fieldsToQuery.add(src.Stack_Trace_Field__c);
        if (String.isNotBlank(src.Exception_Type_Field__c))  fieldsToQuery.add(src.Exception_Type_Field__c);

        Datetime cutoff = Datetime.now().addHours(-lookbackHours);

        String soql = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ')
            + ' FROM '   + src.Source_Object_API_Name__c
            + ' WHERE '  + timestampField + ' >= :cutoff'
            + ' ORDER BY ' + timestampField + ' DESC'
            + ' LIMIT 200';

        List<SObject> sourceRecords;
        try {
            sourceRecords = Database.query(soql);
        } catch (Exception e) {
            result.errors++;
            result.messages.add('QUERY ERROR for "' + src.MasterLabel + '": ' + e.getMessage()
                + '. Check that Source Object API Name and field names are correct.');
            return result;
        }

        if (sourceRecords.isEmpty()) {
            result.messages.add('OK "' + src.MasterLabel + '": no new records in last '
                + lookbackHours + ' hours.');
            return result;
        }

        // Map source records → W360_Incident_Log__c
        List<W360_Incident_Log__c> toUpsert = new List<W360_Incident_Log__c>();

        for (SObject rec : sourceRecords) {
            // Extract and map severity
            String rawSeverity  = String.isNotBlank(src.Severity_Field__c)
                ? String.valueOf(rec.get(src.Severity_Field__c)) : null;
            String w360Severity = mapSeverity(rawSeverity);

            // Apply minimum severity filter
            if (!meetsSeverityThreshold(w360Severity, minSeverity)) {
                result.recordsSkipped++;
                continue;
            }

            // Extract timestamp
            Object tsObj = rec.get(timestampField);
            Datetime occurredAt = (tsObj instanceof Datetime) ? (Datetime) tsObj : Datetime.now();

            // Extract error message — required field
            Object msgObj = rec.get(src.Error_Message_Field__c);
            String errorMsg = msgObj != null ? String.valueOf(msgObj) : '(no message)';

            // Extract optional fields
            String className = String.isNotBlank(src.Class_Name_Field__c)
                ? safeString(rec.get(src.Class_Name_Field__c)) : null;
            String stackTrace = String.isNotBlank(src.Stack_Trace_Field__c)
                ? safeString(rec.get(src.Stack_Trace_Field__c)) : null;
            String exType     = String.isNotBlank(src.Exception_Type_Field__c)
                ? safeString(rec.get(src.Exception_Type_Field__c)) : inferExceptionType(errorMsg);

            // If no class name field configured, try to extract from error message
            if (String.isBlank(className)) {
                className = inferClassName(errorMsg, stackTrace);
            }

            W360_Incident_Log__c incident = new W360_Incident_Log__c(
                Source_Record_Id__c = String.valueOf(rec.get('Id')),  // external Id for upsert dedup
                Error_Message__c    = errorMsg.left(32768),
                Apex_Class__c       = className != null ? className.left(255) : null,
                Exception_Type__c   = exType != null ? exType.left(255) : null,
                Stack_Trace__c      = stackTrace != null ? stackTrace.left(32768) : null,
                Occurred_At__c      = occurredAt,
                Severity__c         = w360Severity,
                Triggered_By__c     = ('Synced from ' + src.MasterLabel).left(255),
                Hit_Count__c        = 1
            );
            toUpsert.add(incident);
        }

        if (!toUpsert.isEmpty()) {
            try {
                Schema.SObjectField extIdField =
                    W360_Incident_Log__c.SObjectType.getDescribe()
                        .fields.getMap().get(EXTERNAL_ID_FIELD);

                if (extIdField != null) {
                    Database.upsert(toUpsert, extIdField, false);
                } else {
                    // External Id field not yet deployed — fall back to insert with dedup check
                    insert toUpsert;
                }
                result.recordsSynced += toUpsert.size();
                result.messages.add('OK "' + src.MasterLabel + '": synced '
                    + toUpsert.size() + ' record(s).');
            } catch (Exception e) {
                result.errors++;
                result.messages.add('UPSERT ERROR for "' + src.MasterLabel + '": ' + e.getMessage());
            }
        }

        return result;
    }

    // ── Severity mapping ──────────────────────────────────────────────────────

    /**
     * Maps any org's severity vocabulary to W360's Critical / Warning / Info.
     * Handles: ERROR, FATAL, P1, HIGH → Critical
     *          WARN, P2, MEDIUM       → Warning
     *          INFO, DEBUG, LOW       → Info
     */
    private static String mapSeverity(String raw) {
        if (String.isBlank(raw)) return 'Warning';
        String s = raw.toUpperCase().trim();
        if (s == 'CRITICAL' || s == 'ERROR' || s == 'FATAL'
            || s == 'P1'    || s == 'HIGH'  || s == 'SEVERE') return 'Critical';
        if (s == 'WARNING'  || s == 'WARN'  || s == 'P2'
            || s == 'MEDIUM'|| s == 'MODERATE')                return 'Warning';
        return 'Info';
    }

    /**
     * Returns true if the record's severity meets or exceeds the configured minimum.
     * Critical > Warning > Info
     */
    private static Boolean meetsSeverityThreshold(String recordSeverity, String minSeverity) {
        Map<String, Integer> rank = new Map<String, Integer>{
            'Info' => 1, 'Warning' => 2, 'Critical' => 3
        };
        Integer recRank = rank.containsKey(recordSeverity) ? rank.get(recordSeverity) : 2;
        Integer minRank = rank.containsKey(minSeverity)    ? rank.get(minSeverity)    : 2;
        return recRank >= minRank;
    }

    // ── Inference helpers ─────────────────────────────────────────────────────

    /**
     * Try to extract a class name from the error message or stack trace.
     * Handles common Salesforce stack trace formats:
     *   "Class.MyClass.myMethod: line 42"
     *   "Trigger.MyTrigger: line 6"
     */
    private static String inferClassName(String errorMsg, String stackTrace) {
        String text = String.isNotBlank(stackTrace) ? stackTrace : errorMsg;
        if (String.isBlank(text)) return null;

        // Match "Class.SomeClassName." or "Trigger.SomeTrigger"
        Pattern p = Pattern.compile('(?:Class|Trigger)\\.([A-Za-z0-9_]+)');
        Matcher m = p.matcher(text);
        if (m.find()) return m.group(1);

        return null;
    }

    /**
     * Try to infer exception type from the error message text.
     * Handles "System.LimitException:", "FIELD_CUSTOM_VALIDATION_EXCEPTION:" etc.
     */
    private static String inferExceptionType(String errorMsg) {
        if (String.isBlank(errorMsg)) return null;
        Integer colonIdx = errorMsg.indexOf(':');
        if (colonIdx > 0 && colonIdx < 80) {
            return errorMsg.substring(0, colonIdx).trim();
        }
        return null;
    }

    private static String safeString(Object val) {
        return val != null ? String.valueOf(val) : null;
    }
}
