import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import logActivity from '@salesforce/apex/WorkspaceLogger.logActivity';

export default class Workspace360Tracker extends LightningElement {
    @api recordId;
    @api objectApiName;
    _logged = false;

    @wire(getRecord, { recordId: '$recordId', fields: '$_fields' })
    wiredRecord({ data }) {
        if (data && !this._logged) {
            this._logged = true;
            const f = data.fields;
            logActivity({ evt: {
                recordId   : this.recordId,
                objectType : this.objectApiName,
                recordName : f.Name?.value || f.Subject?.value || this.recordId,
                actionType : 'View',
                tabUrl     : window.location.href,
                stage      : f.StageName?.value || f.Status?.value || null,
                amount     : f.Amount?.value || null,
            }}).catch(()=>{});
        }
    }

    get _fields() {
        const o = this.objectApiName;
        const map = {
            Opportunity: ['Opportunity.Name','Opportunity.StageName','Opportunity.Amount'],
            Case       : ['Case.Subject','Case.Status'],
            Account    : ['Account.Name'],
            Contact    : ['Contact.Name'],
            Lead       : ['Lead.Name'],
        };
        return map[o] || [`${o}.Name`];
    }
}