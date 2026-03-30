public with sharing class W360GetOverdueTasks {

    public class Request {
        @InvocableVariable(label='Placeholder' required=false)
        public String placeholder;
    }

    public class Response {
        @InvocableVariable(label='Summary Text')
        public String summaryText;
    }

    @InvocableMethod(
        label       = 'Get Overdue Tasks'
        description = 'Returns the user\'s overdue Salesforce tasks. Use when user asks about overdue tasks, what they need to follow up on, or their to-do list.'
        category    = 'Workspace360'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        try {
            List<Task> tasks = WorkspaceLogger.getOverdueTasks();
            Response res = new Response();
            if (tasks.isEmpty()) {
                res.summaryText = 'Great news! You have no overdue tasks. All caught up!';
            } else {
                String sb = 'You have ' + tasks.size() + ' overdue task' + (tasks.size()>1?'s':'') + ':\n';
                for (Integer i = 0; i < Math.min(tasks.size(), 5); i++) {
                    Task t = tasks[i];
                    sb += (i+1) + '. ' + t.Subject;
                    if (t.ActivityDate != null) sb += ' (due ' + t.ActivityDate.format() + ')';
                    if (t.Priority == 'High')   sb += ' ⚠ HIGH PRIORITY';
                    sb += '\n';
                }
                if (tasks.size() > 5) sb += '...and ' + (tasks.size()-5) + ' more.';
                res.summaryText = sb;
            }
            responses.add(res);
        } catch (Exception e) {
            Response res = new Response();
            res.summaryText = 'Error retrieving tasks: ' + e.getMessage();
            responses.add(res);
        }
        return responses;
    }
}