/**
 * W360LiveDemoSeeder
 * ─────────────────────────────────────────────────────────────────────────────
 * Seeds W360_Incident_Log__c records timed around REAL SetupAuditTrail entries.
 *
 * SCENARIO 1 — Too Many SOQL Queries
 *   Anchor: the most recent Apex / LWC change YOU deployed (already in your org)
 *   Incident fires 15 min after that change
 *
 * SCENARIO 2 — Validation Rule Blocks Flow
 *   Anchor: the "Annual_Revenue_Required_On_Conversion" validation rule deploy
 *   Incident fires 8 min after that rule was created
 *   → correlation panel shows the EXACT rule that caused the Flow error
 *
 * PRE-REQUISITE for Scenario 2:
 *   Deploy the validation rule first:
 *     sf project deploy start --source-dir force-app/main/default/objects/Account
 *
 * USAGE:
 *   Run scripts/apex/seed_live_demo.apex in Developer Console → Execute Anonymous
 *
 * CLEAN UP:
 *   W360LiveDemoSeeder.cleanUp();
 */
public class W360LiveDemoSeeder {

    private static final Set<String> DEV_SECTIONS = new Set<String>{
        'Apex Class', 'Apex Classes', 'Apex Trigger', 'Apex Triggers',
        'Lightning Component', 'Aura Component', 'Lightning Web Component',
        'Lightning Page', 'Lightning Pages', 'Flow', 'Process Builder',
        'Custom Object', 'Custom Objects', 'Custom Field', 'Custom Object Definition',
        'Validation Rule', 'Workflow Rule',
        'Profile', 'Permission Set',
        'Static Resource', 'Custom Label', 'Custom Metadata'
    };

    // ── Main entry point ──────────────────────────────────────────────────────

    public static void seedAll() {
        deleteExisting();

        // ── Scenario 1 anchor: any recent Apex / LWC change ──────────────────
        Datetime apexAnchor = findRecentApexOrLwcChange();
        if (apexAnchor != null) {
            System.debug('W360LiveDemoSeeder ✅ Scenario 1 anchor found (Apex/LWC change at ' + apexAnchor.format('h:mm a') + ')');
        } else {
            apexAnchor = Datetime.now().addMinutes(-45);
            System.debug('W360LiveDemoSeeder ⚠️  No recent Apex/LWC audit entry found — using offset fallback for Scenario 1');
        }

        // ── Scenario 2 anchor: the specific validation rule deploy ────────────
        Datetime validationAnchor = findValidationRuleDeployTime();
        if (validationAnchor != null) {
            System.debug('W360LiveDemoSeeder ✅ Scenario 2 anchor found (Annual_Revenue_Required_On_Conversion deployed at ' + validationAnchor.format('h:mm a') + ')');
        } else {
            validationAnchor = Datetime.now().addMinutes(-20);
            System.debug('W360LiveDemoSeeder ⚠️  Validation rule not found in audit trail.');
            System.debug('    → Deploy it first: sf project deploy start --source-dir force-app/main/default/objects/Account');
            System.debug('    → Then re-run this script for full Scenario 2 correlation.');
        }

        // Safety cap: incidents must appear within the 72-hour display window.
        // If an anchor is older than 71 hours, reset to a recent fallback.
        // IMPORTANT: fallback timestamps are set FAR ENOUGH IN THE PAST so that
        // getCorrelatedChanges() can find real audit trail entries before them.
        // We use now()-2h so the 120-min lookback window covers the last 4 hours of audit activity.
        Datetime maxAge = Datetime.now().addHours(-71);
        if (apexAnchor < maxAge) {
            apexAnchor = Datetime.now().addHours(-2);
            System.debug('W360LiveDemoSeeder: Scenario 1 anchor was too old — reset to 2 hours ago.');
        }
        if (validationAnchor < maxAge) {
            validationAnchor = Datetime.now().addHours(-2).addMinutes(-15);
            System.debug('W360LiveDemoSeeder: Scenario 2 anchor was too old — reset to 2h 15m ago.');
            System.debug('    Re-deploy the validation rule to get real correlation for Scenario 2.');
        }

        List<W360_Incident_Log__c> records = new List<W360_Incident_Log__c>();
        records.addAll(scenarioSoqlInsideLoop(apexAnchor));
        records.addAll(scenarioValidationRuleBlocksFlow(validationAnchor));
        insert records;

        System.debug('');
        System.debug('✅ W360LiveDemoSeeder: inserted ' + records.size() + ' incident records.');
        System.debug('');
        System.debug('SCENARIO 1 — Too Many SOQL Queries:');
        System.debug('  Incident fires at: ' + apexAnchor.addMinutes(15).format('h:mm a') + ' (15 min after most recent Apex/LWC change)');
        System.debug('');
        System.debug('SCENARIO 2 — Validation Rule Blocks Flow:');
        System.debug('  Incident fires at: ' + validationAnchor.addMinutes(8).format('h:mm a') + ' (8 min after Annual_Revenue_Required_On_Conversion was deployed)');
        System.debug('');
        System.debug('→ Open Workspace 360 → Incidents tab → click any incident → see the correlated changes!');
    }

