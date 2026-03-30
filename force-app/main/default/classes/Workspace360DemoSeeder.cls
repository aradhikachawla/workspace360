/**
 * Workspace360DemoSeeder
 * ─────────────────────────────────────────────────────────────────────────────
 * Deployable Apex class to seed realistic demo data across 1D, 7D, and 30D
 * activity windows. Each method is self-contained and idempotent.
 *
 * Deploy:
 *   sf project deploy start --source-dir force-app --target-org <alias>
 *
 * Run via CLI (pick one):
 *   sf apex run --file scripts/seed_1day.apex   --target-org <alias>
 *   sf apex run --file scripts/seed_7day.apex   --target-org <alias>
 *   sf apex run --file scripts/seed_30day.apex  --target-org <alias>
 *   sf apex run --file scripts/seed_all.apex    --target-org <alias>
 *   sf apex run --file scripts/seed_reset.apex  --target-org <alias>
 *
 * Or from Developer Console → Execute Anonymous:
 *   Workspace360DemoSeeder.seedAll();
 *   Workspace360DemoSeeder.seed1Day();
 *   Workspace360DemoSeeder.seed7Days();
 *   Workspace360DemoSeeder.seed30Days();
 *   Workspace360DemoSeeder.resetAll();
 */
public with sharing class Workspace360DemoSeeder {

    // ── Public entry points ───────────────────────────────────────────────────

    /** Seed everything: yesterday + last 7 days + last 30 days */
    @AuraEnabled
    public static String seedAll() {
        resetContextOnly();
        SeedResult r = new SeedResult();
        r.addFrom(buildYesterdayData());
        r.addFrom(buildWeekData());
        r.addFrom(buildMonthData());
        return r.summary();
    }

    /** Seed only yesterday's session (shows Session Restore banner + 1D tab) */
    @AuraEnabled
    public static String seed1Day() {
        resetContextOnly();
        SeedResult r = buildYesterdayData();
        return r.summary();
    }

    /** Seed yesterday + last 6 days (fills 7D tab) */
    @AuraEnabled
    public static String seed7Days() {
        resetContextOnly();
        SeedResult r = new SeedResult();
        r.addFrom(buildYesterdayData());
        r.addFrom(buildWeekData());
        return r.summary();
    }

    /** Seed all 30 days of activity */
    @AuraEnabled
    public static String seed30Days() {
        resetContextOnly();
        SeedResult r = new SeedResult();
        r.addFrom(buildYesterdayData());
        r.addFrom(buildWeekData());
        r.addFrom(buildMonthData());
        return r.summary();
    }

    /** Wipe all demo data (context + seeded SObjects) */
    @AuraEnabled
    public static String resetAll() {
        Id userId = UserInfo.getUserId();
        Integer total = 0;

        List<User_Workspace_Context__c> ctx = [SELECT Id FROM User_Workspace_Context__c WHERE User__c = :userId];
        if (!ctx.isEmpty()) { delete ctx; total += ctx.size(); }

        List<Opportunity> opps = [SELECT Id FROM Opportunity WHERE OwnerId = :userId
            AND Name IN ('Burlington Textiles Expansion','Acme Corp Strategic Deal',
                         'Grand Hotels SLA Renewal','United Healthcare Platform',
                         'Pyramid Construction Expansion','Edge Communications Renewal',
                         'Global Media Services Deal','TechStart Seed Round',
                         'Alpine Manufacturing Suite','Coastal Logistics Upgrade')];
        if (!opps.isEmpty()) { delete opps; total += opps.size(); }

        List<Account> accs = [SELECT Id FROM Account WHERE OwnerId = :userId
            AND Name IN ('Burlington Textiles Corp','Acme Corporation',
                         'United Healthcare Systems','Alpine Manufacturing',
                         'Coastal Logistics Group')];
        if (!accs.isEmpty()) { delete accs; total += accs.size(); }

        List<Case> cases = [SELECT Id FROM Case WHERE OwnerId = :userId
            AND Subject IN ('API Integration Issue - Urgent','Data Migration Validation Error',
                            'Dashboard Performance Slowdown','Login SSO Failure',
                            'Report Timeout Issue')];
        if (!cases.isEmpty()) { delete cases; total += cases.size(); }

        List<Lead> leads = [SELECT Id FROM Lead WHERE OwnerId = :userId
            AND LastName IN ('Connor','Park','Wilson','Patel','Nguyen')];
        if (!leads.isEmpty()) { delete leads; total += leads.size(); }

        List<Task> tasks = [SELECT Id FROM Task WHERE OwnerId = :userId
            AND Subject IN ('Follow up on Burlington proposal',
                            'Send pricing sheet to Acme Corp',
                            'Schedule demo with United Healthcare',
                            'Prepare Q2 forecast deck',
                            'Review Pyramid contract draft')];
        if (!tasks.isEmpty()) { delete tasks; total += tasks.size(); }

        return '✅ Reset complete. Deleted ' + total + ' records. Ready to re-seed.';
    }

    // ── Private builders ──────────────────────────────────────────────────────

    /**
     * YESTERDAY DATA — triggers Session Restore banner + populates 1D tab
     * Creates: 3 Opps, 1 Case, 1 Account, 1 Contact, 1 Lead
     * Context records all dated yesterday with realistic timestamps
     */
    private static SeedResult buildYesterdayData() {
        Id     userId    = UserInfo.getUserId();
        Date   yesterday = Date.today().addDays(-1);
        String orgUrl    = System.Url.getOrgDomainUrl().toExternalForm();
        SeedResult r = new SeedResult();

        // ── SObjects ──
        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(Name='Burlington Textiles Expansion', StageName='Negotiation',
                CloseDate=Date.today().addDays(14), Amount=235000),
            new Opportunity(Name='Acme Corp Strategic Deal', StageName='Proposal/Price Quote',
                CloseDate=Date.today().addDays(30), Amount=185000),
            new Opportunity(Name='Grand Hotels SLA Renewal', StageName='Closed Won',
                CloseDate=Date.today().addDays(-1), Amount=90000)
        };
        insert opps;
        r.opps += opps.size();

        Account acc = new Account(Name='Burlington Textiles Corp');
        insert acc;
        r.accounts++;

        Case cs = new Case(Subject='API Integration Issue - Urgent',
            Status='New', Origin='Web', Priority='High');
        insert cs;
        r.cases++;

        Contact con = new Contact(FirstName='John', LastName='Smith',
            AccountId=acc.Id, Email='john.smith@burlington.com');
        insert con;
        r.contacts++;

        Lead ld = new Lead(FirstName='Sarah', LastName='Connor',
            Company='Weaving Solutions Inc', LeadSource='Trade Show',
            Status='Working - Contacted');
        insert ld;
        r.leads++;

        Task tk = new Task(Subject='Follow up on Burlington proposal',
            ActivityDate=yesterday.addDays(-1), Status='Not Started',
            Priority='High', OwnerId=userId, WhatId=opps[0].Id);
        insert tk;
        r.tasks++;

        // ── Context records back-dated to yesterday ──
        List<User_Workspace_Context__c> ctx = new List<User_Workspace_Context__c>{
            makeCtx(userId, opps[0].Id, 'Opportunity', opps[0].Name, 'Edit',
                'Negotiation', 235000, orgUrl, yesterday, 16, 45, 60),
            makeCtx(userId, opps[1].Id, 'Opportunity', opps[1].Name, 'View',
                'Proposal/Price Quote', 185000, orgUrl, yesterday, 15, 30, 30),
            makeCtx(userId, opps[2].Id, 'Opportunity', opps[2].Name, 'View',
                'Closed Won', 90000, orgUrl, yesterday, 14, 0, 20),
            makeCtx(userId, cs.Id, 'Case', cs.Subject, 'View',
                'New', null, orgUrl, yesterday, 13, 15, 15),
            makeCtx(userId, acc.Id, 'Account', acc.Name, 'View',
                null, null, orgUrl, yesterday, 11, 0, 0),
            makeCtx(userId, con.Id, 'Contact', 'John Smith', 'View',
                null, null, orgUrl, yesterday, 10, 30, 0),
            makeCtx(userId, ld.Id, 'Lead', 'Sarah Connor', 'View',
                null, null, orgUrl, yesterday, 9, 45, 0)
        };
        insert ctx;
        r.ctxRecords += ctx.size();
        return r;
    }

    /**
     * WEEK DATA — fills 7D tab with activity on days 2–6 days ago
     * Reuses existing Opps + adds new ones for variety
     */
    private static SeedResult buildWeekData() {
        Id     userId = UserInfo.getUserId();
        String orgUrl = System.Url.getOrgDomainUrl().toExternalForm();
        SeedResult r  = new SeedResult();

        // New Opps for mid-week activity
        List<Opportunity> weekOpps = new List<Opportunity>{
            new Opportunity(Name='United Healthcare Platform', StageName='Value Proposition',
                CloseDate=Date.today().addDays(45), Amount=320000),
            new Opportunity(Name='Pyramid Construction Expansion', StageName='Qualification',
                CloseDate=Date.today().addDays(60), Amount=150000),
            new Opportunity(Name='Edge Communications Renewal', StageName='Needs Analysis',
                CloseDate=Date.today().addDays(21), Amount=78000)
        };
        insert weekOpps;
        r.opps += weekOpps.size();

        Case cs2 = new Case(Subject='Data Migration Validation Error',
            Status='In Progress', Origin='Email', Priority='Medium');
        insert cs2;
        r.cases++;

        Lead ld2 = new Lead(FirstName='James', LastName='Park',
            Company='DataStream Analytics', LeadSource='Web',
            Status='New');
        insert ld2;
        r.leads++;

        Task tk2 = new Task(Subject='Send pricing sheet to Acme Corp',
            ActivityDate=Date.today().addDays(-3), Status='Not Started',
            Priority='Normal', OwnerId=userId, WhatId=weekOpps[0].Id);
        insert tk2;
        r.tasks++;

        // ── Context records spread across days 2-6 ──
        List<User_Workspace_Context__c> ctx = new List<User_Workspace_Context__c>();

        // 2 days ago
        ctx.add(makeCtx(userId, weekOpps[0].Id, 'Opportunity', weekOpps[0].Name,
            'Edit', 'Value Proposition', 320000, orgUrl, Date.today().addDays(-2), 15, 0, 60));
        ctx.add(makeCtx(userId, cs2.Id, 'Case', cs2.Subject,
            'Edit', 'In Progress', null, orgUrl, Date.today().addDays(-2), 14, 0, 45));

        // 3 days ago
        ctx.add(makeCtx(userId, weekOpps[1].Id, 'Opportunity', weekOpps[1].Name,
            'View', 'Qualification', 150000, orgUrl, Date.today().addDays(-3), 16, 30, 30));
        ctx.add(makeCtx(userId, ld2.Id, 'Lead', 'James Park',
            'View', null, null, orgUrl, Date.today().addDays(-3), 11, 0, 0));

        // 4 days ago
        ctx.add(makeCtx(userId, weekOpps[2].Id, 'Opportunity', weekOpps[2].Name,
            'Edit', 'Needs Analysis', 78000, orgUrl, Date.today().addDays(-4), 10, 15, 30));

        // 5 days ago
        ctx.add(makeCtx(userId, weekOpps[0].Id, 'Opportunity', weekOpps[0].Name,
            'View', 'Prospecting', 320000, orgUrl, Date.today().addDays(-5), 14, 45, 20));

        // 6 days ago
        ctx.add(makeCtx(userId, weekOpps[1].Id, 'Opportunity', weekOpps[1].Name,
            'View', 'Qualification', 150000, orgUrl, Date.today().addDays(-6), 9, 30, 20));

        insert ctx;
        r.ctxRecords += ctx.size();
        return r;
    }

    /**
     * MONTH DATA — fills 30D tab with activity on days 7–29 ago
     * Adds longer-term records to show historical patterns
     */
    private static SeedResult buildMonthData() {
        Id     userId = UserInfo.getUserId();
        String orgUrl = System.Url.getOrgDomainUrl().toExternalForm();
        SeedResult r  = new SeedResult();

        // New Opps for month range
        List<Opportunity> monthOpps = new List<Opportunity>{
            new Opportunity(Name='Global Media Services Deal', StageName='Closed Won',
                CloseDate=Date.today().addDays(-10), Amount=410000),
            new Opportunity(Name='TechStart Seed Round', StageName='Prospecting',
                CloseDate=Date.today().addDays(90), Amount=50000),
            new Opportunity(Name='Alpine Manufacturing Suite', StageName='Negotiation',
                CloseDate=Date.today().addDays(7), Amount=275000),
            new Opportunity(Name='Coastal Logistics Upgrade', StageName='Proposal/Price Quote',
                CloseDate=Date.today().addDays(20), Amount=195000)
        };
        insert monthOpps;
        r.opps += monthOpps.size();

        Account acc2 = new Account(Name='Alpine Manufacturing');
        Account acc3 = new Account(Name='Coastal Logistics Group');
        insert new List<Account>{ acc2, acc3 };
        r.accounts += 2;

        List<Case> cases = new List<Case>{
            new Case(Subject='Dashboard Performance Slowdown', Status='Closed',
                Origin='Phone', Priority='Low'),
            new Case(Subject='Login SSO Failure', Status='Escalated',
                Origin='Web', Priority='High'),
            new Case(Subject='Report Timeout Issue', Status='In Progress',
                Origin='Email', Priority='Medium')
        };
        insert cases;
        r.cases += cases.size();

        List<Lead> leads = new List<Lead>{
            new Lead(FirstName='Michael', LastName='Wilson', Company='FinEdge Corp',
                LeadSource='Partner Referral', Status='Qualified'),
            new Lead(FirstName='Priya', LastName='Patel', Company='NovaTech Systems',
                LeadSource='Trade Show', Status='New'),
            new Lead(FirstName='David', LastName='Nguyen', Company='Pacific Retail Group',
                LeadSource='Web', Status='Working - Contacted')
        };
        insert leads;
        r.leads += leads.size();

        Task tk3 = new Task(Subject='Schedule demo with United Healthcare',
            ActivityDate=Date.today().addDays(-8), Status='Completed',
            Priority='High', OwnerId=userId, WhatId=monthOpps[0].Id);
        Task tk4 = new Task(Subject='Prepare Q2 forecast deck',
            ActivityDate=Date.today().addDays(-15), Status='Not Started',
            Priority='High', OwnerId=userId);
        Task tk5 = new Task(Subject='Review Pyramid contract draft',
            ActivityDate=Date.today().addDays(-20), Status='In Progress',
            Priority='Normal', OwnerId=userId, WhatId=monthOpps[2].Id);
        insert new List<Task>{ tk3, tk4, tk5 };
        r.tasks += 3;

        // ── Context records spread across days 7–29 ──
        List<User_Workspace_Context__c> ctx = new List<User_Workspace_Context__c>();

        // Days 7–10
        ctx.add(makeCtx(userId, monthOpps[0].Id, 'Opportunity', monthOpps[0].Name,
            'Edit', 'Closed Won', 410000, orgUrl, Date.today().addDays(-7), 16, 0, 60));
        ctx.add(makeCtx(userId, cases[0].Id, 'Case', cases[0].Subject,
            'View', 'Closed', null, orgUrl, Date.today().addDays(-7), 14, 30, 15));
        ctx.add(makeCtx(userId, acc2.Id, 'Account', acc2.Name,
            'View', null, null, orgUrl, Date.today().addDays(-8), 11, 0, 0));
        ctx.add(makeCtx(userId, monthOpps[2].Id, 'Opportunity', monthOpps[2].Name,
            'Edit', 'Negotiation', 275000, orgUrl, Date.today().addDays(-9), 15, 15, 60));
        ctx.add(makeCtx(userId, leads[0].Id, 'Lead', 'Michael Wilson',
            'Edit', null, null, orgUrl, Date.today().addDays(-10), 10, 0, 30));

        // Days 11–15
        ctx.add(makeCtx(userId, monthOpps[3].Id, 'Opportunity', monthOpps[3].Name,
            'View', 'Proposal/Price Quote', 195000, orgUrl, Date.today().addDays(-11), 14, 0, 30));
        ctx.add(makeCtx(userId, cases[1].Id, 'Case', cases[1].Subject,
            'Edit', 'Escalated', null, orgUrl, Date.today().addDays(-12), 9, 30, 45));
        ctx.add(makeCtx(userId, acc3.Id, 'Account', acc3.Name,
            'View', null, null, orgUrl, Date.today().addDays(-13), 16, 45, 0));
        ctx.add(makeCtx(userId, leads[1].Id, 'Lead', 'Priya Patel',
            'View', null, null, orgUrl, Date.today().addDays(-14), 11, 30, 0));
        ctx.add(makeCtx(userId, monthOpps[1].Id, 'Opportunity', monthOpps[1].Name,
            'Edit', 'Prospecting', 50000, orgUrl, Date.today().addDays(-15), 10, 0, 30));

        // Days 16–22
        ctx.add(makeCtx(userId, monthOpps[0].Id, 'Opportunity', monthOpps[0].Name,
            'View', 'Negotiation', 410000, orgUrl, Date.today().addDays(-16), 15, 0, 20));
        ctx.add(makeCtx(userId, cases[2].Id, 'Case', cases[2].Subject,
            'View', 'In Progress', null, orgUrl, Date.today().addDays(-17), 13, 0, 15));
        ctx.add(makeCtx(userId, leads[2].Id, 'Lead', 'David Nguyen',
            'Edit', null, null, orgUrl, Date.today().addDays(-18), 14, 15, 30));
        ctx.add(makeCtx(userId, monthOpps[2].Id, 'Opportunity', monthOpps[2].Name,
            'View', 'Proposal/Price Quote', 275000, orgUrl, Date.today().addDays(-20), 10, 45, 20));
        ctx.add(makeCtx(userId, acc2.Id, 'Account', acc2.Name,
            'Edit', null, null, orgUrl, Date.today().addDays(-22), 15, 30, 30));

        // Days 23–29
        ctx.add(makeCtx(userId, monthOpps[3].Id, 'Opportunity', monthOpps[3].Name,
            'Edit', 'Qualification', 195000, orgUrl, Date.today().addDays(-24), 11, 0, 30));
        ctx.add(makeCtx(userId, leads[0].Id, 'Lead', 'Michael Wilson',
            'View', null, null, orgUrl, Date.today().addDays(-25), 16, 0, 0));
        ctx.add(makeCtx(userId, monthOpps[1].Id, 'Opportunity', monthOpps[1].Name,
            'View', 'Prospecting', 50000, orgUrl, Date.today().addDays(-27), 9, 0, 20));
        ctx.add(makeCtx(userId, cases[1].Id, 'Case', cases[1].Subject,
            'View', 'New', null, orgUrl, Date.today().addDays(-28), 14, 0, 15));
        ctx.add(makeCtx(userId, acc3.Id, 'Account', acc3.Name,
            'Edit', null, null, orgUrl, Date.today().addDays(-29), 10, 30, 30));

        insert ctx;
        r.ctxRecords += ctx.size();
        return r;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static void resetContextOnly() {
        Id userId = UserInfo.getUserId();
        List<User_Workspace_Context__c> ctx = [
            SELECT Id FROM User_Workspace_Context__c WHERE User__c = :userId
        ];
        if (!ctx.isEmpty()) delete ctx;
    }

    private static User_Workspace_Context__c makeCtx(
        Id userId, Id recordId, String objType, String recName,
        String action, String stage, Decimal amount,
        String orgUrl, Date sessionDate, Integer hr, Integer min, Integer priority
    ) {
        return new User_Workspace_Context__c(
            User__c              = userId,
            Record_Id__c         = recordId,
            Object_Type__c       = objType,
            Record_Name__c       = recName,
            Action_Type__c       = action,
            Stage__c             = stage,
            Amount__c            = amount,
            Tab_URL__c           = orgUrl + '/lightning/r/' + objType + '/' + recordId + '/view',
            Session_Date__c      = sessionDate,
            Session_Timestamp__c = Datetime.newInstance(sessionDate,
                                       Time.newInstance(hr, min, 0, 0)),
            Is_Active_Session__c = true,
            Is_Dismissed__c      = false,
            Priority_Score__c    = priority
        );
    }

    // ── Inner result class ────────────────────────────────────────────────────
    private class SeedResult {
        Integer opps = 0, accounts = 0, cases = 0, contacts = 0,
                leads = 0, tasks = 0, ctxRecords = 0;

        void addFrom(SeedResult other) {
            opps       += other.opps;
            accounts   += other.accounts;
            cases      += other.cases;
            contacts   += other.contacts;
            leads      += other.leads;
            tasks      += other.tasks;
            ctxRecords += other.ctxRecords;
        }

        String summary() {
            return '✅ Seed complete!\n'
                + '  Opportunities : ' + opps       + '\n'
                + '  Accounts      : ' + accounts   + '\n'
                + '  Cases         : ' + cases      + '\n'
                + '  Contacts      : ' + contacts   + '\n'
                + '  Leads         : ' + leads      + '\n'
                + '  Tasks         : ' + tasks      + '\n'
                + '  Context Records: ' + ctxRecords + '\n'
                + '\nRefresh Workspace360 Dashboard to see results.';
        }
    }
}