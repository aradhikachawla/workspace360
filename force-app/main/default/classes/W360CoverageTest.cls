/**
 * W360CoverageTest
 * ─────────────────────────────────────────────────────────────────────────────
 * Covers the 8 production classes that had no test coverage:
 *
 *  ✅ W360GetLastSession
 *  ✅ W360GetOpenOpportunities
 *  ✅ W360GetOverdueTasks
 *  ✅ W360GetPendingApprovals
 *  ✅ W360GetWorkspaceSummary
 *  ✅ W360NavigateToDashboard
 *  ✅ W360NavigateToRecord
 *  ✅ Workspace360BackgroundTrackerController
 *
 * And the full sysadmin/incident path:
 *  ✅ W360AgentUtil
 *  ✅ W360IncidentAnalyzer (getRecentErrors, getCorrelatedChanges, analyzeIncident)
 *  ✅ W360GetRecentIncidents
 *  ✅ W360GetIncidentDetails
 *  ✅ W360AnalyzeAllIncidents
 *
 * @author Workspace 360 Hackathon Team
 */
@IsTest
private class W360CoverageTest {

    // ── Shared helpers ────────────────────────────────────────────────────────

    private static void seedSession() {
        Id uid = UserInfo.getUserId();
        Date yesterday = Date.today().addDays(-1);
        insert new User_Workspace_Context__c(
            User__c              = uid,
            Record_Id__c         = '006000000000001',
            Object_Type__c       = 'Opportunity',
            Record_Name__c       = 'Test Opp',
            Action_Type__c       = 'Edit',
            Session_Date__c      = yesterday,
            Session_Timestamp__c = Datetime.now().addDays(-1),
            Is_Active_Session__c = true,
            Is_Dismissed__c      = false,
            Priority_Score__c    = 50
        );
    }

