public class W360TestDataSeeder {

    public static void seed() {
        Id uid = '005aj00000Tci0y';
        String url = System.Url.getOrgDomainUrl().toExternalForm();
        Date t = Date.today();

        // Clean existing context records for this user
        delete [SELECT Id FROM User_Workspace_Context__c WHERE User__c = :uid];

        // ── Leads ──────────────────────────────────────────────────────────────
        List<Lead> leads = new List<Lead>{
            new Lead(FirstName='Jordan', LastName='Lee', Company='TechFit Solutions',
                     Status='Open - Not Contacted', OwnerId=uid),
            new Lead(FirstName='Maria', LastName='Santos', Company='Blue Ridge Capital',
                     Status='Working - Contacted', OwnerId=uid),
            new Lead(FirstName='Kevin', LastName='Oduya', Company='NovaBridge Inc',
                     Status='Open - Not Contacted', OwnerId=uid)
        };
        insert leads;

        // ── Opportunities ──────────────────────────────────────────────────────
        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(Name='TechFit - Enterprise Expansion', StageName='Proposal/Price Quote',
                            CloseDate=t.addDays(30), Amount=85000, OwnerId=uid),
            new Opportunity(Name='Blue Ridge - Q2 Renewal', StageName='Negotiation/Review',
                            CloseDate=t.addDays(15), Amount=42000, OwnerId=uid),
            new Opportunity(Name='NovaBridge - Platform Deal', StageName='Value Proposition',
                            CloseDate=t.addDays(45), Amount=120000, OwnerId=uid)
        };
        insert opps;

        // ── NewObject__c ───────────────────────────────────────────────────────
        List<NewObject__c> newObjs = new List<NewObject__c>{
            new NewObject__c(Name='Custom Record Alpha'),
            new NewObject__c(Name='Custom Record Beta'),
            new NewObject__c(Name='Custom Record Gamma')
        };
        insert newObjs;

        // ── Context records ────────────────────────────────────────────────────
        List<User_Workspace_Context__c> cx = new List<User_Workspace_Context__c>();

        // TODAY — Lead + Opp + NewObject (shows in 1D, 7D, 30D)
        cx.add(mkCtx(uid, leads[0].Id,   'Lead',        'Jordan Lee',                  'Edit', null,    0,    url, t,          14, 30, 80));
        cx.add(mkCtx(uid, opps[0].Id,    'Opportunity', 'TechFit - Enterprise Expansion','Edit','Proposal/Price Quote', 85000, url, t, 15, 0,  85));
        cx.add(mkCtx(uid, newObjs[0].Id, 'NewObject__c','Custom Record Alpha',          'View', null,    0,    url, t,          16, 0,  55));

        // YESTERDAY — Lead + Opp (shows in 1D, 7D, 30D)
        cx.add(mkCtx(uid, leads[1].Id,   'Lead',        'Maria Santos',                 'View', null,    0,    url, t.addDays(-1), 10, 0,  60));
        cx.add(mkCtx(uid, opps[1].Id,    'Opportunity', 'Blue Ridge - Q2 Renewal',      'Edit','Negotiation/Review', 42000, url, t.addDays(-1), 11, 30, 78));

        // 3 DAYS AGO — NewObject + Lead (shows in 7D, 30D)
        cx.add(mkCtx(uid, newObjs[1].Id, 'NewObject__c','Custom Record Beta',           'Edit', null,    0,    url, t.addDays(-3), 9,  15, 65));
        cx.add(mkCtx(uid, leads[2].Id,   'Lead',        'Kevin Oduya',                  'View', null,    0,    url, t.addDays(-3), 14, 0,  50));

        // 5 DAYS AGO — Opp (shows in 7D, 30D)
        cx.add(mkCtx(uid, opps[2].Id,    'Opportunity', 'NovaBridge - Platform Deal',   'View','Value Proposition', 120000, url, t.addDays(-5), 16, 45, 70));

        // 6 DAYS AGO — NewObject (shows in 7D, 30D)
        cx.add(mkCtx(uid, newObjs[2].Id, 'NewObject__c','Custom Record Gamma',          'Edit', null,    0,    url, t.addDays(-6), 13, 0,  60));

        // 12 DAYS AGO — Lead + Opp (shows in 30D only)
        cx.add(mkCtx(uid, leads[0].Id,   'Lead',        'Jordan Lee',                   'View', null,    0,    url, t.addDays(-12), 11, 0,  40));
        cx.add(mkCtx(uid, opps[0].Id,    'Opportunity', 'TechFit - Enterprise Expansion','View','Proposal/Price Quote', 85000, url, t.addDays(-12), 15, 30, 45));

        // 20 DAYS AGO — NewObject + Lead (shows in 30D only)
        cx.add(mkCtx(uid, newObjs[0].Id, 'NewObject__c','Custom Record Alpha',          'View', null,    0,    url, t.addDays(-20), 10, 0,  30));
        cx.add(mkCtx(uid, leads[1].Id,   'Lead',        'Maria Santos',                 'Edit', null,    0,    url, t.addDays(-20), 14, 0,  48));

        // 26 DAYS AGO — Opp (shows in 30D only)
        cx.add(mkCtx(uid, opps[1].Id,    'Opportunity', 'Blue Ridge - Q2 Renewal',      'Edit','Negotiation/Review', 42000, url, t.addDays(-26), 9, 0, 42));

        insert cx;
        System.debug('W360TestDataSeeder: inserted ' + cx.size() + ' context records');
        System.debug('  Leads: ' + leads.size() + ', Opps: ' + opps.size() + ', NewObject__c: ' + newObjs.size());
        System.debug('  1D (Yesterday & Today): 5 records');
        System.debug('  7D: 9 records');
        System.debug('  30D: 13 records');
    }

    private static User_Workspace_Context__c mkCtx(
        Id uid, Id recId, String objType, String recName,
        String action, String stage, Decimal amount,
        String url, Date d, Integer hr, Integer mn, Integer priority
    ) {
        return new User_Workspace_Context__c(
            User__c              = uid,
            Record_Id__c         = recId,
            Object_Type__c       = objType,
            Record_Name__c       = recName,
            Action_Type__c       = action,
            Stage__c             = stage,
            Amount__c            = (amount > 0 ? amount : null),
            Tab_URL__c           = url + '/lightning/r/' + objType + '/' + recId + '/view',
            Session_Date__c      = d,
            Session_Timestamp__c = Datetime.newInstance(d, Time.newInstance(hr, mn, 0, 0)),
            Is_Active_Session__c = true,
            Is_Dismissed__c      = false,
            Priority_Score__c    = priority
        );
    }
}