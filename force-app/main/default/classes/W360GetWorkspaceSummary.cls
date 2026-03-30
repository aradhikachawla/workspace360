public with sharing class W360GetWorkspaceSummary {
    public class Request {
        @InvocableVariable(label='Time Window' description='1D, 7D, or 30D' required=false)
        public String timeWindow;
    }
    public class Response {
        @InvocableVariable(label='Summary Text')
        public String summaryText;
        @InvocableVariable(label='Record Count')
        public Integer recordCount;
        @InvocableVariable(label='Dashboard URL')
        public String dashboardUrl;
    }
    @InvocableMethod(
        label='Get Workspace Summary'
        description='Returns a natural language summary of the user\'s recent Workspace360 activity. Use when user asks what they worked on recently, wants an activity summary, or asks about their Salesforce session.'
        category='Workspace360'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        String window = (requests[0].timeWindow != null) ? requests[0].timeWindow.toUpperCase() : '7D';
        try {
            List<WorkspaceLogger.RecordCard> records = (window == '1D')
                ? WorkspaceLogger.getLastSession()
                : WorkspaceLogger.getLast7DaysRecords();
            List<User_Workspace_Context__c> ctx = WorkspaceLogger.getYesterdayContext();
            String aiText = AgentforceSummary.generateSummary(ctx);
            Map<String, Integer> typeCounts = new Map<String, Integer>();
            Integer edits = 0;
            for (WorkspaceLogger.RecordCard r : records) {
                String t = r.objectType != null ? r.objectType : 'Record';
                typeCounts.put(t, (typeCounts.containsKey(t) ? typeCounts.get(t) : 0) + 1);
                if (r.actionType == 'Edit') edits++;
            }
            String windowLabel = window == '1D' ? 'yesterday' : 'the last ' + window.replace('D',' days');
            String sb = records.isEmpty() ? aiText :
                'In ' + windowLabel + ' you worked on ' + records.size() + ' record' + (records.size()>1?'s':'')
                + ' across ' + typeCounts.size() + ' object type' + (typeCounts.size()>1?'s':'') + ':\n';
            for (String t : typeCounts.keySet()) sb += '• ' + typeCounts.get(t) + ' ' + t + '\n';
            if (edits > 0) sb += edits + ' edit' + (edits>1?'s':'') + ' made.\n';
            if (!records.isEmpty()) sb += '\n' + aiText;
            Response res = new Response();
            res.summaryText  = sb;
            res.recordCount  = records.size();
            res.dashboardUrl = '/lightning/n/Workspace360Dashboard';
            responses.add(res);
        } catch (Exception e) {
            Response res = new Response();
            res.summaryText = 'Unable to retrieve workspace summary: ' + e.getMessage();
            res.recordCount = 0;
            res.dashboardUrl = '/lightning/n/Workspace360Dashboard';
            responses.add(res);
        }
        return responses;
    }
}