    // ── Find most recent Apex Class or LWC change by current user ────────────
    // NOTE: SetupAuditTrail does NOT support filtering by CreatedBy.Name in SOQL.
    //       Use CreatedById instead, then filter Section in Apex.
    // IMPORTANT: Skip Workspace360 internals — only real customer changes
    //            should be used as anchors so demo correlation is meaningful.

    private static Boolean isW360Internal(String display) {
        if (String.isBlank(display)) return false;
        String d = display.toLowerCase();
        return d.contains('w360') || d.contains('workspace360')
            || d.contains('agentforcesummary') || d.contains('workspacelogger');
    }

    private static Datetime findRecentApexOrLwcChange() {
        Datetime cutoff = Datetime.now().addDays(-7);
        Id currentUserId = UserInfo.getUserId();
        try {
            List<SetupAuditTrail> trails = [
                SELECT CreatedDate, Display, Section
                FROM   SetupAuditTrail
                WHERE  CreatedDate  >= :cutoff
                AND    CreatedById  =  :currentUserId
                ORDER BY CreatedDate DESC
                LIMIT  2000
            ];
            // First pass: prefer Apex Class or LWC — skip W360 app internals
            for (SetupAuditTrail t : trails) {
                if (t.Section == null || isW360Internal(t.Display)) continue;
                if (t.Section.containsIgnoreCase('Apex Class')
                    || t.Section.containsIgnoreCase('Lightning Web Component')
                    || t.Section.containsIgnoreCase('Aura Component')
                    || t.Section.containsIgnoreCase('Lightning Component')) {
                    System.debug('W360LiveDemoSeeder: Scenario 1 matched → "' + t.Display + '"');
                    return t.CreatedDate;
                }
            }
            // Second pass: any dev section change — skip W360 app internals
            for (SetupAuditTrail t : trails) {
                if (t.Section == null || isW360Internal(t.Display)) continue;
                for (String s : DEV_SECTIONS) {
                    if (t.Section.containsIgnoreCase(s)) {
                        System.debug('W360LiveDemoSeeder: Scenario 1 fallback matched → "' + t.Display + '"');
                        return t.CreatedDate;
                    }
                }
            }
        } catch (Exception e) {
            System.debug('W360LiveDemoSeeder.findRecentApexOrLwcChange error: ' + e.getMessage());
        }
        return null;
    }

    // ── Find when Annual_Revenue_Required_On_Conversion was deployed ──────────
    // NOTE: No user filter here — validation rules can be deployed by any admin.
    //       We search Display text across all users within the last 90 days.

    private static Datetime findValidationRuleDeployTime() {
        try {
            Datetime cutoff = Datetime.now().addDays(-90);
            List<SetupAuditTrail> trails = [
                SELECT CreatedDate, Display, Section
                FROM   SetupAuditTrail
                WHERE  CreatedDate >= :cutoff
                ORDER BY CreatedDate DESC
                LIMIT  2000
            ];
            for (SetupAuditTrail t : trails) {
                if (t.Display != null
                    && t.Display.containsIgnoreCase('Annual_Revenue_Required_On_Conversion')) {
                    System.debug('W360LiveDemoSeeder: Scenario 2 matched → "' + t.Display + '" at ' + t.CreatedDate.format('h:mm a'));
                    return t.CreatedDate;
                }
            }
        } catch (Exception e) {
            System.debug('W360LiveDemoSeeder.findValidationRuleDeployTime error: ' + e.getMessage());
        }
        return null;
    }

    // ── Helper: ensure a timestamp is never in the future ────────────────────
    // If anchor+offset would be in the future, cap it to 2 minutes ago so
    // getRecentErrors() always finds the incident and the lookback window is valid.
    private static Datetime clampPast(Datetime dt) {
        Datetime ceiling = Datetime.now().addMinutes(-2);
        return dt > ceiling ? ceiling : dt;
    }

