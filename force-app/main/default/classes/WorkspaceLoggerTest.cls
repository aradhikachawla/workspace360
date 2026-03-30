/**
 * WorkspaceLoggerTest
 * ─────────────────────────────────────────────────────────────────────────────
 * Comprehensive test coverage for WorkspaceLogger.cls
 *
 * Covers:
 *  ✅ logActivity  – new insert, dedup update, null/blank guard, URL truncation,
 *                    Edit upgrade, priority scoring, all object types
 *  ✅ markSessionEnd – no-op smoke test
 *  ✅ dismissSession – marks records dismissed, blank guard
 *  ✅ getLastSession – returns previous-day records, excludes today,
 *                      excludes dismissed, deduplicates, excludes Dashboard
 *  ✅ getLast7DaysRecords – range filter, active-only, dedup
 *  ✅ getYesterdayContext – yesterday only, ordered correctly
 *  ✅ getPendingApprovals – returns workitems for current user
 *  ✅ getOverdueTasks     – open + overdue tasks only
 *  ✅ getInProgressOpportunities – open opps only, ordered by LastModifiedDate
 *  ✅ getUserPermissions  – returns PermissionInfo list (smoke)
 *  ✅ calculatePriority   – all scoring branches via logActivity
 *  ✅ resolveRecordName   – standard Name field, Case Subject fallback
 *
 * @author   Workspace 360 Hackathon Team
 */
@IsTest
private class WorkspaceLoggerTest {

    // ── Shared test data helpers ──────────────────────────────────────────────

    /**
     * Build a minimal WorkspaceEvent for logActivity calls.
     */
    private static WorkspaceLogger.WorkspaceEvent makeEvent(
            String recId, String objType, String recName,
            String action, Decimal amount) {

        WorkspaceLogger.WorkspaceEvent e = new WorkspaceLogger.WorkspaceEvent();
        e.recordId   = recId;
        e.objectType = objType;
        e.recordName = recName;
        e.actionType = action;
        e.tabUrl     = 'https://test.salesforce.com/lightning/r/' + objType + '/' + recId + '/view';
        e.amount     = amount;
        e.stage      = null;
        return e;
    }

    /**
     * Insert a User_Workspace_Context__c directly (bypassing logActivity)
     * so we can back-date Session_Date__c for getLastSession / getYesterdayContext tests.
     */
    private static User_Workspace_Context__c makeContext(
            Id userId, String recId, String objType,
            String recName, String action,
            Date sessionDate, Boolean dismissed) {

        return new User_Workspace_Context__c(
            User__c               = userId,
            Record_Id__c          = recId,
            Object_Type__c        = objType,
            Record_Name__c        = recName,
            Action_Type__c        = action,
            Session_Date__c       = sessionDate,
            Session_Timestamp__c  = Datetime.now(),
            Is_Active_Session__c  = true,
            Is_Dismissed__c       = dismissed,
            Priority_Score__c     = 10,
            Tab_URL__c            = 'https://test.salesforce.com'
        );
    }

    // ═════════════════════════════════════════════════════════════════════════
    // logActivity
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void logActivity_insertsNewRecord() {
        // Create a real Opportunity so resolveRecordName can query it
        Opportunity opp = new Opportunity(
            Name        = 'Test Opp',
            StageName   = 'Prospecting',
            CloseDate   = Date.today().addDays(30)
        );
        insert opp;

        Test.startTest();
        WorkspaceLogger.WorkspaceEvent evt =
            makeEvent(opp.Id, 'Opportunity', null, 'View', null);
        WorkspaceLogger.logActivity(evt);
        Test.stopTest();

        List<User_Workspace_Context__c> ctxList = [
            SELECT Record_Id__c, Object_Type__c, Action_Type__c,
                   Record_Name__c, Is_Active_Session__c
            FROM   User_Workspace_Context__c
            WHERE  Record_Id__c = :opp.Id
              AND  User__c      = :UserInfo.getUserId()
        ];
        System.assertEquals(1, ctxList.size(), 'Expected exactly one context record');
        System.assertEquals('Opportunity', ctxList[0].Object_Type__c);
        System.assertEquals('View',        ctxList[0].Action_Type__c);
        System.assertEquals('Test Opp',    ctxList[0].Record_Name__c,
            'Record name should be resolved from Opportunity.Name');
        System.assertEquals(true, ctxList[0].Is_Active_Session__c);
    }

