import { LightningElement } from 'lwc';
import logActivity from '@salesforce/apex/WorkspaceLogger.logActivity';
import markSessionEnd from '@salesforce/apex/WorkspaceLogger.markSessionEnd';

/**
 * Workspace360GlobalTracker
 * ─────────────────────────────────────────────────────────────────────────────
 * Lives in the Utility Bar — always loaded, always listening.
 * Tracks ANY record page the user visits regardless of object type.
 * No need to add workspace360Tracker to individual record pages.
 *
 * "Browser tab restore" behaviour:
 *   • Each navigation is logged with Session_Timestamp__c and Is_Active_Session__c = true
 *   • When the user leaves / closes the app, markSessionEnd is called (best-effort)
 *   • On next login the dashboard reads the last session's active records and
 *     presents a "Restore session?" banner — exactly like Chrome's tab restore.
 */
export default class Workspace360GlobalTracker extends LightningElement {

    _lastTrackedUrl   = null;
    _lastTrackedId    = null;
    _sessionStartTime = null;
    _pollInterval     = null;
    _debounceTimer    = null;

    // Object-type → name field mapping (fallback to 'Name' for unknowns)
    static NAME_FIELD_MAP = {
        Case        : 'Subject',
        Task        : 'Subject',
        EmailMessage: 'Subject',
    };

    connectedCallback() {
        this._sessionStartTime = new Date().toISOString();
        this._checkNavigation();

        // Poll every 1.2 s — catches standard nav, custom objects, tabs, everything
        this._pollInterval = setInterval(() => this._checkNavigation(), 1200);

        // Mark session end on tab/window close (best-effort)
        window.addEventListener('beforeunload', this._handleUnload.bind(this));
        // Also handle Salesforce SPA "hidden" event
        document.addEventListener('visibilitychange', this._handleVisibility.bind(this));
    }

    disconnectedCallback() {
        if (this._pollInterval) clearInterval(this._pollInterval);
        if (this._debounceTimer) clearTimeout(this._debounceTimer);
        window.removeEventListener('beforeunload', this._handleUnload.bind(this));
        document.removeEventListener('visibilitychange', this._handleVisibility.bind(this));
    }

    // ── Core navigation detection ─────────────────────────────────────────────

    _checkNavigation() {
        const url = window.location.href;
        if (url === this._lastTrackedUrl) return;

        // Match /lightning/r/ObjectApiName/RecordId/view|edit|related
        //   also handles  /lightning/r/Object__c/RecordId/view
        const match = url.match(/\/lightning\/r\/([^/]+)\/([a-zA-Z0-9]{15,18})\/(view|edit|related)/);
        if (!match) return;

        const objectType = match[1];
        const recordId   = match[2];
        const actionRaw  = match[3];

        // Never log our own tracking object — avoids infinite loop
        if (objectType === 'User_Workspace_Context__c') return;

        this._lastTrackedUrl = url;
        this._lastTrackedId  = recordId;

        // Debounce 400 ms so rapid tab-switching doesn't flood the server
        if (this._debounceTimer) clearTimeout(this._debounceTimer);
        this._debounceTimer = setTimeout(() => {
            this._doLog(recordId, objectType, actionRaw, url);
        }, 400);
    }

    _doLog(recordId, objectType, actionRaw, url) {
        const actionType = actionRaw === 'edit' ? 'Edit' : 'View';
        // Truncate URL to 255 chars (field limit) — Apex also guards this
        const tabUrl = url.length > 255 ? url.substring(0, 255) : url;

        logActivity({
            evt: {
                recordId,
                objectType,
                recordName : null,   // Apex resolves the real name dynamically
                actionType,
                tabUrl,
                stage      : null,
                amount     : null,
            }
        }).catch(err => console.warn('[W360 Tracker]', err));
    }

    // ── Session lifecycle ─────────────────────────────────────────────────────

    _handleUnload() {
        // synchronous best-effort — fire-and-forget
        if (this._lastTrackedId) {
            markSessionEnd({ recordId: this._lastTrackedId }).catch(() => {});
        }
    }

    _handleVisibility() {
        if (document.visibilityState === 'hidden' && this._lastTrackedId) {
            markSessionEnd({ recordId: this._lastTrackedId }).catch(() => {});
        }
    }
}