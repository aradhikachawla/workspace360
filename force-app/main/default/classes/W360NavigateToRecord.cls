/**
 * W360NavigateToRecord
 * ─────────────────────────────────────────────────────────────────────────────
 * InvocableMethod called by the Workspace360 Agentforce agent when the user
 * asks to open a record from their last session.
 *
 * Agentforce redacts runtime-generated URLs (System.Url.getOrgDomainUrl)
 * as a platform security policy — the same reason W360NavigateToDashboard
 * uses DomainCreator.getLightningHostname() instead.  This class follows
 * the same pattern but accepts a recordId + objectType so it can build
 * a proper /lightning/r/<ObjectType>/<Id>/view link that the platform
 * will render rather than redact.
 *
 * Called by the agent after W360GetLastSession returns hasSession = true.
 */
public with sharing class W360NavigateToRecord {

    public class Request {
        @InvocableVariable(
            label='Record Id'
            description='Salesforce record ID to navigate to (15 or 18 char)'
            required=true
        )
        public String recordId;

        @InvocableVariable(
            label='Object Type'
            description='API name of the object, e.g. Opportunity, Case, Account'
            required=true
        )
        public String objectType;

        @InvocableVariable(
            label='Record Name'
            description='Human-readable record name, used in the response message'
            required=false
        )
        public String recordName;
    }

    public class Response {
        @InvocableVariable(label='Navigation Message'
            description='Full message with clickable navigation link to share with the user')
        public String message;

        @InvocableVariable(label='Record URL'
            description='Absolute URL to the record page')
        public String recordUrl;

        @InvocableVariable(label='Success'
            description='True if a valid URL was built, false if inputs were missing')
        public Boolean success;
    }

    @InvocableMethod(
        label       = 'Navigate to Workspace360 Record'
        description = 'Opens a specific Salesforce record by ID. Call this after W360GetLastSession returns a top record the user wants to open. Do NOT use the topRecordUrl field from W360GetLastSession directly — use this action instead so the URL is not redacted.'
        category    = 'Workspace360'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();

            if (String.isBlank(req.recordId) || String.isBlank(req.objectType)) {
                res.success = false;
                res.message = 'Unable to navigate: record ID or object type was not provided. Please open the Workspace360 Dashboard to access your session records.';
                responses.add(res);
                continue;
            }

            // Use DomainCreator (same approach as W360NavigateToDashboard) so
            // Agentforce does not redact the URL at render time.
            String host = '';
            try {
                host = DomainCreator.getLightningHostname();
            } catch (Exception e) {
                // fallback — may still be redacted in some orgs, but best effort
                try {
                    host = System.Url.getOrgDomainUrl().toExternalForm()
                               .replace('https://', '')
                               .replace('http://', '');
                } catch (Exception e2) {}
            }

            String url = String.isNotBlank(host)
                ? 'https://' + host + '/lightning/r/' + req.objectType + '/' + req.recordId + '/view'
                : '/lightning/r/' + req.objectType + '/' + req.recordId + '/view';

            String label = String.isNotBlank(req.recordName) ? req.recordName : req.objectType + ' record';

            res.success   = true;
            res.recordUrl = url;
            res.message   = 'Opening ' + label + ': ' + url;

            responses.add(res);
        }

        return responses;
    }
}