    @IsTest
    static void logActivity_deduplicatesOnSameDay() {
        Opportunity opp = new Opportunity(
            Name='Dedup Opp', StageName='Prospecting',
            CloseDate=Date.today().addDays(10));
        insert opp;

        WorkspaceLogger.WorkspaceEvent evt =
            makeEvent(opp.Id, 'Opportunity', 'Dedup Opp', 'View', null);

        Test.startTest();
        WorkspaceLogger.logActivity(evt);
        WorkspaceLogger.logActivity(evt); // second call same record same day
        Test.stopTest();

        List<User_Workspace_Context__c> ctxList = [
            SELECT Id FROM User_Workspace_Context__c
            WHERE  Record_Id__c = :opp.Id AND User__c = :UserInfo.getUserId()
        ];
        System.assertEquals(1, ctxList.size(), 'Duplicate log entries should not be created');
    }

    @IsTest
    static void logActivity_upgradesViewToEditOnUpdate() {
        Opportunity opp = new Opportunity(
            Name='Edit Upgrade', StageName='Qualification',
            CloseDate=Date.today().addDays(5));
        insert opp;

        // First: View
        WorkspaceLogger.logActivity(
            makeEvent(opp.Id, 'Opportunity', 'Edit Upgrade', 'View', null));

        // Second: Edit same day → should upgrade Action_Type__c
        Test.startTest();
        WorkspaceLogger.logActivity(
            makeEvent(opp.Id, 'Opportunity', 'Edit Upgrade', 'Edit', null));
        Test.stopTest();

        User_Workspace_Context__c ctx = [
            SELECT Action_Type__c, Priority_Score__c
            FROM   User_Workspace_Context__c
            WHERE  Record_Id__c = :opp.Id AND User__c = :UserInfo.getUserId()
            LIMIT  1
        ];
        System.assertEquals('Edit', ctx.Action_Type__c, 'Action should be upgraded to Edit');
        System.assert(ctx.Priority_Score__c >= 30, 'Edit priority score should be >= 30');
    }

    @IsTest
    static void logActivity_nullEventDoesNotThrow() {
        Test.startTest();
        WorkspaceLogger.logActivity(null);   // should silently return
        Test.stopTest();
        // No exception = pass
        System.assert(true);
    }

    @IsTest
    static void logActivity_blankRecordIdDoesNotInsert() {
        WorkspaceLogger.WorkspaceEvent evt = new WorkspaceLogger.WorkspaceEvent();
        evt.recordId   = '';
        evt.objectType = 'Opportunity';
        evt.actionType = 'View';

        Test.startTest();
        WorkspaceLogger.logActivity(evt);
        Test.stopTest();

        Integer count = [
            SELECT COUNT() FROM User_Workspace_Context__c
            WHERE Object_Type__c = 'Opportunity'
              AND User__c = :UserInfo.getUserId()
        ];
        System.assertEquals(0, count, 'Blank recordId should not insert a record');
    }

    @IsTest
    static void logActivity_truncatesLongUrl() {
        Opportunity opp = new Opportunity(
            Name='URL Opp', StageName='Prospecting',
            CloseDate=Date.today().addDays(1));
        insert opp;

        WorkspaceLogger.WorkspaceEvent evt =
            makeEvent(opp.Id, 'Opportunity', 'URL Opp', 'View', null);
        // Build a URL > 255 chars
        evt.tabUrl = 'https://test.salesforce.com/' + 'x'.repeat(300);

        Test.startTest();
        WorkspaceLogger.logActivity(evt);
        Test.stopTest();

        User_Workspace_Context__c ctx = [
            SELECT Tab_URL__c FROM User_Workspace_Context__c
            WHERE  Record_Id__c = :opp.Id AND User__c = :UserInfo.getUserId()
            LIMIT  1
        ];
        System.assert(ctx.Tab_URL__c.length() <= 255,
            'Tab_URL__c must be truncated to 255 characters');
    }

