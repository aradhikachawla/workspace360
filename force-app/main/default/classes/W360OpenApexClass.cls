/**
 * W360OpenApexClass
 * Agentforce action that opens an Apex class in Setup when the user asks
 * to open or view a class (e.g., "Open WorkspaceLogger", "Show me AgentforceSummary").
 *
 * @author   Workspace 360 Hackathon Team
 * @version  1.0
 */
public with sharing class W360OpenApexClass {

    public class Request {
        @InvocableVariable(label='Class Name' description='Name of the Apex class to open (e.g., WorkspaceLogger, AgentforceSummary)' required=true)
        public String className;
    }

    public class Response {
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Class URL' description='Clickable link to open the Apex class in Setup')
        public String classUrl;
        @InvocableVariable(label='Found')
        public Boolean found;
    }

    @InvocableMethod(
        label='Open Apex Class'
        description='Opens an Apex class in Salesforce Setup. Use when user asks to open, view, or navigate to a specific Apex class (e.g., "Open WorkspaceLogger", "Show me the AgentforceSummary class", "Take me to W360GetDevActivitySummary").'
        category='Workspace360'
    )
    public static List<Response> execute(List<Request> requests) {
        String className = requests[0].className != null ? requests[0].className.trim() : '';
        Response res = new Response();

        if (String.isBlank(className)) {
            res.found   = false;
            res.message = 'Please specify an Apex class name to open.';
            res.classUrl = '';
            return new List<Response>{ res };
        }

        try {
            List<ApexClass> classes = [
                SELECT Id, Name
                FROM   ApexClass
                WHERE  Name = :className
                LIMIT  1
            ];

            if (classes.isEmpty()) {
                res.found   = false;
                res.message = 'Apex class "' + className + '" was not found. Check the class name and try again.';
                res.classUrl = '';
            } else {
                String classUrl = '/' + classes[0].Id;
                res.found   = true;
                res.classUrl = classUrl;
                res.message  = 'Click here to open ' + className + ' in Setup: ' + classUrl;
            }
        } catch (Exception e) {
            res.found   = false;
            res.message = 'Unable to open class: ' + e.getMessage();
            res.classUrl = '';
        }
        return new List<Response>{ res };
    }
}