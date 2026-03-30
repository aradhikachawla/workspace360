/**
 * Workspace360IncidentSeeder
 * Seeds demo W360_Incident_Log__c records spread across time so the
 * 1D / 7D / 30D filters show meaningfully different data.
 *
 * Timeline:
 *   TODAY       — 2 incidents (SOQL loop + validation rule)    → shows in 1D, 7D, 30D
 *   5 DAYS AGO  — 2 incidents (null pointer + CPU limit)       → shows in 7D, 30D only
 *   15 DAYS AGO — 2 incidents (batch abort + DML exception)    → shows in 30D only
 *
 * Run: Workspace360IncidentSeeder.seedAll();
 */
public class Workspace360IncidentSeeder {

    public static void seedAll() {
        deleteExisting();
        List<W360_Incident_Log__c> records = new List<W360_Incident_Log__c>();
        records.addAll(todayIncidents());
        records.addAll(fiveDaysAgoIncidents());
        records.addAll(fifteenDaysAgoIncidents());
        insert records;
        System.debug('Inserted ' + records.size() + ' incident records.');
        System.debug('1D: 2 incidents | 7D: 4 incidents | 30D: 6 incidents');
    }

    private static void deleteExisting() {
        delete [SELECT Id FROM W360_Incident_Log__c LIMIT 200];
    }

    // TODAY — visible in 1D, 7D, 30D
    private static List<W360_Incident_Log__c> todayIncidents() {
        Datetime t1 = Datetime.now().addHours(-2);
        Datetime t2 = Datetime.now().addMinutes(-45);
        return new List<W360_Incident_Log__c>{
            new W360_Incident_Log__c(
                Apex_Class__c     = 'OpportunityTriggerHandler',
                Error_Message__c  = 'System.LimitException: Too many SOQL queries: 101',
                Exception_Type__c = 'System.LimitException',
                Stack_Trace__c    = 'Class.OpportunityTriggerHandler.updateAccountRating: line 47, column 1\nClass.OpportunityTriggerHandler.handleAfterUpdate: line 18, column 1\nTrigger.OpportunityTrigger: line 6, column 1',
                Triggered_By__c   = 'Bulk Opportunity Update — Data Loader (200 records)',
                Occurred_At__c    = t1,
                Severity__c       = 'Critical',
                Hit_Count__c      = 7
            ),
            new W360_Incident_Log__c(
                Apex_Class__c     = 'Lead_Conversion_Flow',
                Error_Message__c  = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: Annual Revenue is required for converted accounts. Error occurred while processing element Account_Create in Flow: Lead_Conversion_Flow.',
                Exception_Type__c = 'FIELD_CUSTOM_VALIDATION_EXCEPTION',
                Stack_Trace__c    = 'Flow: Lead_Conversion_Flow\n  Element: Account_Create (Create Records)\n  Object: Account\n  Field: AnnualRevenue\n  Validation Rule: Annual_Revenue_Required_On_Conversion',
                Triggered_By__c   = 'Convert Lead — Sales Rep UI Action',
                Occurred_At__c    = t2,
                Severity__c       = 'Critical',
                Hit_Count__c      = 12
            )
        };
    }

    // 5 DAYS AGO — visible in 7D and 30D only
    private static List<W360_Incident_Log__c> fiveDaysAgoIncidents() {
        Datetime t1 = Datetime.now().addDays(-5).addHours(-3);
        Datetime t2 = Datetime.now().addDays(-5).addHours(-1);
        return new List<W360_Incident_Log__c>{
            new W360_Incident_Log__c(
                Apex_Class__c     = 'AccountSyncBatch',
                Error_Message__c  = 'System.NullPointerException: Attempt to de-reference a null object. Contact.AccountId is null for recently imported leads in AccountSyncBatch.execute.',
                Exception_Type__c = 'System.NullPointerException',
                Stack_Trace__c    = 'Class.AccountSyncBatch.execute: line 34, column 1\nClass.AccountSyncBatch.syncContactOwner: line 89, column 1',
                Triggered_By__c   = 'Scheduled Job — nightly account sync (11 PM)',
                Occurred_At__c    = t1,
                Severity__c       = 'Critical',
                Hit_Count__c      = 3
            ),
            new W360_Incident_Log__c(
                Apex_Class__c     = 'CasePriorityFlow',
                Error_Message__c  = 'System.LimitException: Apex CPU time limit exceeded. Flow CasePriorityFlow element CalculatePriority exceeded 10000ms CPU limit.',
                Exception_Type__c = 'System.LimitException',
                Stack_Trace__c    = 'Flow: CasePriorityFlow\n  Element: CalculatePriority (Formula)\n  Triggered by: Case assignment rule update',
                Triggered_By__c   = 'Case Assignment Rule — Priority Escalation',
                Occurred_At__c    = t2,
                Severity__c       = 'Warning',
                Hit_Count__c      = 5
            )
        };
    }

    // 15 DAYS AGO — visible in 30D only
    private static List<W360_Incident_Log__c> fifteenDaysAgoIncidents() {
        Datetime t1 = Datetime.now().addDays(-15).addHours(-6);
        Datetime t2 = Datetime.now().addDays(-15).addHours(-2);
        return new List<W360_Incident_Log__c>{
            new W360_Incident_Log__c(
                Apex_Class__c     = 'LeadScoreBatch',
                Error_Message__c  = 'Job aborted: UNABLE_TO_LOCK_ROW — Record currently unavailable. LeadScoreBatch failed on chunk 3 of 8 (records 401-600). Row lock contention with LeadOwnerAssignment trigger.',
                Exception_Type__c = 'UNABLE_TO_LOCK_ROW',
                Stack_Trace__c    = 'Class.LeadScoreBatch.execute: line 22, column 1\n  Chunk: 3 / 8\n  Records affected: 401-600',
                Triggered_By__c   = 'Scheduled Batch — LeadScoreBatch (nightly 2 AM)',
                Occurred_At__c    = t1,
                Severity__c       = 'Critical',
                Hit_Count__c      = 1
            ),
            new W360_Incident_Log__c(
                Apex_Class__c     = 'OpportunityCloseNotifier',
                Error_Message__c  = 'System.DmlException: Insert failed. First exception on row 0; first error: REQUIRED_FIELD_MISSING, Required fields are missing: [CloseDate].',
                Exception_Type__c = 'System.DmlException',
                Stack_Trace__c    = 'Class.OpportunityCloseNotifier.sendNotification: line 61, column 1\nClass.OpportunityCloseNotifier.handleClosedOpportunity: line 29, column 1\nTrigger.OpportunityNotifyTrigger: line 4, column 1',
                Triggered_By__c   = 'Opportunity stage changed to Closed Won — UI',
                Occurred_At__c    = t2,
                Severity__c       = 'Warning',
                Hit_Count__c      = 2
            )
        };
    }
}