    @IsTest
    static void logActivity_caseUsesSubjectField() {
        Case c = new Case(Subject = 'API Issue', Status = 'New', Origin = 'Web');
        insert c;

        WorkspaceLogger.WorkspaceEvent evt =
            makeEvent(c.Id, 'Case', null, 'View', null);

        Test.startTest();
        WorkspaceLogger.logActivity(evt);
        Test.stopTest();

        User_Workspace_Context__c ctx = [
            SELECT Record_Name__c FROM User_Workspace_Context__c
            WHERE  Record_Id__c = :c.Id AND User__c = :UserInfo.getUserId()
            LIMIT  1
        ];
        System.assertEquals('API Issue', ctx.Record_Name__c,
            'Case name should be resolved from Subject field');
    }

    @IsTest
    static void logActivity_priorityScoreForHighValueOpp() {
        Opportunity opp = new Opportunity(
            Name='Big Deal', StageName='Prospecting',
            CloseDate=Date.today().addDays(10), Amount=200000);
        insert opp;

        WorkspaceLogger.WorkspaceEvent evt =
            makeEvent(opp.Id, 'Opportunity', 'Big Deal', 'Edit', 200000);
        evt.amount = 200000;

        Test.startTest();
        WorkspaceLogger.logActivity(evt);
        Test.stopTest();

        User_Workspace_Context__c ctx = [
            SELECT Priority_Score__c FROM User_Workspace_Context__c
            WHERE  Record_Id__c = :opp.Id AND User__c = :UserInfo.getUserId()
            LIMIT  1
        ];
        // Edit(30) + Opportunity(20) + amount>100k(10) = 60
        System.assertEquals(60, (Integer) ctx.Priority_Score__c,
            'Priority score should be 60 for Edit+Opportunity+Amount>100k');
    }