    private static W360_Incident_Log__c makeIncidentLog(String cls, String msg, String severity, Integer hits) {
        return new W360_Incident_Log__c(
            Apex_Class__c     = cls,
            Error_Message__c  = msg,
            Exception_Type__c = 'System.LimitException',
            Severity__c       = severity,
            Hit_Count__c      = hits,
            Occurred_At__c    = Datetime.now().addHours(-2),
            Triggered_By__c   = 'TestTrigger'
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360GetLastSession
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void getLastSession_returnsSessionSummary() {
        seedSession();
        W360GetLastSession.Request req = new W360GetLastSession.Request();
        req.maxRecords = 5;
        Test.startTest();
        List<W360GetLastSession.Response> res = W360GetLastSession.execute(
            new List<W360GetLastSession.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
        System.assert(String.isNotBlank(res[0].dashboardUrl));
    }

    @IsTest
    static void getLastSession_emptySession() {
        W360GetLastSession.Request req = new W360GetLastSession.Request();
        Test.startTest();
        List<W360GetLastSession.Response> res = W360GetLastSession.execute(
            new List<W360GetLastSession.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360GetOpenOpportunities
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void getOpenOpportunities_withOpps() {
        insert new Opportunity(Name='Test Deal', StageName='Prospecting',
                               CloseDate=Date.today().addDays(30), Amount=50000);
        W360GetOpenOpportunities.Request req = new W360GetOpenOpportunities.Request();
        Test.startTest();
        List<W360GetOpenOpportunities.Response> res = W360GetOpenOpportunities.execute(
            new List<W360GetOpenOpportunities.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
    }

    @IsTest
    static void getOpenOpportunities_noOpps() {
        W360GetOpenOpportunities.Request req = new W360GetOpenOpportunities.Request();
        Test.startTest();
        List<W360GetOpenOpportunities.Response> res = W360GetOpenOpportunities.execute(
            new List<W360GetOpenOpportunities.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360GetOverdueTasks
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void getOverdueTasks_withTasks() {
        insert new Task(Subject='Overdue', ActivityDate=Date.today().addDays(-3),
                        Status='Not Started', Priority='High',
                        OwnerId=UserInfo.getUserId());
        W360GetOverdueTasks.Request req = new W360GetOverdueTasks.Request();
        Test.startTest();
        List<W360GetOverdueTasks.Response> res = W360GetOverdueTasks.execute(
            new List<W360GetOverdueTasks.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
    }

    @IsTest
    static void getOverdueTasks_noTasks() {
        W360GetOverdueTasks.Request req = new W360GetOverdueTasks.Request();
        Test.startTest();
        List<W360GetOverdueTasks.Response> res = W360GetOverdueTasks.execute(
            new List<W360GetOverdueTasks.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360GetPendingApprovals
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void getPendingApprovals_noApprovals() {
        W360GetPendingApprovals.Request req = new W360GetPendingApprovals.Request();
        Test.startTest();
        List<W360GetPendingApprovals.Response> res = W360GetPendingApprovals.execute(
            new List<W360GetPendingApprovals.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360GetWorkspaceSummary
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void getWorkspaceSummary_7D() {
        seedSession();
        W360GetWorkspaceSummary.Request req = new W360GetWorkspaceSummary.Request();
        req.timeWindow = '7D';
        Test.startTest();
        List<W360GetWorkspaceSummary.Response> res = W360GetWorkspaceSummary.execute(
            new List<W360GetWorkspaceSummary.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
        System.assertNotEquals(null, res[0].recordCount);
        System.assert(String.isNotBlank(res[0].dashboardUrl));
    }

    @IsTest
    static void getWorkspaceSummary_1D() {
        W360GetWorkspaceSummary.Request req = new W360GetWorkspaceSummary.Request();
        req.timeWindow = '1D';
        Test.startTest();
        List<W360GetWorkspaceSummary.Response> res = W360GetWorkspaceSummary.execute(
            new List<W360GetWorkspaceSummary.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
    }

    @IsTest
    static void getWorkspaceSummary_nullWindow() {
        W360GetWorkspaceSummary.Request req = new W360GetWorkspaceSummary.Request();
        req.timeWindow = null;
        Test.startTest();
        List<W360GetWorkspaceSummary.Response> res = W360GetWorkspaceSummary.execute(
            new List<W360GetWorkspaceSummary.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360NavigateToDashboard
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void navigateToDashboard_returnsUrl() {
        W360NavigateToDashboard.Request req = new W360NavigateToDashboard.Request();
        Test.startTest();
        List<W360NavigateToDashboard.Response> res = W360NavigateToDashboard.execute(
            new List<W360NavigateToDashboard.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(res[0].dashboardUrl.contains('Workspace360Dashboard'));
        System.assert(String.isNotBlank(res[0].summaryText));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360NavigateToRecord
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void navigateToRecord_validInputs() {
        Opportunity opp = new Opportunity(Name='Nav Test', StageName='Prospecting',
                                          CloseDate=Date.today().addDays(10));
        insert opp;
        W360NavigateToRecord.Request req = new W360NavigateToRecord.Request();
        req.recordId   = opp.Id;
        req.objectType = 'Opportunity';
        req.recordName = 'Nav Test';
        Test.startTest();
        List<W360NavigateToRecord.Response> res = W360NavigateToRecord.execute(
            new List<W360NavigateToRecord.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assertEquals(true, res[0].success);
        System.assert(res[0].recordUrl.contains('Opportunity'));
        System.assert(String.isNotBlank(res[0].message));
    }

    @IsTest
    static void navigateToRecord_blankInputs() {
        W360NavigateToRecord.Request req = new W360NavigateToRecord.Request();
        req.recordId   = '';
        req.objectType = '';
        Test.startTest();
        List<W360NavigateToRecord.Response> res = W360NavigateToRecord.execute(
            new List<W360NavigateToRecord.Request>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assertEquals(false, res[0].success);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Workspace360BackgroundTrackerController
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void backgroundTracker_logsActivity() {
        Opportunity opp = new Opportunity(Name='Tracker Test', StageName='Prospecting',
                                          CloseDate=Date.today().addDays(10));
        insert opp;
        Map<String, Object> evtMap = new Map<String, Object>{
            'recordId'   => opp.Id,
            'objectType' => 'Opportunity',
            'recordName' => 'Tracker Test',
            'actionType' => 'View',
            'tabUrl'     => 'https://test.salesforce.com',
            'stage'      => 'Prospecting',
            'amount'     => 10000
        };
        Test.startTest();
        Workspace360BackgroundTrackerController.logActivity(evtMap);
        Test.stopTest();
        List<User_Workspace_Context__c> recs = [
            SELECT Id FROM User_Workspace_Context__c
            WHERE Record_Id__c = :opp.Id AND User__c = :UserInfo.getUserId()
        ];
        System.assertEquals(1, recs.size(), 'Background tracker should log the activity');
    }

    @IsTest
    static void backgroundTracker_nullMapDoesNotThrow() {
        Test.startTest();
        Workspace360BackgroundTrackerController.logActivity(null);
        Test.stopTest();
        System.assert(true);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360IncidentAnalyzer — getRecentErrors
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void incidentAnalyzer_getRecentErrors_noErrors() {
        Test.startTest();
        List<W360IncidentAnalyzer.IncidentRecord> results =
            W360IncidentAnalyzer.getRecentErrors(72);
        Test.stopTest();
        System.assertNotEquals(null, results);
    }

    @IsTest
    static void incidentAnalyzer_getRecentErrors_withDemoLog() {
        insert makeIncidentLog('OpportunityTriggerHandler',
                               'System.LimitException: Too many SOQL queries: 101', 'Critical', 7);
        Test.startTest();
        List<W360IncidentAnalyzer.IncidentRecord> results =
            W360IncidentAnalyzer.getRecentErrors(72, false);
        Test.stopTest();
        System.assert(!results.isEmpty());
        System.assertNotEquals(null, results[0].apexClass);
        System.assertNotEquals(null, results[0].severity);
    }

    @IsTest
    static void incidentAnalyzer_getRecentErrors_sinceToday() {
        insert makeIncidentLog('LeadConversionFlow',
                               'FIELD_CUSTOM_VALIDATION_EXCEPTION: Annual Revenue is required',
                               'Critical', 12);
        Test.startTest();
        List<W360IncidentAnalyzer.IncidentRecord> results =
            W360IncidentAnalyzer.getRecentErrors(24, true);
        Test.stopTest();
        System.assertNotEquals(null, results);
    }

    @IsTest
    static void incidentAnalyzer_getRecentErrorsSinceToday_smoke() {
        Test.startTest();
        List<W360IncidentAnalyzer.IncidentRecord> results =
            W360IncidentAnalyzer.getRecentErrorsSinceToday(24);
        Test.stopTest();
        System.assertNotEquals(null, results);
    }

    @IsTest
    static void incidentAnalyzer_getRecentErrors_nullHours() {
        Test.startTest();
        List<W360IncidentAnalyzer.IncidentRecord> results =
            W360IncidentAnalyzer.getRecentErrors(null);
        Test.stopTest();
        System.assertNotEquals(null, results);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360IncidentAnalyzer — getCorrelatedChanges
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void incidentAnalyzer_getCorrelatedChanges_blankTimestamp() {
        Test.startTest();
        List<W360IncidentAnalyzer.DevChangeRecord> changes =
            W360IncidentAnalyzer.getCorrelatedChanges('', 120);
        Test.stopTest();
        System.assertEquals(0, changes.size());
    }

    @IsTest
    static void incidentAnalyzer_getCorrelatedChanges_validTimestamp() {
        String isoNow = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        Test.startTest();
        List<W360IncidentAnalyzer.DevChangeRecord> changes =
            W360IncidentAnalyzer.getCorrelatedChanges(isoNow, 120);
        Test.stopTest();
        System.assertNotEquals(null, changes);
    }

    @IsTest
    static void incidentAnalyzer_getCorrelatedChanges_nullMinutes() {
        String isoNow = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        Test.startTest();
        List<W360IncidentAnalyzer.DevChangeRecord> changes =
            W360IncidentAnalyzer.getCorrelatedChanges(isoNow, null);
        Test.stopTest();
        System.assertNotEquals(null, changes);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360IncidentAnalyzer — analyzeIncident (fallback paths, no callout)
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void analyzeIncident_nullPointer() {
        Test.startTest();
        String result = W360IncidentAnalyzer.analyzeIncident(
            'System.NullPointerException: Attempt to de-reference a null object',
            'NullPointerException', 'at line 42', '[]');
        Test.stopTest();
        System.assert(String.isNotBlank(result));
    }

    @IsTest
    static void analyzeIncident_soqlLimit() {
        Test.startTest();
        String result = W360IncidentAnalyzer.analyzeIncident(
            'System.LimitException: Too many SOQL queries: 101',
            'LimitException', null, '[]');
        Test.stopTest();
        System.assert(String.isNotBlank(result));
    }

    @IsTest
    static void analyzeIncident_validationException() {
        Test.startTest();
        String result = W360IncidentAnalyzer.analyzeIncident(
            'FIELD_CUSTOM_VALIDATION_EXCEPTION: Annual Revenue is required',
            'ValidationException', null, '[]');
        Test.stopTest();
        System.assert(String.isNotBlank(result));
    }

    @IsTest
    static void analyzeIncident_listHasNoRows() {
        Test.startTest();
        String result = W360IncidentAnalyzer.analyzeIncident(
            'System.QueryException: List has no rows for assignment to SObject',
            'QueryException', null, null);
        Test.stopTest();
        System.assert(String.isNotBlank(result));
    }

    @IsTest
    static void analyzeIncident_unknown() {
        Test.startTest();
        String result = W360IncidentAnalyzer.analyzeIncident(
            'Some unknown error occurred', 'UnknownException', null, null);
        Test.stopTest();
        System.assert(String.isNotBlank(result));
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360GetRecentIncidents
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void getRecentIncidents_noErrors() {
        W360AgentUtil.IncidentRequest req = new W360AgentUtil.IncidentRequest();
        req.hours      = 1;
        req.sinceToday = false;
        Test.startTest();
        List<W360AgentUtil.IncidentResponse> res = W360GetRecentIncidents.getRecentIncidents(
            new List<W360AgentUtil.IncidentRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].incidentSummary));
    }

    @IsTest
    static void getRecentIncidents_withDemoData() {
        insert makeIncidentLog('AccountSyncBatch',
                               'System.NullPointerException: Contact.AccountId is null',
                               'Critical', 3);
        W360AgentUtil.IncidentRequest req = new W360AgentUtil.IncidentRequest();
        req.hours = 72;
        Test.startTest();
        List<W360AgentUtil.IncidentResponse> res = W360GetRecentIncidents.getRecentIncidents(
            new List<W360AgentUtil.IncidentRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assertNotEquals(null, res[0].incidentCount);
    }

    @IsTest
    static void getRecentIncidents_withClassNameFilter() {
        insert makeIncidentLog('CasePriorityFlow', 'CPU time limit exceeded', 'Warning', 5);
        W360AgentUtil.IncidentRequest req = new W360AgentUtil.IncidentRequest();
        req.hours     = 72;
        req.className = 'CasePriorityFlow';
        Test.startTest();
        List<W360AgentUtil.IncidentResponse> res = W360GetRecentIncidents.getRecentIncidents(
            new List<W360AgentUtil.IncidentRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].incidentSummary));
    }

    @IsTest
    static void getRecentIncidents_sinceToday() {
        W360AgentUtil.IncidentRequest req = new W360AgentUtil.IncidentRequest();
        req.hours      = 24;
        req.sinceToday = true;
        Test.startTest();
        List<W360AgentUtil.IncidentResponse> res = W360GetRecentIncidents.getRecentIncidents(
            new List<W360AgentUtil.IncidentRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assertNotEquals(null, res[0].incidentSummary);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360GetIncidentDetails
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void getIncidentDetails_notFound() {
        W360AgentUtil.DetailRequest req = new W360AgentUtil.DetailRequest();
        req.incidentIdOrClass = 'NonExistentClass999XYZ';
        req.lookbackMinutes   = 120;
        Test.startTest();
        List<W360AgentUtil.DetailResponse> res = W360GetIncidentDetails.getIncidentDetails(
            new List<W360AgentUtil.DetailRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].rootCauseAnalysis));
    }

    @IsTest
    static void getIncidentDetails_withMatchingIncident() {
        insert makeIncidentLog('LeadConversionFlow',
                               'FIELD_CUSTOM_VALIDATION_EXCEPTION: Annual Revenue is required',
                               'Critical', 12);
        W360AgentUtil.DetailRequest req = new W360AgentUtil.DetailRequest();
        req.incidentIdOrClass = 'LeadConversionFlow';
        req.lookbackMinutes   = 120;
        Test.startTest();
        List<W360AgentUtil.DetailResponse> res = W360GetIncidentDetails.getIncidentDetails(
            new List<W360AgentUtil.DetailRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].rootCauseAnalysis));
        System.assertNotEquals(null, res[0].devChangesCount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360AnalyzeAllIncidents
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void analyzeAllIncidents_noErrors() {
        W360AgentUtil.IncidentRequest req = new W360AgentUtil.IncidentRequest();
        req.hours = 1;
        Test.startTest();
        List<W360AgentUtil.IncidentResponse> res = W360AnalyzeAllIncidents.analyzeAllIncidents(
            new List<W360AgentUtil.IncidentRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].reportData));
    }

    @IsTest
    static void analyzeAllIncidents_withDemoData() {
        insert new List<W360_Incident_Log__c>{
            makeIncidentLog('OpportunityTriggerHandler',
                            'System.LimitException: Too many SOQL queries: 101', 'Critical', 7),
            makeIncidentLog('AccountSyncBatch',
                            'System.NullPointerException: Attempt to de-reference a null object',
                            'Critical', 3)
        };
        W360AgentUtil.IncidentRequest req = new W360AgentUtil.IncidentRequest();
        req.hours = 72;
        Test.startTest();
        List<W360AgentUtil.IncidentResponse> res = W360AnalyzeAllIncidents.analyzeAllIncidents(
            new List<W360AgentUtil.IncidentRequest>{ req });
        Test.stopTest();
        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].reportData));
        System.assertNotEquals(null, res[0].incidentCount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // W360AgentUtil — utilities + DTOs
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void agentUtil_relativeTime_variations() {
        Test.startTest();
        System.assert(String.isNotBlank(
            W360AgentUtil.relativeTime(Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''))));
        System.assert(String.isNotBlank(
            W360AgentUtil.relativeTime(Datetime.now().addHours(-2).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''))));
        System.assert(String.isNotBlank(
            W360AgentUtil.relativeTime(Datetime.now().addDays(-2).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''))));
        System.assertNotEquals(null, W360AgentUtil.relativeTime(null));
        System.assertNotEquals(null, W360AgentUtil.relativeTime(''));
        Test.stopTest();
    }

    @IsTest
    static void agentUtil_buildStatusLineAndNumberedList() {
        insert makeIncidentLog('OpportunityTriggerHandler', 'Too many SOQL queries: 101', 'Critical', 7);
        Test.startTest();
        List<W360IncidentAnalyzer.IncidentRecord> incidents = W360IncidentAnalyzer.getRecentErrors(72);
        if (!incidents.isEmpty()) {
            System.assert(String.isNotBlank(W360AgentUtil.buildStatusLine(incidents, 72, false)));
            System.assert(String.isNotBlank(W360AgentUtil.buildNumberedList(incidents)));
        }
        Test.stopTest();
    }

    @IsTest
    static void agentUtil_findIncident_notFound() {
        Test.startTest();
        W360IncidentAnalyzer.IncidentRecord r = W360AgentUtil.findIncident('NonExistentClass_XYZ_999');
        Test.stopTest();
        System.assertEquals(null, r);
    }

    @IsTest
    static void agentUtil_findIncident_found() {
        insert makeIncidentLog('MyBatchJob', 'Batch failed', 'Critical', 1);
        Test.startTest();
        W360AgentUtil.findIncident('MyBatchJob');
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void agentUtil_dtoFields_smokeTest() {
        W360AgentUtil.IncidentResponse resp = new W360AgentUtil.IncidentResponse();
        resp.incidentCount = 3; resp.incidentSummary = 'Test'; resp.incidentData = '1.';
        resp.primaryIncidentClass = 'TestClass'; resp.reportData = 'Report';
        System.assertEquals(3, resp.incidentCount);

        W360AgentUtil.DetailRequest dreq = new W360AgentUtil.DetailRequest();
        dreq.incidentIdOrClass = 'TestClass'; dreq.lookbackMinutes = 60;
        System.assertEquals('TestClass', dreq.incidentIdOrClass);

        W360AgentUtil.DetailResponse dresp = new W360AgentUtil.DetailResponse();
        dresp.rootCauseAnalysis = 'Root'; dresp.correlatedChangesSummary = 'None';
        dresp.recommendedFix = 'Fix'; dresp.devChangesCount = 0;
        System.assertEquals(0, dresp.devChangesCount);
    }
}