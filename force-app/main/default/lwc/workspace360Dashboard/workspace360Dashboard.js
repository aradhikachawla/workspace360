import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin }               from 'lightning/navigation';
import { ShowToastEvent }                from 'lightning/platformShowToastEvent';
//Aradhika
import getYesterdayContext        from '@salesforce/apex/WorkspaceLogger.getYesterdayContext';
import getLast7DaysRecords        from '@salesforce/apex/WorkspaceLogger.getLast7DaysRecords';
import getPendingApprovals        from '@salesforce/apex/WorkspaceLogger.getPendingApprovals';
import getOverdueTasks            from '@salesforce/apex/WorkspaceLogger.getOverdueTasks';
import getInProgressOpportunities from '@salesforce/apex/WorkspaceLogger.getInProgressOpportunities';
import getUserPermissions         from '@salesforce/apex/WorkspaceLogger.getUserPermissions';
import getDevActivity             from '@salesforce/apex/WorkspaceLogger.getDevActivity';
import logActivity                from '@salesforce/apex/WorkspaceLogger.logActivity';
import generateSummary            from '@salesforce/apex/AgentforceSummary.generateSummary';
import generateDevSummary         from '@salesforce/apex/AgentforceSummary.generateDevSummary';
import getRecentErrors            from '@salesforce/apex/W360IncidentAnalyzer.getRecentErrors';
import getRecentRecords           from '@salesforce/apex/WorkspaceLogger.getRecentRecords';
import checkIsSysAdmin            from '@salesforce/apex/WorkspaceLogger.isSysAdmin';
import checkHasDevAccess          from '@salesforce/apex/WorkspaceLogger.hasDevAccess';
import getLastSession             from '@salesforce/apex/WorkspaceLogger.getLastSession';
import dismissSession             from '@salesforce/apex/WorkspaceLogger.dismissSession';
import getCorrelatedChanges       from '@salesforce/apex/W360IncidentAnalyzer.getCorrelatedChanges';
import analyzeIncident            from '@salesforce/apex/W360IncidentAnalyzer.analyzeIncident';

import USER_ID    from '@salesforce/user/Id';
import FIRST_NAME from '@salesforce/schema/User.FirstName';
import { getRecord } from 'lightning/uiRecordApi';

const STAGE_PROGRESS = {
    'Prospecting': 10, 'Qualification': 25, 'Needs Analysis': 35,
    'Value Proposition': 45, 'Id. Decision Makers': 55,
    'Perception Analysis': 60, 'Proposal/Price Quote': 70,
    'Negotiation/Review': 80, 'Negotiation': 80,
    'Closed Won': 100, 'Closed Lost': 100
};

const OBJECT_ICON_MAP = {
    Opportunity  : 'standard:opportunity',
    Case         : 'standard:case',
    Account      : 'standard:account',
    Contact      : 'standard:contact',
    Lead         : 'standard:lead',
    Task         : 'standard:task',
    Dashboard    : 'standard:dashboard',
    NewObject__c : 'standard:custom',
};

export default class Workspace360Dashboard extends NavigationMixin(LightningElement) {

    @track isLoading        = true;
    @track isSummaryLoading = true;
    @track isPermsLoading   = false;
    @track activeTab        = 'recent';
    @track aiSummary        = '';
    @track activePermSet    = 'ALL';

    @track recentRecords    = [];
    @track pendingApprovals = [];
    @track overdueTasks     = [];
    @track opportunities    = [];
    @track permissions      = [];
    // Add to properties:
   @track activeFilter = '7D';
    @track _isSysAdmin = false;
    @track _hasDevAccess = false;
    _yesterdayContext = [];
    _profileResolved = false;



    userId = USER_ID;

    @wire(getRecord, { recordId: '$userId', fields: [FIRST_NAME] })
    wiredUser({ data }) { if (data) this._firstName = data.fields.FirstName.value; }

