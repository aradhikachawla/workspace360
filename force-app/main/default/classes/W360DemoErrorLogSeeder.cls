/**
 * W360DemoErrorLogSeeder
 * ─────────────────────────────────────────────────────────────────────────────
 * Inserts realistic error records into Demo_Error_Log__c to simulate what a
 * real org's error log table would contain.
 *
 * This proves the adapter works end-to-end:
 *   Demo_Error_Log__c  →  W360ErrorLogAdapter  →  W360_Incident_Log__c
 *                                                         ↓
 *                                              Agentforce agent / Dashboard
 *
 * USAGE — Run in Developer Console → Execute Anonymous:
 *
 *   // Step 1: Seed errors into Demo_Error_Log__c
 *   W360DemoErrorLogSeeder.seedAll();
 *
 *   // Step 2: Run the adapter to sync them into W360_Incident_Log__c
 *   W360ErrorLogAdapter.SyncResult result = W360ErrorLogAdapter.syncAll();
 *   System.debug(result.summary());
 *
 *   // Step 3: Open Workspace360 Dashboard → Incidents tab
 *   //         You should see the errors from Demo_Error_Log__c now appearing
 *
 * CLEAN UP:
 *   W360DemoErrorLogSeeder.cleanUp();
 */
public class W360DemoErrorLogSeeder {

    public static void seedAll() {
        cleanUp();

        List<Demo_Error_Log__c> errors = new List<Demo_Error_Log__c>();
        errors.addAll(triggerErrors());
        errors.addAll(batchErrors());
        errors.addAll(integrationErrors());
        insert errors;

        System.debug('✅ W360DemoErrorLogSeeder: inserted ' + errors.size()
            + ' records into Demo_Error_Log__c.');
        System.debug('');
        System.debug('Next step → run the adapter to sync them into W360_Incident_Log__c:');
        System.debug('  W360ErrorLogAdapter.SyncResult r = W360ErrorLogAdapter.syncAll();');
        System.debug('  System.debug(r.summary());');
    }

    // ── Trigger errors (most common in real orgs) ─────────────────────────────

    private static List<Demo_Error_Log__c> triggerErrors() {
        return new List<Demo_Error_Log__c>{
            new Demo_Error_Log__c(
                Message__c       = 'System.LimitException: Too many SOQL queries: 101',
                Class_Name__c    = 'OpportunityTriggerHandler',
                Exception_Type__c = 'System.LimitException',
                Stack_Trace__c   = 'Class.OpportunityTriggerHandler.updateAccountRating: line 47, column 1\n'
                                 + 'Class.OpportunityTriggerHandler.handleAfterUpdate: line 18, column 1\n'
                                 + 'Trigger.OpportunityTrigger: line 6, column 1',
                Log_Level__c     = 'ERROR',
                Occurred_At__c   = Datetime.now().addHours(-1)
            ),
            new Demo_Error_Log__c(
                Message__c       = 'System.NullPointerException: Attempt to de-reference a null object. '
                                 + 'Contact.AccountId is null for recently imported records.',
                Class_Name__c    = 'ContactSyncHandler',
                Exception_Type__c = 'System.NullPointerException',
                Stack_Trace__c   = 'Class.ContactSyncHandler.syncOwner: line 34, column 1\n'
                                 + 'Trigger.ContactTrigger: line 8, column 1',
                Log_Level__c     = 'ERROR',
                Occurred_At__c   = Datetime.now().addHours(-3)
            )
        };
    }

    // ── Batch job errors ──────────────────────────────────────────────────────

    private static List<Demo_Error_Log__c> batchErrors() {
        return new List<Demo_Error_Log__c>{
            new Demo_Error_Log__c(
                Message__c       = 'UNABLE_TO_LOCK_ROW: Record currently unavailable. '
                                 + 'LeadScoreBatch failed on chunk 3 of 8 (records 401-600). '
                                 + 'Row lock contention with LeadOwnerAssignment trigger.',
                Class_Name__c    = 'LeadScoreBatch',
                Exception_Type__c = 'UNABLE_TO_LOCK_ROW',
                Stack_Trace__c   = 'Class.LeadScoreBatch.execute: line 22, column 1\n'
                                 + 'Chunk: 3 / 8 — Records: 401-600',
                Log_Level__c     = 'CRITICAL',
                Occurred_At__c   = Datetime.now().addHours(-5)
            ),
            new Demo_Error_Log__c(
                Message__c       = 'System.DmlException: Insert failed. First exception on row 0; '
                                 + 'first error: REQUIRED_FIELD_MISSING, Required fields are missing: [CloseDate].',
                Class_Name__c    = 'OpportunityCloseNotifier',
                Exception_Type__c = 'System.DmlException',
                Stack_Trace__c   = 'Class.OpportunityCloseNotifier.sendNotification: line 61, column 1\n'
                                 + 'Class.OpportunityCloseNotifier.handleClosedOpportunity: line 29, column 1\n'
                                 + 'Trigger.OpportunityNotifyTrigger: line 4, column 1',
                Log_Level__c     = 'ERROR',
                Occurred_At__c   = Datetime.now().addHours(-8)
            )
        };
    }

    // ── Integration errors ────────────────────────────────────────────────────

    private static List<Demo_Error_Log__c> integrationErrors() {
        return new List<Demo_Error_Log__c>{
            new Demo_Error_Log__c(
                Message__c       = 'CalloutException: Read timed out after 10000ms. '
                                 + 'External ERP system did not respond. '
                                 + 'Endpoint: https://erp.internal.company.com/api/sync',
                Class_Name__c    = 'ERPSyncService',
                Exception_Type__c = 'System.CalloutException',
                Stack_Trace__c   = 'Class.ERPSyncService.syncAccounts: line 89, column 1\n'
                                 + 'Class.ERPSyncService.execute: line 45, column 1',
                Log_Level__c     = 'WARN',
                Occurred_At__c   = Datetime.now().addHours(-2)
            )
        };
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────

    public static void cleanUp() {
        List<Demo_Error_Log__c> existing = [SELECT Id FROM Demo_Error_Log__c LIMIT 200];
        if (!existing.isEmpty()) {
            delete existing;
            System.debug('✅ W360DemoErrorLogSeeder.cleanUp: deleted ' + existing.size() + ' records.');
        }
    }
}
