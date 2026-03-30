public with sharing class W360GetOpenOpportunities {

    public class Request {
        @InvocableVariable(label='Placeholder' required=false)
        public String placeholder;
    }

    public class Response {
        @InvocableVariable(label='Summary Text')
        public String summaryText;
    }

    @InvocableMethod(
        label       = 'Get Open Opportunities'
        description = 'Returns the user\'s open Salesforce opportunities with stage and amount. Use when user asks about their deals, pipeline, revenue forecast, or open opportunities.'
        category    = 'Workspace360'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        try {
            List<Opportunity> opps = WorkspaceLogger.getInProgressOpportunities();
            Response res = new Response();
            if (opps.isEmpty()) {
                res.summaryText = 'No open opportunities found.';
            } else {
                Decimal total = 0;
                String sb = 'You have ' + opps.size() + ' open opportunit' + (opps.size()>1?'ies':'y') + ':\n';
                for (Integer i = 0; i < Math.min(opps.size(), 5); i++) {
                    Opportunity o = opps[i];
                    sb += (i+1) + '. ' + o.Name + ' — ' + o.StageName;
                    if (o.Amount    != null) { sb += ' ($' + o.Amount.setScale(0).format() + ')'; total += o.Amount; }
                    if (o.CloseDate != null)   sb += ' closes ' + o.CloseDate.format();
                    sb += '\n';
                }
                if (opps.size() > 5) sb += '...and ' + (opps.size()-5) + ' more.';
                sb += '\nTotal pipeline: $' + total.setScale(0).format();
                res.summaryText = sb;
            }
            responses.add(res);
        } catch (Exception e) {
            Response res = new Response();
            res.summaryText = 'Error retrieving opportunities: ' + e.getMessage();
            responses.add(res);
        }
        return responses;
    }
}