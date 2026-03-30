import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent }  from 'lightning/platformShowToastEvent';
import getLastSession      from '@salesforce/apex/WorkspaceLogger.getLastSession';
import dismissSession      from '@salesforce/apex/WorkspaceLogger.dismissSession';

import USER_ID    from '@salesforce/user/Id';
import FIRST_NAME from '@salesforce/schema/User.FirstName';
import { getRecord } from 'lightning/uiRecordApi';

const OBJECT_ICON_MAP = {
    Opportunity  : 'standard:opportunity',
    Case         : 'standard:case',
    Account      : 'standard:account',
    Contact      : 'standard:contact',
    Lead         : 'standard:lead',
    Task         : 'standard:task',
    Campaign     : 'standard:campaign',
    Contract     : 'standard:contract',
    Order        : 'standard:orders',
    Quote        : 'standard:quote',
};

/**
 * workspace360SessionRestore
 * ─────────────────────────────────────────────────────────────────────────────
 * Shows a "restore session" banner on the dashboard when the user has
 * unfinished records from a previous session — like Chrome's tab restore.
 *
 * Fires a custom event  "sessionrestored"  when the user clicks Restore.
 */
export default class Workspace360SessionRestore extends NavigationMixin(LightningElement) {

    @track showBanner   = false;
    @track isExpanded   = false;
    @track sessionTabs  = [];
    @track _firstName   = '';
    @track sessionDateLabel = '';
    @track sessionSummary   = '';

    userId = USER_ID;
    _sessionDate = null;

    @wire(getRecord, { recordId: '$userId', fields: [FIRST_NAME] })
    wiredUser({ data }) {
        if (data) this._firstName = data.fields.FirstName.value || '';
    }

    get firstNameClause() {
        return this._firstName ? `, ${this._firstName}` : '';
    }

    connectedCallback() {
        this._loadLastSession();
    }

    async _loadLastSession() {
        try {
            const records = await getLastSession();
            if (!records || records.length === 0) return;

            this._sessionDate = records[0].sessionDate;
            this.sessionDateLabel = this._formatSessionDate(records[0].sessionDate);
            this.sessionTabs  = records.map(r => ({
                ...r,
                iconName   : OBJECT_ICON_MAP[r.objectType]
                           || (r.objectType?.endsWith('__c') ? 'standard:custom' : 'standard:record'),
                timeLabel  : this._formatTime(r.sessionTimestamp),
            }));

            // Build summary e.g. "3 Opportunities, 1 Case, 2 Accounts"
            this.sessionSummary = this._buildSummary(records);
            this.showBanner = true;
        } catch (e) {
            console.warn('[W360 Restore]', e);
        }
    }

    // ── Event handlers ────────────────────────────────────────────────────────

    handleToggle() {
        this.isExpanded = !this.isExpanded;
    }

    handleRestore() {
        // Open the most recent / highest priority record
        const top = this.sessionTabs[0];
        if (!top) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: top.recordId, actionName: 'view' }
        });
        // Notify parent dashboard to refresh
        this.dispatchEvent(new CustomEvent('sessionrestored', {
            bubbles: true,
            detail: { records: this.sessionTabs }
        }));
        this._dismiss();
    }

    handleRestoreAll() {
        // Navigate to the top record; others are shown in the dashboard feed
        this.handleRestore();
        this.dispatchEvent(new ShowToastEvent({
            title  : '✅ Session Restored',
            message: `Opened ${this.sessionTabs.length} records from your last session`,
            variant: 'success'
        }));
    }

    handleTabClick(evt) {
        const id = evt.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, actionName: 'view' }
        });
    }

    handleDismiss() {
        this._dismiss();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _dismiss() {
        this.showBanner = false;
        // Mark session as dismissed so it doesn't show again
        if (this._sessionDate) {
            dismissSession({ sessionDate: this._sessionDate }).catch(() => {});
        }
    }

    _formatSessionDate(dateStr) {
        if (!dateStr) return 'yesterday';
        try {
            const d = new Date(dateStr);
            const today = new Date();
            const diff  = Math.round((today - d) / 86400000);
            if (diff === 0) return 'today';
            if (diff === 1) return 'yesterday';
            return d.toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
        } catch { return 'your last session'; }
    }

    _formatTime(ts) {
        if (!ts) return '';
        try {
            return new Date(ts).toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        } catch { return ''; }
    }

    _buildSummary(records) {
        const counts = {};
        for (const r of records) {
            counts[r.objectType] = (counts[r.objectType] || 0) + 1;
        }
        return Object.entries(counts)
            .map(([obj, cnt]) => {
                const IRREGULAR = {
                    Opportunity: 'Opportunities', Activity: 'Activities',
                    Case: 'Cases', Lead: 'Leads', Account: 'Accounts',
                    Contact: 'Contacts', Task: 'Tasks', Campaign: 'Campaigns',
                };
                const plural = IRREGULAR[obj] || obj + 's';
                return `${cnt} ${cnt === 1 ? obj : plural}`;
            })
            .join(', ');
    }
}