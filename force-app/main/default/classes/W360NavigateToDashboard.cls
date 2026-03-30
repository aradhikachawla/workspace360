public with sharing class W360NavigateToDashboard {

    public class Request {
        @InvocableVariable(label='Placeholder' required=false)
        public String placeholder;
    }

    public class Response {
        @InvocableVariable(label='Summary Text')
        public String summaryText;

        @InvocableVariable(label='Dashboard URL')
        public String dashboardUrl;
    }

    @InvocableMethod(
        label       = 'Navigate to Workspace360 Dashboard'
        description = 'Opens the Workspace360 Dashboard. Use when user asks to open or navigate to the dashboard.'
        category    = 'Workspace360'
    )
    public static List<Response> execute(List<Request> requests) {
        Response res = new Response();
        res.summaryText  = 'Opening your Workspace360 Dashboard.';
        res.dashboardUrl = '/lightning/n/Workspace360Dashboard';
        return new List<Response>{ res };
    }
}