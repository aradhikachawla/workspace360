public with sharing class W360GetPendingApprovals {

    public class Request {
        @InvocableVariable(label='Placeholder' required=false)
        public String placeholder;
    }

    public class Response {
        @InvocableVariable(label='Summary Text')
        public String summaryText;
    }

    @InvocableMethod(
        label       = 'Get Pending Approvals'
        description = 'Returns records waiting for the user\'s approval in Salesforce. Use when user asks about approvals, what needs their sign-off, or pending requests.'
        category    = 'Workspace360'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        try {
            List<ProcessInstanceWorkitem> approvals = WorkspaceLogger.getPendingApprovals();
            Response res = new Response();
            if (approvals.isEmpty()) {
                res.summaryText = 'No pending approvals. Your inbox is clear!';
            } else {
                String sb = 'You have ' + approvals.size() + ' pending approval' + (approvals.size()>1?'s':'') + ':\n';
                for (Integer i = 0; i < Math.min(approvals.size(), 5); i++) {
                    ProcessInstanceWorkitem a = approvals[i];
                    String name = (a.ProcessInstance != null && a.ProcessInstance.TargetObject != null)
                        ? a.ProcessInstance.TargetObject.Name : 'Record';
                    sb += (i+1) + '. ' + name + '\n';
                }
                if (approvals.size() > 5) sb += '...and ' + (approvals.size()-5) + ' more.';
                res.summaryText = sb;
            }
            responses.add(res);
        } catch (Exception e) {
            Response res = new Response();
            res.summaryText = 'Error retrieving approvals: ' + e.getMessage();
            responses.add(res);
        }
        return responses;
    }
}