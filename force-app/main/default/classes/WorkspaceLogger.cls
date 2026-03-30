public without sharing class WorkspaceLogger {

    // ── Inner classes ─────────────────────────────────────────────────────────

    public class WorkspaceEvent {
        @AuraEnabled public String  recordId   { get; set; }
        @AuraEnabled public String  objectType { get; set; }
        @AuraEnabled public String  recordName { get; set; }
        @AuraEnabled public String  actionType { get; set; }
        @AuraEnabled public String  tabUrl     { get; set; }
        @AuraEnabled public String  stage      { get; set; }
        @AuraEnabled public Decimal amount     { get; set; }
    }

    public class RecordCard {
        @AuraEnabled public String  id             { get; set; }
        @AuraEnabled public String  recordId       { get; set; }
        @AuraEnabled public String  recordName     { get; set; }
        @AuraEnabled public String  objectType     { get; set; }
        @AuraEnabled public String  actionType     { get; set; }
        @AuraEnabled public String  stage          { get; set; }
        @AuraEnabled public Decimal amount         { get; set; }
        @AuraEnabled public String  tabUrl         { get; set; }
        @AuraEnabled public String  sessionDate    { get; set; }
        @AuraEnabled public String  sessionTimestamp { get; set; }
        @AuraEnabled public Integer priorityScore  { get; set; }
        @AuraEnabled public Integer daysAgo        { get; set; }
    }

    public class PermissionInfo {
        @AuraEnabled public String  permSetName  { get; set; }
        @AuraEnabled public String  permSetLabel { get; set; }
        @AuraEnabled public String  objectName   { get; set; }
        @AuraEnabled public Boolean canRead      { get; set; }
        @AuraEnabled public Boolean canCreate    { get; set; }
        @AuraEnabled public Boolean canEdit      { get; set; }
        @AuraEnabled public Boolean canDelete    { get; set; }
    }

    // ── Logging ───────────────────────────────────────────────────────────────

    /**
     * logActivity — called by workspace360GlobalTracker for EVERY record visited.
     * Works for any SObject type; no hardcoded object list required.
     * 
     * Deduplication: if the same user+recordId already has a log entry for today,
     * we UPDATE it (refresh timestamp) instead of inserting a duplicate.
     */
    @AuraEnabled
    public static void logActivity(WorkspaceEvent evt) {
        if (evt == null || String.isBlank(evt.recordId)) return;

        try {
            String resolvedName = evt.recordName;

            // Dynamically resolve record name for any SObject
            if (String.isBlank(resolvedName) || resolvedName == evt.recordId) {
                resolvedName = resolveRecordName(evt.recordId, evt.objectType);
            }

            String tabUrlToStore = String.isNotBlank(evt.tabUrl) && evt.tabUrl.length() > 255
                ? evt.tabUrl.substring(0, 255) : evt.tabUrl;

            Id userId = UserInfo.getUserId();
            Date today = Date.today();

            // Check for existing entry for this user+record today
            List<User_Workspace_Context__c> existing = [
                SELECT Id, Session_Timestamp__c, Action_Type__c, Priority_Score__c
                FROM   User_Workspace_Context__c
                WHERE  User__c        = :userId
                AND    Record_Id__c   = :evt.recordId
                AND    Session_Date__c = :today
                LIMIT  1
            ];

            if (!existing.isEmpty()) {
                // Update: refresh timestamp, upgrade action if edit > view
                User_Workspace_Context__c upd = existing[0];
                upd.Session_Timestamp__c = Datetime.now();
                upd.Is_Active_Session__c = true;
                upd.Is_Dismissed__c      = false;
                if (evt.actionType == 'Edit') {
                    upd.Action_Type__c   = 'Edit';
                    upd.Priority_Score__c = calculatePriority(evt);
                }
                if (String.isNotBlank(resolvedName)) upd.Record_Name__c = resolvedName;
                if (String.isNotBlank(tabUrlToStore)) upd.Tab_URL__c    = tabUrlToStore;
                update upd;
            } else {
                // Insert new log entry
                User_Workspace_Context__c ctx = new User_Workspace_Context__c(
                    User__c               = userId,
                    Record_Id__c          = evt.recordId,
                    Object_Type__c        = evt.objectType,
                    Record_Name__c        = resolvedName,
                    Action_Type__c        = evt.actionType,
                    Tab_URL__c            = tabUrlToStore,
                    Stage__c              = evt.stage,
                    Amount__c             = evt.amount,
                    Session_Timestamp__c  = Datetime.now(),
                    Session_Date__c       = today,
                    Is_Active_Session__c  = true,
                    Is_Dismissed__c       = false,
                    Priority_Score__c     = calculatePriority(evt)
                );
                insert ctx;
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WorkspaceLogger.logActivity: ' + e.getMessage());
        }
    }

    /**
     * markSessionEnd — called when user closes tab / navigates away.
     * Does NOT delete records; they stay for session restore next login.
     */
    @AuraEnabled
    public static void markSessionEnd(String recordId) {
        // Nothing destructive — we intentionally keep Is_Active_Session__c = true
        // so tomorrow the restore banner can find them.
        // This method is a hook for future analytics (e.g. dwell time).
        System.debug('W360: session end signal for ' + recordId);
    }

    /**
     * dismissSession — called when user dismisses the restore banner.
     * Marks all records from that date as Is_Dismissed__c = true
     * so they won't show in the restore banner again.
     */
    @AuraEnabled
    public static void dismissSession(String sessionDate) {
        if (String.isBlank(sessionDate)) return;
        try {
            Date d = Date.valueOf(sessionDate);
            List<User_Workspace_Context__c> recs = [
                SELECT Id FROM User_Workspace_Context__c
                WHERE  User__c         = :UserInfo.getUserId()
                AND    Session_Date__c = :d
            ];
            for (User_Workspace_Context__c r : recs) {
                r.Is_Dismissed__c = true;
            }
            if (!recs.isEmpty()) update recs;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WorkspaceLogger.dismissSession: ' + e.getMessage());
        }
    }

    // ── Session Restore ───────────────────────────────────────────────────────

    /**
     * getLastSession — returns records from the user's LAST working day session
     * that have NOT been dismissed. Used by the "restore session" banner.
     *
     * Logic: find the most recent Session_Date__c before today that has
     * un-dismissed records, return those records ordered by priority.
     */
    @AuraEnabled(cacheable=false)
    public static List<RecordCard> getLastSession() {
        Id userId = UserInfo.getUserId();
        Date today = Date.today();

        // Find the most recent session date before today
        // Is_Dismissed__c intentionally excluded — dismissed records should
        // still be findable via agent/manual restore. The flag only controls
        // whether the auto-banner re-shows.
        List<User_Workspace_Context__c> dateFinder = [
            SELECT Session_Date__c
            FROM   User_Workspace_Context__c
            WHERE  User__c           = :userId
            AND    Session_Date__c   <= :today
            AND    Object_Type__c   != 'Dashboard'
            ORDER BY Session_Date__c DESC
            LIMIT  1
        ];

        if (dateFinder.isEmpty()) return new List<RecordCard>();

        Date lastDate = dateFinder[0].Session_Date__c;

        List<User_Workspace_Context__c> raw = [
            SELECT Id, Record_Id__c, Object_Type__c, Record_Name__c,
                   Action_Type__c, Tab_URL__c, Session_Date__c,
                   Session_Timestamp__c, Stage__c, Amount__c, Priority_Score__c
            FROM   User_Workspace_Context__c
            WHERE  User__c           = :userId
            AND    Session_Date__c   = :lastDate
            AND    Object_Type__c   != 'Dashboard'
            ORDER BY Session_Timestamp__c DESC, Priority_Score__c DESC
            LIMIT  25
        ];

        // Deduplicate by Record_Id__c
        Map<String, RecordCard> seen = new Map<String, RecordCard>();
        for (User_Workspace_Context__c r : raw) {
            String key = String.isBlank(r.Record_Id__c) ? r.Id : r.Record_Id__c;
            if (!seen.containsKey(key)) {
                RecordCard card = buildCard(r);
                seen.put(key, card);
            }
        }
        return seen.values();
    }

    // ── Recent records (1 / 7 / 30 days) ────────────────────────────────────

    /**
     * getRecentRecords — returns deduplicated records for the last N days.
     * Called by the dashboard when the user switches the 1d / 7d / 30d toggle.
     * days: accepted values are 1, 7, or 30. Defaults to 7 if out of range.
     */
    @AuraEnabled(cacheable=false)
    public static List<RecordCard> getRecentRecords(Integer days) {
        if (days == null || (days != 1 && days != 7 && days != 30)) days = 7;
        // cutoff = today minus N days. 1D = yesterday+today, 7D/30D as labeled.
        Date cutoff = Date.today().addDays(-days);
        List<User_Workspace_Context__c> raw = [
            SELECT Id, Record_Id__c, Object_Type__c, Record_Name__c,
                   Action_Type__c, Tab_URL__c, Session_Date__c,
                   Session_Timestamp__c, Stage__c, Amount__c, Priority_Score__c
            FROM   User_Workspace_Context__c
            WHERE  User__c          = :UserInfo.getUserId()
            AND    Session_Date__c  >= :cutoff
            AND    Object_Type__c   != 'Dashboard'
            ORDER BY Priority_Score__c DESC, Session_Timestamp__c DESC
            LIMIT  200
        ];

        Map<String, RecordCard> seen = new Map<String, RecordCard>();
        for (User_Workspace_Context__c r : raw) {
            String key = String.isBlank(r.Record_Id__c) ? r.Id : r.Record_Id__c;
            if (!seen.containsKey(key)) {
                seen.put(key, buildCard(r));
            }
        }
        return seen.values();
    }

    /**
     * getLast7DaysRecords — kept for backwards compatibility.
     */
    @AuraEnabled(cacheable=true)
    public static List<RecordCard> getLast7DaysRecords() {
        return getRecentRecords(7);
    }

    // ── Yesterday context (kept for AI summary) ───────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<User_Workspace_Context__c> getYesterdayContext() {
        Date yesterday = Date.today().addDays(-1);
        return [
            SELECT Id, Record_Id__c, Object_Type__c, Record_Name__c,
                   Action_Type__c, Tab_URL__c, Session_Timestamp__c,
                   Stage__c, Amount__c, Priority_Score__c
            FROM   User_Workspace_Context__c
            WHERE  User__c           = :UserInfo.getUserId()
            AND    Session_Date__c   = :yesterday
            AND    Is_Active_Session__c = true
            ORDER BY Priority_Score__c DESC, Session_Timestamp__c DESC
            LIMIT  50
        ];
    }

    // ── Permissions ───────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<PermissionInfo> getUserPermissions() {
        Id userId = UserInfo.getUserId();
        List<PermissionInfo> results = new List<PermissionInfo>();

        List<PermissionSetAssignment> assignments = [
            SELECT PermissionSet.Name, PermissionSet.Label, PermissionSet.IsOwnedByProfile
            FROM   PermissionSetAssignment
            WHERE  AssigneeId = :userId
            ORDER BY PermissionSet.Label
        ];

        Set<Id> permSetIds = new Set<Id>();
        Map<Id, String[]> permSetMeta = new Map<Id, String[]>();
        for (PermissionSetAssignment psa : assignments) {
            String psName  = psa.PermissionSet.Name;
            String psLabel = psa.PermissionSet.Label;
            // Skip system-generated permission sets with no readable label
            if (String.isBlank(psLabel)) continue;
            if (psName  != null && psName.startsWith('00'))  continue;
            if (psLabel != null && psLabel.startsWith('00')) continue;
            permSetIds.add(psa.PermissionSetId);
            permSetMeta.put(psa.PermissionSetId, new String[]{
                psName,
                psLabel,
                psa.PermissionSet.IsOwnedByProfile ? 'Profile' : 'Permission Set'
            });
        }

        List<ObjectPermissions> objPerms = [
            SELECT ParentId, SObjectType,
                   PermissionsRead, PermissionsCreate,
                   PermissionsEdit, PermissionsDelete
            FROM   ObjectPermissions
            WHERE  ParentId IN :permSetIds
            ORDER BY SObjectType
        ];

        for (ObjectPermissions op : objPerms) {
            String[] meta = permSetMeta.get(op.ParentId);
            if (meta == null) continue;
            PermissionInfo pi = new PermissionInfo();
            pi.permSetName  = meta[0];
            pi.permSetLabel = meta[1];
            pi.objectName   = op.SObjectType;
            pi.canRead      = op.PermissionsRead;
            pi.canCreate    = op.PermissionsCreate;
            pi.canEdit      = op.PermissionsEdit;
            pi.canDelete    = op.PermissionsDelete;
            results.add(pi);
        }
        return results;
    }

    // ── Standard queries ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<ProcessInstanceWorkitem> getPendingApprovals() {
        return [
            SELECT Id, ProcessInstance.TargetObjectId,
                   ProcessInstance.TargetObject.Name,
                   ProcessInstance.Status, CreatedDate
            FROM   ProcessInstanceWorkitem
            WHERE  ActorId = :UserInfo.getUserId()
            LIMIT  20
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Task> getOverdueTasks() {
        return [
            SELECT Id, Subject, WhatId, What.Name, ActivityDate, Priority, Status
            FROM   Task
            WHERE  OwnerId    = :UserInfo.getUserId()
            AND    IsClosed   = false
            AND    ActivityDate < TODAY
            ORDER BY ActivityDate ASC
            LIMIT  20
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Opportunity> getInProgressOpportunities() {
        return [
            SELECT Id, Name, StageName, Amount, CloseDate,
                   Account.Name, LastModifiedDate
            FROM   Opportunity
            WHERE  OwnerId   = :UserInfo.getUserId()
            AND    IsClosed  = false
            ORDER BY LastModifiedDate DESC
            LIMIT  10
        ];
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static RecordCard buildCard(User_Workspace_Context__c r) {
        RecordCard card = new RecordCard();
        card.id               = r.Id;
        card.recordId         = r.Record_Id__c;
        card.recordName       = r.Record_Name__c;
        card.objectType       = r.Object_Type__c;
        card.actionType       = r.Action_Type__c;
        card.stage            = r.Stage__c;
        card.amount           = r.Amount__c;
        card.tabUrl           = r.Tab_URL__c;
        card.sessionDate      = r.Session_Date__c != null ? String.valueOf(r.Session_Date__c) : '';
        card.sessionTimestamp = r.Session_Timestamp__c != null
            ? r.Session_Timestamp__c.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : '';
        card.priorityScore    = r.Priority_Score__c != null ? Integer.valueOf(r.Priority_Score__c) : 0;
        card.daysAgo          = r.Session_Date__c != null
            ? Date.today().daysBetween(r.Session_Date__c) * -1 : 0;
        return card;
    }

    /**
     * Dynamically query record name for ANY SObject type.
     * Falls back gracefully for objects without Name/Subject.
     */
    private static String resolveRecordName(String recordId, String objectType) {
        if (String.isBlank(recordId) || String.isBlank(objectType)) return null;
        try {
            // Determine name field
            String nameField = 'Name';
            if (objectType == 'Case' || objectType == 'Task' || objectType == 'EmailMessage') {
                nameField = 'Subject';
            }
            String q = 'SELECT ' + nameField + ' FROM ' + objectType
                     + ' WHERE Id = \'' + String.escapeSingleQuotes(recordId) + '\' LIMIT 1';
            List<SObject> rows = Database.query(q);
            if (!rows.isEmpty()) {
                Object val = rows[0].get(nameField);
                return val != null ? String.valueOf(val) : null;
            }
        } catch (Exception e) {
            // Object may not have Name/Subject — try Id as fallback label
            System.debug('W360: name resolve failed for ' + objectType + ' - ' + e.getMessage());
        }
        return null;
    }

    // ── Developer Activity ────────────────────────────────────────────────────
    // Returns raw SetupAuditTrail entries for client-side consolidation.
    // JS consolidates by Action Category + Date.

    public class DevActivityRaw {
        @AuraEnabled public String Action      { get; set; }
        @AuraEnabled public String Section     { get; set; }
        @AuraEnabled public String Display     { get; set; }
        @AuraEnabled public String CreatedDate { get; set; }
        @AuraEnabled public String ChangedBy   { get; set; }  // full name of the sysadmin who made the change
    }

    public class DevActivityItem {
        @AuraEnabled public String  id           { get; set; }
        @AuraEnabled public String  action       { get; set; }
        @AuraEnabled public String  section      { get; set; }
        @AuraEnabled public String  component    { get; set; }  // cleaned component name
        @AuraEnabled public String  detail       { get; set; }  // raw display text
        @AuraEnabled public String  changedBy    { get; set; }
        @AuraEnabled public String  lastModified { get; set; }  // most recent change time
        @AuraEnabled public String  daysAgoLabel { get; set; }
        @AuraEnabled public String  typeIcon     { get; set; }
        @AuraEnabled public String  typeBadge    { get; set; }
        @AuraEnabled public Integer changeCount  { get; set; }  // how many times edited
        @AuraEnabled public String  countLabel   { get; set; }  // "3 changes" or ""
    }

    /**
     * getDevActivity — filtered overload used by the dashboard UI.
     * Hides Workspace360 internal components so they don't clutter the Dev Activity tab.
     * All existing callers (LWC, Agentforce action) continue to call this signature unchanged.
     */
    @AuraEnabled(cacheable=false)
    public static List<DevActivityRaw> getDevActivity(Integer days) {
        return getDevActivity(days, true);
    }

    /**
     * getDevActivity — full overload (internal Apex-to-Apex only, not exposed to LWC).
     * @param days        Number of days to look back.
     * @param filterW360  true  = hide Workspace360 internals (dashboard UI default).
     *                    false = include all components, including W360 internals
     *                            (needed for incident RCA where a W360 deploy could
     *                            itself be the root cause of a production error).
     * NOTE: @AuraEnabled is intentionally absent — Salesforce forbids overloading
     * @AuraEnabled methods. This overload is called only from Apex (never from LWC).
     */
    public static List<DevActivityRaw> getDevActivity(Integer days, Boolean filterW360) {
        if (days == null || days < 1) days = 7;
        if (filterW360 == null) filterW360 = true;
        Datetime cutoff = Datetime.now().addDays(-days);

        Set<String> devSections = new Set<String>{
            'Apex Class', 'Apex Classes', 'Apex Trigger', 'Apex Triggers',
            'Lightning Component', 'Aura Component', 'Lightning Web Component',
            'Lightning Page', 'Lightning Pages', 'Flow', 'Process Builder',
            'Custom Object', 'Custom Objects', 'Custom Field', 'Custom Object Definition',
            'Validation Rule', 'Workflow Rule',
            'Profile', 'Permission Set',
            'Change Set', 'Package', 'Installed Package',
            'Custom App', 'Tab', 'Named Credential', 'Remote Site',
            'Static Resource', 'Custom Label', 'Custom Metadata'
        };

        // Query org-wide — all sysadmins on the team see the same shared activity feed.
        // Filtering to the current user would miss changes deployed by teammates or
        // a CI/CD service user (Copado, Gearset, etc).
        List<SetupAuditTrail> trails = [
            SELECT Id, Action, Section, Display, CreatedBy.Name, CreatedDate
            FROM   SetupAuditTrail
            WHERE  CreatedDate >= :cutoff
            ORDER BY CreatedDate DESC
            LIMIT  500
        ];

        // Deduplicate by component name + section — keep only the most recent entry per component
        // This prevents the same Apex class appearing multiple times from repeated deploys
        Map<String, DevActivityRaw> seen = new Map<String, DevActivityRaw>();
        for (SetupAuditTrail t : trails) {
            Boolean relevant = false;
            for (String s : devSections) {
                if (t.Section != null && t.Section.containsIgnoreCase(s)) { relevant = true; break; }
            }
            if (!relevant) continue;

            String componentName = extractComponentName(t.Display, t.Section);

            // Skip test classes — never a root cause of production errors
            if (t.Section != null && t.Section.containsIgnoreCase('Apex Class')
                && componentName.endsWithIgnoreCase('Test')) continue;

            // Skip Workspace360 project internals when running in dashboard (UI) mode.
            // These are app infrastructure, not customer changes, and would clutter the feed.
            // When filterW360=false (incident RCA mode), we include them — a W360 deploy
            // could itself be the root cause of a production error.
            if (filterW360 == true) {
                if (componentName.startsWithIgnoreCase('W360')
                    || componentName.startsWithIgnoreCase('Workspace360')
                    || componentName.startsWithIgnoreCase('workspace360')
                    || componentName.containsIgnoreCase('W360 Incident')
                    || componentName.containsIgnoreCase('User Workspace Context')
                    || componentName.equalsIgnoreCase('AgentforceSummary')
                    || componentName.equalsIgnoreCase('WorkspaceLogger')
                    || componentName.equalsIgnoreCase('W360LiveDemoSeeder')
                    || componentName.equalsIgnoreCase('Workspace360IncidentSeeder')
                    || componentName.equalsIgnoreCase('Workspace360DemoSeeder')
                    || componentName.equalsIgnoreCase('Workspace360BackgroundTrackerController')) continue;
            }

            // Dedup key: component name + section type
            String dedupeKey = componentName + '||' + (t.Section != null ? t.Section : '');

            // Trails are ORDER BY CreatedDate DESC so first occurrence = most recent
            if (!seen.containsKey(dedupeKey)) {
                DevActivityRaw item = new DevActivityRaw();
                item.Action      = t.Action;
                item.Section     = t.Section;
                item.Display     = t.Display;
                item.CreatedDate = t.CreatedDate != null ? t.CreatedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'') : null;
                item.ChangedBy   = t.CreatedBy != null ? t.CreatedBy.Name : 'Unknown';
                seen.put(dedupeKey, item);
            }
        }
        return seen.values();
    }

    // "Created My_Field__c on Account"                   → "My_Field__c on Account"
    private static String extractComponentName(String display, String section) {
        if (String.isBlank(display)) return '(unknown)';

        String d = display.trim();
        String sec = section != null ? section.toLowerCase() : '';

        // Pattern: "Changed|Created|Deleted <Name> <Section>" — strip verb and trailing section
        List<String> verbs = new List<String>{'Changed ','Created ','Deleted ','Deployed ','Installed ','Activated ','Deactivated '};
        for (String v : verbs) {
            if (d.startsWithIgnoreCase(v)) {
                d = d.substring(v.length()).trim();
                break;
            }
        }

        // Strip trailing section label if it ends with it
        // e.g. "WorkspaceLogger Apex Class code" → strip " Apex Class code"
        List<String> suffixes = new List<String>{
            ' Apex Class code', ' Apex Class', ' Lightning Web Component',
            ' Lightning Component', ' Aura Component', ' Flow', ' Custom Object',
            ' Custom Field', ' Validation Rule', ' Workflow Rule', ' Profile',
            ' Permission Set', ' Static Resource', ' Custom Label', ' Custom Metadata',
            ' code'
        };
        for (String suf : suffixes) {
            if (d.endsWithIgnoreCase(suf)) {
                d = d.substring(0, d.length() - suf.length()).trim();
                break;
            }
        }

        return String.isBlank(d) ? display : d;
    }

    /**
     * isSysAdmin — returns true if the running user has the System Administrator profile.
     * Used by the dashboard to show/hide dev-only tabs (Dev Activity, Permissions, Incidents).
     */
    /**
     * isDevUser — returns true if the running user has the System Administrator profile
     * OR is assigned the Workspace360_DevAccess permission set.
     * This controls visibility of Dev Activity and Incidents tabs.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isSysAdmin() {
        // True ONLY for System Administrator profile — gets dev-only view (no sales tabs)
        User u = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return u.Profile.Name == 'System Administrator';
    }

    @AuraEnabled(cacheable=true)
    public static Boolean hasDevAccess() {
        // True if user has Workspace360_DevAccess permission set
        // These users get sales tabs PLUS Dev Activity + Incidents tabs
        Id userId = UserInfo.getUserId();
        List<PermissionSetAssignment> psa = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            AND   PermissionSet.Name = 'Workspace360_DevAccess'
            LIMIT 1
        ];
        return !psa.isEmpty();
    }

    private static Integer calculatePriority(WorkspaceEvent evt) {
        Integer score = 0;
        if (evt.actionType == 'Edit')    score += 30;
        if (evt.actionType == 'Create')  score += 25;
        if (evt.actionType == 'Approve') score += 40;
        if (evt.objectType == 'Opportunity') score += 20;
        if (evt.objectType == 'Case')        score += 15;
        if (evt.objectType != null && evt.objectType.endsWith('__c')) score += 10;
        if (evt.amount != null && evt.amount > 100000) score += 10;
        return score;
    }
}