public with sharing class W360GetLastSession {

    public class Request {
        @InvocableVariable(label='Max Records' description='Max records to return (default 5)' required=false)
        public Integer maxRecords;
    }

    public class Response {
        @InvocableVariable(label='Summary Text')
        public String summaryText;

        @InvocableVariable(label='Dashboard URL')
        public String dashboardUrl;
    }

    @InvocableMethod(
        label       = 'Get Last Session'
        description = 'Returns the user\'s last Salesforce work session. Use when the user asks about yesterday\'s work, wants to restore a session, or asks what they were working on.'
        category    = 'Workspace360'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        try {
            List<WorkspaceLogger.RecordCard> records = WorkspaceLogger.getLastSession();
            Response res = new Response();
            res.dashboardUrl = '/lightning/n/Workspace360Dashboard';

            if (records.isEmpty()) {
                res.summaryText = 'No previous session found. Ready to start fresh!';
            } else {
                Integer max = (requests[0].maxRecords != null) ? requests[0].maxRecords : 5;
                WorkspaceLogger.RecordCard top = records[0];

                String sb = 'Your last session was on ' + top.sessionDate + '. Here\'s what you were working on:\n\n';
                for (Integer i = 0; i < Math.min(records.size(), max); i++) {
                    WorkspaceLogger.RecordCard r = records[i];
                    sb += (i + 1) + '. ' + r.recordName + ' (' + r.objectType + ')';
                    if (r.actionType == 'Edit') sb += ' — edited';
                    if (r.stage != null)        sb += ' [' + r.stage + ']';
                    sb += '\n';
                }
                if (records.size() > max) {
                    sb += '...and ' + (records.size() - max) + ' more records.';
                }
                res.summaryText = sb;
            }
            responses.add(res);
        } catch (Exception e) {
            Response res = new Response();
            res.summaryText  = 'Error retrieving session: ' + e.getMessage();
            res.dashboardUrl = '/lightning/n/Workspace360Dashboard';
            responses.add(res);
        }
        return responses;
    }
}