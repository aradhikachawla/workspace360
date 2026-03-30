/**
 * AgentforceSummaryTest
 * ─────────────────────────────────────────────────────────────────────────────
 * Comprehensive test coverage for AgentforceSummary.cls
 *
 * Covers:
 *  ✅ generateSummary – null/empty input returns default message
 *  ✅ generateSummary – callout success path (mocked HTTP response)
 *  ✅ generateSummary – callout failure falls back to rule-based summary
 *  ✅ buildFallbackSummary – correct counts for Edit / View / Approve
 *  ✅ generateSummaryAsync – future method smoke test
 *
 * @author   Workspace 360 Hackathon Team
 */
@IsTest
private class AgentforceSummaryTest {

    // ── Mock: successful Einstein GenAI response ──────────────────────────────
    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"generations":[{"text":"Yesterday you edited 3 opportunities. Focus on closing the Negotiation stage deals today."}]}');
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    // ── Mock: failed Einstein GenAI response (500) ────────────────────────────
    private class FailMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    // ── Helper: build context records ────────────────────────────────────────
    private static List<User_Workspace_Context__c> makeContextRecords(
            Integer viewCount, Integer editCount, Integer approveCount) {

        Id userId = UserInfo.getUserId();
        List<User_Workspace_Context__c> recs = new List<User_Workspace_Context__c>();
        Date yesterday = Date.today().addDays(-1);

        for (Integer i = 0; i < viewCount; i++) {
            recs.add(new User_Workspace_Context__c(
                User__c              = userId,
                Record_Id__c         = '006' + String.valueOf(i).leftPad(12, '0'),
                Object_Type__c       = 'Opportunity',
                Record_Name__c       = 'View Opp ' + i,
                Action_Type__c       = 'View',
                Session_Date__c      = yesterday,
                Session_Timestamp__c = Datetime.now().addDays(-1),
                Is_Active_Session__c = true,
                Is_Dismissed__c      = false
            ));
        }
        for (Integer i = 0; i < editCount; i++) {
            recs.add(new User_Workspace_Context__c(
                User__c              = userId,
                Record_Id__c         = '007' + String.valueOf(i).leftPad(12, '0'),
                Object_Type__c       = 'Opportunity',
                Record_Name__c       = 'Edit Opp ' + i,
                Action_Type__c       = 'Edit',
                Session_Date__c      = yesterday,
                Session_Timestamp__c = Datetime.now().addDays(-1),
                Is_Active_Session__c = true,
                Is_Dismissed__c      = false
            ));
        }
        for (Integer i = 0; i < approveCount; i++) {
            recs.add(new User_Workspace_Context__c(
                User__c              = userId,
                Record_Id__c         = '008' + String.valueOf(i).leftPad(12, '0'),
                Object_Type__c       = 'Opportunity',
                Record_Name__c       = 'Approve Opp ' + i,
                Action_Type__c       = 'Approve',
                Session_Date__c      = yesterday,
                Session_Timestamp__c = Datetime.now().addDays(-1),
                Is_Active_Session__c = true,
                Is_Dismissed__c      = false
            ));
        }
        return recs;
    }

    // ═════════════════════════════════════════════════════════════════════════
    // generateSummary – null / empty input
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void generateSummary_nullInputReturnsDefault() {
        Test.startTest();
        String result = AgentforceSummary.generateSummary(null);
        Test.stopTest();

        System.assert(String.isNotBlank(result),
            'Should return a default non-blank string for null input');
        System.assert(result.containsIgnoreCase('No activity'),
            'Default message should mention no activity');
    }

    @IsTest
    static void generateSummary_emptyListReturnsDefault() {
        Test.startTest();
        String result = AgentforceSummary.generateSummary(
            new List<User_Workspace_Context__c>());
        Test.stopTest();

        System.assert(String.isNotBlank(result),
            'Should return a default non-blank string for empty list');
        System.assert(result.containsIgnoreCase('No activity'),
            'Default message should mention no activity');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // generateSummary – callout success (mocked)
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void generateSummary_calloutSuccessReturnsAIText() {
        List<User_Workspace_Context__c> recs = makeContextRecords(3, 2, 0);
        insert recs;

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        String result = AgentforceSummary.generateSummary(recs);
        Test.stopTest();

        System.assert(String.isNotBlank(result),
            'Result should be non-blank on successful callout');
        System.assert(result.contains('opportunities') || result.contains('deals'),
            'AI response text should be returned from the mock');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // generateSummary – callout failure → fallback
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void generateSummary_calloutFailureFallsBackToRuleBased() {
        List<User_Workspace_Context__c> recs = makeContextRecords(5, 2, 1);
        insert recs;

        Test.setMock(HttpCalloutMock.class, new FailMock());

        Test.startTest();
        String result = AgentforceSummary.generateSummary(recs);
        Test.stopTest();

        System.assert(String.isNotBlank(result),
            'Fallback summary should not be blank');
        // Fallback text includes record counts
        System.assert(result.contains('8') || result.contains('records'),
            'Fallback should reference total record count');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Fallback summary – correct counts for each action type
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void generateSummary_fallbackCountsEditsAndViews() {
        List<User_Workspace_Context__c> recs = makeContextRecords(10, 3, 0);
        insert recs;

        Test.setMock(HttpCalloutMock.class, new FailMock());

        Test.startTest();
        String result = AgentforceSummary.generateSummary(recs);
        Test.stopTest();

        System.assert(result.contains('3 edits'),
            'Fallback summary should show correct edit count (3)');
        System.assert(result.contains('10 record views'),
            'Fallback summary should show correct view count (10)');
        System.assert(!result.contains('approvals'),
            'Fallback summary should not mention approvals when count is 0');
    }

    @IsTest
    static void generateSummary_fallbackIncludesApprovalsWhenPresent() {
        List<User_Workspace_Context__c> recs = makeContextRecords(2, 1, 2);
        insert recs;

        Test.setMock(HttpCalloutMock.class, new FailMock());

        Test.startTest();
        String result = AgentforceSummary.generateSummary(recs);
        Test.stopTest();

        System.assert(result.contains('2 approvals'),
            'Fallback summary should mention approval count when > 0');
    }

    @IsTest
    static void generateSummary_fallbackIncludesResumeSessionPrompt() {
        List<User_Workspace_Context__c> recs = makeContextRecords(1, 0, 0);
        insert recs;

        Test.setMock(HttpCalloutMock.class, new FailMock());

        Test.startTest();
        String result = AgentforceSummary.generateSummary(recs);
        Test.stopTest();

        System.assert(result.containsIgnoreCase('Resume Session'),
            'Fallback should prompt user to use the Resume Session button');
    }

    // ═════════════════════════════════════════════════════════════════════════
    // generateSummaryAsync (future method smoke test)
    // ═════════════════════════════════════════════════════════════════════════

    @IsTest
    static void generateSummaryAsync_doesNotThrow() {
        List<User_Workspace_Context__c> recs = makeContextRecords(2, 1, 0);
        insert recs;

        Set<Id> ids = new Set<Id>();
        for (User_Workspace_Context__c r : recs) ids.add(r.Id);

        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        AgentforceSummary.generateSummaryAsync(ids);
        Test.stopTest();

        // Verify AI_Summary__c was written back to the first record
        User_Workspace_Context__c updated = [
            SELECT AI_Summary__c FROM User_Workspace_Context__c
            WHERE Id = :recs[0].Id
        ];
        System.assert(String.isNotBlank(updated.AI_Summary__c),
            'generateSummaryAsync should write AI summary back to the first record');
    }

    @IsTest
    static void generateSummaryAsync_emptyIdsDoesNotThrow() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());

        Test.startTest();
        AgentforceSummary.generateSummaryAsync(new Set<Id>());
        Test.stopTest();

        System.assert(true, 'Empty Id set should be a safe no-op');
    }
}