    // ── Scenario 1: Too Many SOQL Queries ────────────────────────────────────
    // Incidents fire 15 and 37 min AFTER the most recent Apex/LWC deploy.
    // Clamped so they never appear in the future.

    private static List<W360_Incident_Log__c> scenarioSoqlInsideLoop(Datetime anchor) {
        return new List<W360_Incident_Log__c>{
            new W360_Incident_Log__c(
                Error_Message__c  = 'System.LimitException: Too many SOQL queries: 101',
                Exception_Type__c = 'System.LimitException',
                Stack_Trace__c    =
                    'Class.OpportunityTriggerHandler.updateAccountRating: line 47, column 1\n'
                  + 'Class.OpportunityTriggerHandler.handleAfterUpdate: line 18, column 1\n'
                  + 'Trigger.OpportunityTrigger: line 6, column 1',
                Apex_Class__c     = 'OpportunityTriggerHandler',
                Triggered_By__c   = 'Bulk Opportunity Update via Data Loader (200 records)',
                Occurred_At__c    = clampPast(anchor.addMinutes(15)),
                Severity__c       = 'Critical',
                Hit_Count__c      = 7
            ),
            new W360_Incident_Log__c(
                Error_Message__c  = 'System.LimitException: Too many SOQL queries: 101',
                Exception_Type__c = 'System.LimitException',
                Stack_Trace__c    =
                    'Class.OpportunityTriggerHandler.updateAccountRating: line 47, column 1\n'
                  + 'Trigger.OpportunityTrigger: line 6, column 1',
                Apex_Class__c     = 'OpportunityTriggerHandler',
                Triggered_By__c   = 'Quick Action — Update Stage (UI, single record)',
                Occurred_At__c    = clampPast(anchor.addMinutes(37)),
                Severity__c       = 'Critical',
                Hit_Count__c      = 3
            )
        };
    }

    // ── Scenario 2: Validation Rule blocks Flow ───────────────────────────────
    // Incidents fire 8 and 23 min AFTER the validation rule was deployed.
    // Clamped so they never appear in the future.

    private static List<W360_Incident_Log__c> scenarioValidationRuleBlocksFlow(Datetime anchor) {
        return new List<W360_Incident_Log__c>{
            new W360_Incident_Log__c(
                Error_Message__c  =
                    'FIELD_CUSTOM_VALIDATION_EXCEPTION: Annual Revenue is required for converted accounts.\n'
                  + 'Error occurred while processing element Account_Create in Flow: Lead_Conversion_Flow.',
                Exception_Type__c = 'FIELD_CUSTOM_VALIDATION_EXCEPTION',
                Stack_Trace__c    =
                    'Flow: Lead_Conversion_Flow\n'
                  + '  Element: Account_Create (Create Records)\n'
                  + '  Object: Account\n'
                  + '  Field: AnnualRevenue\n'
                  + '  Validation Rule: Annual_Revenue_Required_On_Conversion',
                Apex_Class__c     = 'Lead_Conversion_Flow',
                Triggered_By__c   = 'Convert Lead — Sales Rep UI Action',
                Occurred_At__c    = clampPast(anchor.addMinutes(8)),
                Severity__c       = 'Critical',
                Hit_Count__c      = 12
            ),
            new W360_Incident_Log__c(
                Error_Message__c  =
                    'FIELD_CUSTOM_VALIDATION_EXCEPTION: Annual Revenue is required for converted accounts.',
                Exception_Type__c = 'FIELD_CUSTOM_VALIDATION_EXCEPTION',
                Stack_Trace__c    =
                    'Flow: Lead_Conversion_Flow\n'
                  + '  Element: Account_Create (Create Records)',
                Apex_Class__c     = 'Lead_Conversion_Flow',
                Triggered_By__c   = 'Convert Lead — API (integration user)',
                Occurred_At__c    = clampPast(anchor.addMinutes(23)),
                Severity__c       = 'Warning',
                Hit_Count__c      = 4
            )
        };
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static void deleteExisting() {
        List<W360_Incident_Log__c> existing = [SELECT Id FROM W360_Incident_Log__c LIMIT 200];
        if (!existing.isEmpty()) delete existing;
    }

    public static void cleanUp() {
        List<W360_Incident_Log__c> all = [SELECT Id FROM W360_Incident_Log__c LIMIT 200];
        if (!all.isEmpty()) {
            delete all;
            System.debug('✅ W360LiveDemoSeeder.cleanUp: deleted ' + all.size() + ' incident records.');
        } else {
            System.debug('W360LiveDemoSeeder.cleanUp: nothing to delete.');
        }
    }
}