    get firstName()    { return this._firstName || 'there'; }
    get greetingTime() {
        const h = new Date().getHours();
        return h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening';
    }
    get todayLabel() {
        return new Date().toLocaleDateString('en-US',
            { weekday:'long', month:'long', day:'numeric' });
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    connectedCallback() {
        this.loadAllData();
        this._logDashboardVisit();
        checkIsSysAdmin().then(result => {
            this._isSysAdmin = result;
            this._profileResolved = true;
            if (result) {
                this.activeTab = 'incidents';
                this.loadIncidents();
                this._loadDevSummary();
            } else {
                // Profile resolved as non-sysadmin — load sales summary now
                this._loadAISummary(this._yesterdayContext);
            }
        }).catch(() => {
            this._isSysAdmin = false;
            this._profileResolved = true;
            this._loadAISummary(this._yesterdayContext);
        });
        checkHasDevAccess().then(result => { this._hasDevAccess = result; }).catch(() => { this._hasDevAccess = false; });
    }

    async loadAllData() {
        this.isLoading = true;
        try {
            const [recent, approvals, tasks, opps, yesterday] = await Promise.all([
                getLast7DaysRecords(),
                getPendingApprovals(),
                getOverdueTasks(),
                getInProgressOpportunities(),
                getYesterdayContext(),
            ]);
            this.recentRecords    = this._enrichRecentRecords(recent);
            this.pendingApprovals = this._enrichApprovals(approvals);
            this.overdueTasks     = this._enrichTasks(tasks);
            this.opportunities    = this._enrichOpps(opps);
            // Store context but don't load summary yet —
            // wait for isSysAdmin check to decide which summary to show
            this._yesterdayContext = yesterday;
            if (this._profileResolved) {
                this._isSysAdmin ? this._loadDevSummary() : this._loadAISummary(yesterday);
            }
        } catch(e) {
            console.error('Workspace360 load error', e);
        } finally {
            this.isLoading = false;
        }
    }

    // Add getters:
get activeFilterLabel() {
    return this.activeFilter === '1D' ? 'Yesterday & Today' 
         : this.activeFilter === '30D' ? 'Last 30 Days' 
         : 'Last 7 Days';
}
get filteredRecentRecords() {
    return this.recentRecords;
}
get filterClass1D()  { return this.activeFilter === '1D'  ? 'w360-filter-btn w360-filter-active' : 'w360-filter-btn'; }
get filterClass7D()  { return this.activeFilter === '7D'  ? 'w360-filter-btn w360-filter-active' : 'w360-filter-btn'; }
get filterClass30D() { return this.activeFilter === '30D' ? 'w360-filter-btn w360-filter-active' : 'w360-filter-btn'; }

get hasFilteredRecentRecords() { 
    return this.filteredRecentRecords.length > 0; 
}
// Add handlers:
setFilter1D()  { this.activeFilter = '1D';  if (this._isSysAdmin) { this._incidentsLoading = false; this.loadIncidents(); } else { this._loadFilteredRecords(1); } }
setFilter7D()  { this.activeFilter = '7D';  if (this._isSysAdmin) { this._incidentsLoading = false; this.loadIncidents(); } else { this._loadFilteredRecords(7); } }
setFilter30D() { this.activeFilter = '30D'; if (this._isSysAdmin) { this._incidentsLoading = false; this.loadIncidents(); } else { this._loadFilteredRecords(30); } }

_loadFilteredRecords(days) {
    this.isLoading = true;
    getRecentRecords({ days })
        .then(data => { this.recentRecords = this._enrichRecentRecords(data); })
        .catch(e  => { console.error('Filter load error', e); })
        .finally(() => { this.isLoading = false; });
}

    async _loadAISummary(ctx) {
        this.isSummaryLoading = true;
        try {
            this.aiSummary = await generateSummary({ contextRecords: ctx });
        } catch {
            this.aiSummary = 'Ready to pick up where you left off? Your recent activity is shown below.';
        } finally {
            this.isSummaryLoading = false;
        }
    }

    async _loadDevSummary() {
        this.isSummaryLoading = true;
        try {
            this.aiSummary = await generateDevSummary();
        } catch {
            this.aiSummary = 'Check the Incidents tab for the latest production health status.';
        } finally {
            this.isSummaryLoading = false;
        }
    }

    async loadPermissions() {
        if (this.permissions.length > 0) return;
        this.isPermsLoading = true;
        try {
            const raw = await getUserPermissions();
            this.permissions = this._enrichPermissions(raw);
        } catch(e) {
            console.error('Perms load error', e);
        } finally {
            this.isPermsLoading = false;
        }
    }

    // ── Tabs ──────────────────────────────────────────────────────────────────
    get isSysAdmin()         { return this._isSysAdmin; }
    get isNotSysAdmin()      { return !this._isSysAdmin; }
    get hasDevAccess()       { return this._hasDevAccess; }
    get activeTabRecent()    { return this.activeTab === 'recent'; }
    get activeTabOpps()      { return this.activeTab === 'opps'; }
    get activeTabTasks()     { return this.activeTab === 'tasks'; }
    get activeTabApprovals() { return this.activeTab === 'approvals'; }
    get activeTabPerms()     { return this.activeTab === 'perms'; }
    get activeTabDev()       { return this.activeTab === 'dev'; }
    get tabClassDev()        { return this._tab('dev'); }
    showTabDev()             { if (!this._isSysAdmin && !this._hasDevAccess) return; this.activeTab = 'dev'; this.loadDevActivity(); }

    @track _devActivityRaw   = [];
    @track _devLoading       = false;

    get hasDevActivity()     { return this.groupedDevActivity.length > 0; }

    loadDevActivity() {
        if (this._devLoading) return;
        this._devLoading = true;
        getDevActivity({ days: 7 })
            .then(data => { this._devActivityRaw = data || []; })
            .catch(err => { console.error('Dev Activity error:', err); this._devActivityRaw = []; })
            .finally(() => { this._devLoading = false; });
    }

    // Extract the component/artifact name from the Display text
    // e.g. "Changed WorkspaceLogger Apex Class code" → "WorkspaceLogger"
    // e.g. "Created My_Field__c on Account Custom Field" → "My_Field__c on Account"
    _extractName(display) {
        if (!display) return '(unknown)';
        let d = display.trim();
        // Strip leading verb
        const verbs = ['Changed ','Created ','Deleted ','Deployed ','Installed ','Activated ','Deactivated ','Saved '];
        for (const v of verbs) {
            if (d.toLowerCase().startsWith(v.toLowerCase())) { d = d.slice(v.length).trim(); break; }
        }
        // Strip trailing section/type label
        const suffixes = [
            ' Apex Class code',' Apex Class',' Apex Trigger',
            ' Lightning Web Component',' Lightning Component',' Aura Component',
            ' Lightning Page',' Flow Definition',' Flow',
            ' Custom Object Definition',' Custom Object',' Custom Field',
            ' Validation Rule',' Workflow Rule',
            ' Permission Set',' Profile',
            ' Static Resource',' Custom Label',' Custom Metadata',
            ' Named Credential',' Remote Site Setting',
            ' code'
        ];
        for (const s of suffixes) {
            if (d.toLowerCase().endsWith(s.toLowerCase())) { d = d.slice(0, d.length - s.length).trim(); break; }
        }
        return d || display;
    }

    _typeFromSection(section) {
        const s = (section || '').toLowerCase();
        if (s.includes('apex class'))   return { badge: 'Apex', icon: 'standard:apex' };
        if (s.includes('apex trigger')) return { badge: 'Trigger', icon: 'standard:apex' };
        if (s.includes('lwc') || s.includes('lightning web')) return { badge: 'LWC', icon: 'standard:lightning_component' };
        if (s.includes('lightning component') || s.includes('aura')) return { badge: 'Aura', icon: 'standard:lightning_component' };
        if (s.includes('lightning page'))  return { badge: 'Page', icon: 'standard:page_layout' };
        if (s.includes('flow'))            return { badge: 'Flow', icon: 'standard:flow' };
        if (s.includes('custom field'))    return { badge: 'Field', icon: 'standard:formula' };
        if (s.includes('custom object'))   return { badge: 'Object', icon: 'standard:custom_object' };
        if (s.includes('validation'))      return { badge: 'Rule', icon: 'standard:validation_rule' };
        if (s.includes('workflow'))        return { badge: 'Workflow', icon: 'standard:workflow' };
        if (s.includes('permission set'))  return { badge: 'PermSet', icon: 'standard:permission_set' };
        if (s.includes('profile'))         return { badge: 'Profile', icon: 'standard:user' };
        if (s.includes('static resource')) return { badge: 'Resource', icon: 'standard:file' };
        if (s.includes('named credential')) return { badge: 'Credential', icon: 'standard:connected_apps' };
        if (s.includes('custom label'))    return { badge: 'Label', icon: 'utility:label' };
        if (s.includes('custom metadata')) return { badge: 'CMDT', icon: 'standard:custom_notification' };
        return { badge: 'Config', icon: 'utility:settings' };
    }

    get groupedDevActivity() {
        // Group by unique component name — one card per artifact, regardless of how many times edited
        const seen = {};
        for (const r of this._devActivityRaw) {
            const name = this._extractName(r.Display);
            const type = this._typeFromSection(r.Section);
            // Key = name + section so "WorkspaceLogger (Apex)" and "WorkspaceLogger (LWC)" stay separate
            const key  = name + '||' + r.Section;
            if (!seen[key]) {
                const date = r.CreatedDate ? r.CreatedDate.substring(0, 10) : '';
                seen[key] = { id: key, name, section: r.Section, icon: type.icon, badge: type.badge, count: 0, lastDate: date };
            }
            seen[key].count++;
            // Keep most recent date
            const d = r.CreatedDate ? r.CreatedDate.substring(0, 10) : '';
            if (d > seen[key].lastDate) seen[key].lastDate = d;
        }

        return Object.values(seen)
            .sort((a, b) => b.lastDate.localeCompare(a.lastDate) || a.name.localeCompare(b.name))
            .map(g => ({
                id         : g.id,
                label      : g.name,
                icon       : g.icon,
                typeBadge  : g.badge,
                dateLabel  : g.lastDate,
                countLabel : g.count > 1 ? g.count + ' edits' : '1 edit'
            }));
    }

    // ── Incidents Tab ─────────────────────────────────────────────────────────
    @track _incidents          = [];
    @track _incidentsLoading   = false;
    @track _selectedIncident   = null;
    @track _correlatedChanges  = [];
    @track _correlatedLoading  = false;
    @track _aiAnalysis         = '';
    @track _aiAnalysisLoading  = false;

    get activeTabIncidents()   { return this.activeTab === 'incidents'; }
    get tabClassIncidents()    { return this._tab('incidents'); }
    get hasIncidents()         { return this._incidents.length > 0; }
    get hasSelectedIncident()  { return this._selectedIncident != null; }
    get hasCorrelated()        { return this._correlatedChanges.length > 0; }
    get incidentsCount()       { return this._incidents.length; }
    get criticalIncidentsCount() { return this._incidents.filter(i => i.severity === 'Critical').length; }
    get warningIncidentsCount()  { return this._incidents.filter(i => i.severity !== 'Critical').length; }
    get totalHitsCount()         { return this._incidents.reduce((sum, i) => sum + (i.hitCount || 1), 0); }
    get incidentHealthSummary() {
        if (this._incidentsLoading) return 'Loading incident data...';
        if (this._incidents.length === 0) return 'No production errors in the selected window — org looks healthy.';
        const crit = this._incidents.filter(i => i.severity === "Critical").length;
        const top  = this._incidents[0];
        const window = this.activeFilter === "1D" ? "24 hours" : this.activeFilter === "30D" ? "30 days" : "7 days";
        return crit + " critical incident" + (crit !== 1 ? "s" : "") + " in the last " + window + ". Most recent: " + (top ? top.apexClass + " — " + (top.errorMessage || "").substring(0, 80) : "");
    }

    showTabIncidents() {
        if (!this._isSysAdmin && !this._hasDevAccess) return;
        this.activeTab = 'incidents';
        this.loadIncidents();
    }

    loadIncidents() {
        if (this._incidentsLoading) return;
        this._incidentsLoading = true;
        this._selectedIncident = null;
        this._correlatedChanges = [];
        this._aiAnalysis = '';
        const hours = this.activeFilter === '1D' ? 24 : this.activeFilter === '30D' ? 720 : 168;
        getRecentErrors({ hours })
            .then(data => {
                this._incidents = (data || []).map(inc => ({
                    ...inc,
                    severityClass  : `w360-inc-badge w360-inc-sev-${(inc.severity || 'warning').toLowerCase()}`,
                    formattedTime  : inc.occurredAt
                        ? new Date(inc.occurredAt).toLocaleString('en-US', { month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' })
                        : 'Unknown',
                    hitLabel       : inc.hitCount > 1 ? `${inc.hitCount}x` : '1x',
                    sourceIcon     : inc.source === 'AsyncApexJob' ? 'utility:apex'
                                        : inc.source === 'ApexLog'      ? 'utility:bug'
                                        : 'utility:data_model',
                    sourceLabel    : inc.source === 'AsyncApexJob' ? 'Real Job Failure'
                                        : inc.source === 'ApexLog'      ? 'Apex Log'
                                        : 'Demo',
                }));
            })
            .catch(err => { console.error('Incidents load error', err); this._incidents = []; })
            .finally(() => { this._incidentsLoading = false; });
    }

    handleSelectIncident(evt) {
        const id = evt.currentTarget.dataset.id;
        this._selectedIncident = this._incidents.find(i => i.id === id) || null;
        this._correlatedChanges = [];
        this._aiAnalysis = '';
        if (!this._selectedIncident?.occurredAt) return;

        // Auto-load correlated changes
        this._correlatedLoading = true;
        getCorrelatedChanges({
            errorTimestampIso: this._selectedIncident.occurredAt,
            lookbackMinutes  : 120
        })
        .then(data => {
            this._correlatedChanges = (data || []).map(c => ({
                ...c,
                typeIcon     : this._changeTypeIcon(c.section),
                typeBadge    : this._changeTypeBadge(c.section),
                formattedTime: c.changedAt
                    ? new Date(c.changedAt).toLocaleString('en-US', { month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' })
                    : '',
            }));
        })
        .catch(err => { console.error('Correlated changes error', err); })
        .finally(() => { this._correlatedLoading = false; });
    }

    handleAnalyzeIncident() {
        if (!this._selectedIncident) return;
        this._aiAnalysisLoading = true;
        this._aiAnalysis = '';
        analyzeIncident({
            errorMessage  : this._selectedIncident.errorMessage,
            exceptionType : this._selectedIncident.exceptionType,
            stackTrace    : this._selectedIncident.stackTrace,
            devChangesJson: JSON.stringify(
                this._correlatedChanges.map(c => ({
                    component: c.component, section: c.section,
                    detail: c.detail, minutesBefore: c.minutesBefore
                }))
            )
        })
        .then(analysis => { this._aiAnalysis = analysis || 'No analysis returned.'; })
        .catch(err => { this._aiAnalysis = 'AI analysis unavailable: ' + (err.body?.message || err.message); })
        .finally(() => { this._aiAnalysisLoading = false; });
    }

    handleBackToIncidents() {
        this._selectedIncident = null;
        this._correlatedChanges = [];
        this._aiAnalysis = '';
    }

    _changeTypeIcon(section) {
        const s = (section || '').toLowerCase();
        if (s.includes('apex'))       return 'standard:apex';
        if (s.includes('flow'))       return 'standard:flow';
        if (s.includes('lightning') || s.includes('lwc')) return 'standard:lightning_component';
        if (s.includes('field'))      return 'standard:formula';
        if (s.includes('validation')) return 'standard:validation_rule';
        if (s.includes('object'))     return 'standard:custom_object';
        if (s.includes('profile') || s.includes('permission')) return 'standard:permission_set';
        return 'utility:settings';
    }

    _changeTypeBadge(section) {
        const s = (section || '').toLowerCase();
        if (s.includes('apex class'))   return 'Apex';
        if (s.includes('apex trigger')) return 'Trigger';
        if (s.includes('lwc') || s.includes('lightning web')) return 'LWC';
        if (s.includes('flow'))         return 'Flow';
        if (s.includes('custom field')) return 'Field';
        if (s.includes('validation'))   return 'Rule';
        if (s.includes('permission'))   return 'PermSet';
        return 'Config';
    }

    // ── Tabs ──────────────────────────────────────────────────────────────────
    _tab(n) { return `w360-tab-btn${this.activeTab===n?' w360-tab-active':''}`; }
    get tabClassRecent()    { return this._tab('recent'); }
    get tabClassOpps()      { return this._tab('opps'); }
    get tabClassTasks()     { return this._tab('tasks'); }
    get tabClassApprovals() { return this._tab('approvals'); }
    get tabClassPerms()     { return this._tab('perms'); }

    showTabRecent()    { this.activeTab = 'recent'; }
    showTabOpps()      { this.activeTab = 'opps'; }
    showTabTasks()     { this.activeTab = 'tasks'; }
    showTabApprovals() { this.activeTab = 'approvals'; }
    showTabPerms()     { this.activeTab = 'perms'; this.loadPermissions(); }

    // ── Stats ─────────────────────────────────────────────────────────────────
    get recentRecordsCount()    { return this.recentRecords.length; }
    get pendingApprovalsCount() { return this.pendingApprovals.length; }
    get overdueTasksCount()     { return this.overdueTasks.length; }
    get openOppsCount()         { return this.opportunities.length; }

    get hasRecentRecords()   { return this.recentRecords.length > 0; }
    get hasPendingApprovals(){ return this.pendingApprovals.length > 0; }
    get hasOverdueTasks()    { return this.overdueTasks.length > 0; }
    get hasOpportunities()   { return this.opportunities.length > 0; }
    get hasPermissions()     { return this.permissions.length > 0; }

    // ── Permission filtering ──────────────────────────────────────────────────
    get permSetNames() {
        const seen = new Set();
        const sets = [{ name:'ALL', label:'All', pillClass: this._pillClass('ALL') }];
        for (const p of this.permissions) {
            if (!seen.has(p.permSetName)) {
                seen.add(p.permSetName);
                sets.push({
                    name: p.permSetName,
                    label: p.permSetLabel,
                    pillClass: this._pillClass(p.permSetName)
                });
            }
        }
        return sets;
    }

    _pillClass(name) {
        return `w360-perm-pill${this.activePermSet===name?' w360-perm-pill-active':''}`;
    }

    get filteredPermissions() {
        return this.activePermSet === 'ALL'
            ? this.permissions
            : this.permissions.filter(p => p.permSetName === this.activePermSet);
    }

    handlePermSetFilter(evt) {
        this.activePermSet = evt.currentTarget.dataset.name;
    }

    // ── Navigation ────────────────────────────────────────────────────────────
    handleRecordClick(evt) {
        const id = evt.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type:'standard__recordPage',
            attributes:{ recordId:id, actionName:'view' }
        });
    }
    handleTaskClick(evt) { this.handleRecordClick(evt); }
    handleApprovalClick(evt) { this.handleRecordClick(evt); }

    async handleResumeSession() {
        // Call getLastSession directly — recentRecords is the 7-day activity feed
        // and may be empty or unrelated to the actual last session for non-sysadmin users.
        try {
            const records = await getLastSession();
            if (!records || records.length === 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'No Previous Session',
                    message: 'No records found from your last session.',
                    variant: 'info'
                }));
                return;
            }
            const top = records[0];
            this[NavigationMixin.Navigate]({
                type       : 'standard__recordPage',
                attributes : { recordId: top.recordId, actionName: 'view' }
            });
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Session Resumed ✅',
                message: `Opening ${top.recordName}${records.length > 1 ? ` (+${records.length - 1} more)` : ''}`,
                variant: 'success'
            }));
            // Dismiss so the banner does not re-appear after navigation
            if (top.sessionDate) {
                dismissSession({ sessionDate: top.sessionDate }).catch(() => {});
            }
        } catch (e) {
            console.error('[W360 ResumeSession]', e);
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Could Not Restore Session',
                message: 'Please try again or scroll down to your recent records.',
                variant: 'warning'
            }));
        }
    }

    handleRefresh() { this.permissions = []; this.loadAllData(); }

    handleOpenAssistant() {
        // Try to open utility bar item
        try {
            const utilityAPI = this.template.closest(`[data-id="utilitybar"]`);
            if (utilityAPI) {
                utilityAPI.openUtilityItem({ utilityLabel: `Workspace360 Assistant` });
                return;
            }
        } catch(e) { /* ignore */ }
        // Fallback: show toast guiding user to utility bar
        this.dispatchEvent(new ShowToastEvent({
            title  : 'Workspace360 Assistant',
            message: 'Click the Assistant icon in the bottom utility bar to start chatting about your activity, tasks, deals and approvals.',
            variant: 'info',
            mode   : 'dismissible'
        }));
    }

    handleSessionRestored(evt) {
        // Bubble up from the session restore banner
        // Reload the dashboard data so the restored records are freshly visible
        this.loadAllData();
        this.dispatchEvent(new ShowToastEvent({
            title  : '✅ Session Restored',
            message: `Showing ${(evt.detail?.records?.length || 0)} records from your last session`,
            variant: 'success'
        }));
    }

    _logDashboardVisit() {
        logActivity({ evt:{
            recordId:this.userId, objectType:'Dashboard',
            recordName:'Workspace 360 Home', actionType:'View',
            tabUrl:window.location.href
        }}).catch(()=>{});
    }

    // ── Data enrichment ───────────────────────────────────────────────────────
    _enrichRecentRecords(records) {
        return (records||[]).map(r => ({
            ...r,
            iconName       : OBJECT_ICON_MAP[r.objectType] || (r.objectType && r.objectType.endsWith('__c') ? 'standard:custom' : 'standard:record'),
            formattedAmount: r.amount
                ? '$'+Number(r.amount).toLocaleString('en-US',{maximumFractionDigits:0}) : '',
            daysAgoLabel   : r.daysAgo === 0 ? 'Today'
                           : r.daysAgo === 1 ? 'Yesterday'
                           : `${r.daysAgo}d ago`,
            daysAgoBadgeClass: r.daysAgo <= 1
                ? 'w360-days-badge w360-days-recent'
                : 'w360-days-badge w360-days-old',
            actionClass    : `w360-action-badge w360-action-${(r.actionType||'view').toLowerCase()}`,
        }));
    }

    _enrichApprovals(approvals) {
        return (approvals||[]).map(a => ({
            ...a,
            TargetObjectId  : a.ProcessInstance?.TargetObjectId,
            TargetObjectName: a.ProcessInstance?.TargetObject?.Name || 'Record',
            formattedDate   : a.CreatedDate
                ? new Date(a.CreatedDate).toLocaleDateString('en-US',{month:'short',day:'numeric'}) : '',
        }));
    }

    _enrichTasks(tasks) {
        return (tasks||[]).map(t => ({
            ...t,
            WhatName    : t.What?.Name || '',
            formattedDue: t.ActivityDate
                ? new Date(t.ActivityDate).toLocaleDateString('en-US',{month:'short',day:'numeric'}) : 'No date',
        }));
    }

    _enrichOpps(opps) {
        const stageMap = STAGE_PROGRESS;
        return (opps||[]).map(o => ({
            ...o,
            AccountName    : o.Account?.Name || '',
            formattedAmount: o.Amount
                ? '$'+Number(o.Amount).toLocaleString('en-US',{maximumFractionDigits:0}) : '',
            formattedClose : o.CloseDate
                ? new Date(o.CloseDate).toLocaleDateString('en-US',{month:'short',day:'numeric'}) : '',
            progressStyle  : `width:${stageMap[o.StageName]||20}%`,
        }));
    }

    _enrichPermissions(perms) {
        return (perms||[]).map((p,i) => ({
            ...p,
            key        : `${p.permSetName}-${p.objectName}-${i}`,
            readIcon   : p.canRead   ? '✅' : '—',
            createIcon : p.canCreate ? '✅' : '—',
            editIcon   : p.canEdit   ? '✅' : '—',
            deleteIcon : p.canDelete ? '✅' : '—',
            objIcon    : p.objectName?.includes('__c')
                ? 'standard:custom' : 'standard:record',
        }));
    }
}