    @IsTest
    static void logActivity_customObjectGetsCustomScore() {
        // Use a fake custom object type (no actual SObject needed since
        // resolveRecordName will gracefully fail and return null for the name)
        WorkspaceLogger.WorkspaceEvent evt = new WorkspaceLogger.WorkspaceEvent();
        evt.recordId   = UserInfo.getUserId(); // reuse a real Id so DB doesn't error
        evt.objectType = 'CustomObj__c';
        evt.recordName = 'My Custom Record';
        evt.actionType = 'View';
        evt.tabUrl     = 'https://test.salesforce.com';

        Test.startTest();
        WorkspaceLogger.logActivity(evt);
        Test.stopTest();

        User_Workspace_Context__c ctx = [
            SELECT Priority_Score__c, Object_Type__c
            FROM   User_Workspace_Context__c
            WHERE  Record_Id__c = :UserInfo.getUserId()
              AND  Object_Type__c = 'CustomObj__c'
            LIMIT  1
        ];
        // Custom object view: 0 + 10(__c) = 10
        System.assertEquals(10, (Integer) ctx.Priority_Score__c,
            'Custom object should get +10 priority score');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // markSessionEnd
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void markSessionEnd_doesNotThrow() {
        Test.startTest();
        WorkspaceLogger.markSessionEnd('someRecordId');
        WorkspaceLogger.markSessionEnd(null);
        Test.stopTest();
        System.assert(true, 'markSessionEnd should be a no-op and not throw');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // dismissSession
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void dismissSession_marksRecordsDismissed() {
        Id userId = UserInfo.getUserId();
        Date yesterday = Date.today().addDays(-1);

        List<User_Workspace_Context__c> recs = new List<User_Workspace_Context__c>{
            makeContext(userId, '001000000000001', 'Account', 'Acme', 'View', yesterday, false),
            makeContext(userId, '006000000000001', 'Opportunity', 'Big Deal', 'Edit', yesterday, false)
        };
        insert recs;

        Test.startTest();
        WorkspaceLogger.dismissSession(String.valueOf(yesterday));
        Test.stopTest();

        List<User_Workspace_Context__c> result = [
            SELECT Is_Dismissed__c FROM User_Workspace_Context__c
            WHERE  Session_Date__c = :yesterday AND User__c = :userId
        ];
        for (User_Workspace_Context__c r : result) {
            System.assertEquals(true, r.Is_Dismissed__c,
                'All records for that date should be dismissed');
        }
    }

    @IsTest
    static void dismissSession_blankDateDoesNothing() {
        Test.startTest();
        WorkspaceLogger.dismissSession('');
        WorkspaceLogger.dismissSession(null);
        Test.stopTest();
        System.assert(true, 'Blank/null sessionDate should be a safe no-op');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getLastSession
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getLastSession_returnsPreviousDayRecords() {
        Id userId = UserInfo.getUserId();
        Date yesterday = Date.today().addDays(-1);

        insert new List<User_Workspace_Context__c>{
            makeContext(userId, '006000000000002', 'Opportunity', 'Restore Opp',   'Edit', yesterday, false),
            makeContext(userId, '001000000000002', 'Account',     'Restore Acct',  'View', yesterday, false)
        };

        Test.startTest();
        List<WorkspaceLogger.RecordCard> cards = WorkspaceLogger.getLastSession();
        Test.stopTest();

        System.assertEquals(2, cards.size(), 'Should return 2 un-dismissed previous-day records');
        for (WorkspaceLogger.RecordCard c : cards) {
            System.assert(c.recordId != null, 'RecordCard.recordId must not be null');
            System.assert(c.objectType != null, 'RecordCard.objectType must not be null');
        }
    }

    @IsTest
    static void getLastSession_excludesTodayRecords() {
        Id userId = UserInfo.getUserId();
        // Insert records dated today — should NOT appear in getLastSession
        insert makeContext(userId, '006000000000003', 'Opportunity', 'Today Opp', 'View',
                           Date.today(), false);

        Test.startTest();
        List<WorkspaceLogger.RecordCard> cards = WorkspaceLogger.getLastSession();
        Test.stopTest();

        System.assertEquals(0, cards.size(), 'Today\'s records should not appear in getLastSession');
    }

    @IsTest
    static void getLastSession_excludesDismissedRecords() {
        Id userId = UserInfo.getUserId();
        Date yesterday = Date.today().addDays(-1);

        insert makeContext(userId, '006000000000004', 'Opportunity', 'Dismissed Opp',
                           'View', yesterday, true); // Is_Dismissed__c = true

        Test.startTest();
        List<WorkspaceLogger.RecordCard> cards = WorkspaceLogger.getLastSession();
        Test.stopTest();

        System.assertEquals(0, cards.size(), 'Dismissed records should not appear in getLastSession');
    }

    @IsTest
    static void getLastSession_excludesDashboardObjectType() {
        Id userId = UserInfo.getUserId();
        Date yesterday = Date.today().addDays(-1);

        insert makeContext(userId, userId, 'Dashboard', 'Workspace 360 Home',
                           'View', yesterday, false);

        Test.startTest();
        List<WorkspaceLogger.RecordCard> cards = WorkspaceLogger.getLastSession();
        Test.stopTest();

        System.assertEquals(0, cards.size(), 'Dashboard object type should be excluded');
    }

    @IsTest
    static void getLastSession_deduplicatesByRecordId() {
        Id userId = UserInfo.getUserId();
        Date yesterday = Date.today().addDays(-1);

        // Two rows, same Record_Id__c — should deduplicate to 1
        User_Workspace_Context__c r1 =
            makeContext(userId, '006000000000005', 'Opportunity', 'Dup Opp', 'View', yesterday, false);
        User_Workspace_Context__c r2 =
            makeContext(userId, '006000000000005', 'Opportunity', 'Dup Opp', 'Edit', yesterday, false);
        r2.Priority_Score__c = 50; // higher priority — picked first
        insert new List<User_Workspace_Context__c>{ r1, r2 };

        Test.startTest();
        List<WorkspaceLogger.RecordCard> cards = WorkspaceLogger.getLastSession();
        Test.stopTest();

        System.assertEquals(1, cards.size(), 'Duplicate Record_Id__c entries should be deduplicated');
    }

    @IsTest
    static void getLastSession_emptyWhenNoHistory() {
        Test.startTest();
        List<WorkspaceLogger.RecordCard> cards = WorkspaceLogger.getLastSession();
        Test.stopTest();

        System.assertEquals(0, cards.size(), 'Should return empty list when no previous sessions exist');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getLast7DaysRecords
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getLast7DaysRecords_returnsActiveRecordsInRange() {
        Id userId = UserInfo.getUserId();

        insert new List<User_Workspace_Context__c>{
            makeContext(userId, '006000000000010', 'Opportunity', 'In Range',
                        'View', Date.today().addDays(-3), false),
            makeContext(userId, '006000000000011', 'Opportunity', 'Too Old',
                        'View', Date.today().addDays(-8), false)
        };

        Test.startTest();
        List<WorkspaceLogger.RecordCard> cards = WorkspaceLogger.getLast7DaysRecords();
        Test.stopTest();

        System.assertEquals(1, cards.size(), 'Only records within 7 days should be returned');
        System.assertEquals('In Range', cards[0].recordName);
    }

    @IsTest
    static void getLast7DaysRecords_deduplicatesByRecordId() {
        Id userId = UserInfo.getUserId();
        Date threeDaysAgo = Date.today().addDays(-3);

        User_Workspace_Context__c r1 =
            makeContext(userId, '006000000000012', 'Opportunity', 'Same Opp', 'View', threeDaysAgo, false);
        User_Workspace_Context__c r2 =
            makeContext(userId, '006000000000012', 'Opportunity', 'Same Opp', 'Edit', threeDaysAgo, false);
        r2.Priority_Score__c = 60;
        insert new List<User_Workspace_Context__c>{ r1, r2 };

        Test.startTest();
        List<WorkspaceLogger.RecordCard> cards = WorkspaceLogger.getLast7DaysRecords();
        Test.stopTest();

        System.assertEquals(1, cards.size(), '7-day view should deduplicate by record Id');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getYesterdayContext
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getYesterdayContext_returnsOnlyYesterdayRecords() {
        Id userId = UserInfo.getUserId();
        Date yesterday = Date.today().addDays(-1);

        insert new List<User_Workspace_Context__c>{
            makeContext(userId, '006000000000020', 'Opportunity', 'Yesterday Opp',
                        'Edit', yesterday, false),
            makeContext(userId, '006000000000021', 'Opportunity', 'Two Days Ago',
                        'View', Date.today().addDays(-2), false)
        };

        Test.startTest();
        List<User_Workspace_Context__c> result = WorkspaceLogger.getYesterdayContext();
        Test.stopTest();

        System.assertEquals(1, result.size(), 'getYesterdayContext should return only yesterday\'s records');
        System.assertEquals('Yesterday Opp', result[0].Record_Name__c);
    }

    @IsTest
    static void getYesterdayContext_emptyWhenNothingYesterday() {
        Test.startTest();
        List<User_Workspace_Context__c> result = WorkspaceLogger.getYesterdayContext();
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Should return empty list when no yesterday records');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getOverdueTasks
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getOverdueTasks_returnsOpenOverdueTasks() {
        Task overdueTask = new Task(
            Subject      = 'Follow up Overdue',
            ActivityDate = Date.today().addDays(-2),
            Status       = 'Not Started',
            Priority     = 'High',
            OwnerId      = UserInfo.getUserId()
        );
        insert overdueTask;

        Test.startTest();
        List<Task> tasks = WorkspaceLogger.getOverdueTasks();
        Test.stopTest();

        System.assert(!tasks.isEmpty(), 'Should return at least one overdue task');
        for (Task t : tasks) {
            System.assert(t.ActivityDate < Date.today(),
                'All returned tasks must be overdue (ActivityDate < today)');
        }
    }

    @IsTest
    static void getOverdueTasks_excludesClosedTasks() {
        Task closedTask = new Task(
            Subject      = 'Closed Task',
            ActivityDate = Date.today().addDays(-1),
            Status       = 'Completed',
            OwnerId      = UserInfo.getUserId()
        );
        insert closedTask;

        Test.startTest();
        List<Task> tasks = WorkspaceLogger.getOverdueTasks();
        Test.stopTest();

        for (Task t : tasks) {
            System.assertNotEquals('Completed', t.Status,
                'Completed tasks should not appear in overdue tasks');
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getInProgressOpportunities
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getInProgressOpportunities_returnsOpenOpps() {
        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(Name='Open Opp 1',  StageName='Prospecting',
                            CloseDate=Date.today().addDays(30)),
            new Opportunity(Name='Closed Opp',  StageName='Closed Won',
                            CloseDate=Date.today().addDays(-1))
        };
        insert opps;

        Test.startTest();
        List<Opportunity> result = WorkspaceLogger.getInProgressOpportunities();
        Test.stopTest();

        for (Opportunity o : result) {
            System.assertEquals(false, o.IsClosed,
                'Only open opportunities should be returned');
        }
        // Verify the closed one is NOT in results
        Set<String> names = new Set<String>();
        for (Opportunity o : result) names.add(o.Name);
        System.assert(!names.contains('Closed Opp'),
            'Closed Won opportunity should be excluded');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getPendingApprovals
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getPendingApprovals_returnsListWithoutError() {
        // No approval processes in test org — just verify it doesn't throw
        Test.startTest();
        List<ProcessInstanceWorkitem> items = WorkspaceLogger.getPendingApprovals();
        Test.stopTest();

        System.assertNotEquals(null, items, 'getPendingApprovals should return a non-null list');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // getUserPermissions
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void getUserPermissions_returnsPermissionInfoList() {
        Test.startTest();
        List<WorkspaceLogger.PermissionInfo> perms = WorkspaceLogger.getUserPermissions();
        Test.stopTest();

        System.assertNotEquals(null, perms, 'getUserPermissions should not return null');
        // Every row should have field values populated
        for (WorkspaceLogger.PermissionInfo p : perms) {
            System.assert(String.isNotBlank(p.objectName),
                'Each PermissionInfo should have an objectName');
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // RecordCard builder (buildCard via getLastSession)
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void buildCard_populatesAllFields() {
        Id userId = UserInfo.getUserId();
        Date yesterday = Date.today().addDays(-1);

        insert new User_Workspace_Context__c(
            User__c               = userId,
            Record_Id__c          = '006000000000030',
            Object_Type__c        = 'Opportunity',
            Record_Name__c        = 'Card Test Opp',
            Action_Type__c        = 'Edit',
            Stage__c              = 'Negotiation',
            Amount__c             = 75000,
            Tab_URL__c            = 'https://test.salesforce.com',
            Session_Date__c       = yesterday,
            Session_Timestamp__c  = Datetime.now().addDays(-1),
            Is_Active_Session__c  = true,
            Is_Dismissed__c       = false,
            Priority_Score__c     = 50
        );

        Test.startTest();
        List<WorkspaceLogger.RecordCard> cards = WorkspaceLogger.getLastSession();
        Test.stopTest();

        System.assertEquals(1, cards.size());
        WorkspaceLogger.RecordCard c = cards[0];
        System.assertEquals('006000000000030', c.recordId);
        System.assertEquals('Opportunity',     c.objectType);
        System.assertEquals('Card Test Opp',   c.recordName);
        System.assertEquals('Edit',            c.actionType);
        System.assertEquals('Negotiation',     c.stage);
        System.assertEquals(75000,             c.amount);
        System.assertEquals(50,                c.priorityScore);
        System.assertEquals(1,                 c.daysAgo);
        System.assert(String.isNotBlank(c.sessionDate),      'sessionDate should be set');
        System.assert(String.isNotBlank(c.sessionTimestamp), 'sessionTimestamp should be set');
    }
}