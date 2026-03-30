public class W360DataPurgeScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {

        // Delete workspace context older than 30 days
        List<User_Workspace_Context__c> oldContext = [
            SELECT Id FROM User_Workspace_Context__c
            WHERE Session_Date__c < :Date.today().addDays(-30)
            LIMIT 9000
        ];
        if (!oldContext.isEmpty()) delete oldContext;

        // Delete incident log older than 90 days
        List<W360_Incident_Log__c> oldIncidents = [
            SELECT Id FROM W360_Incident_Log__c
            WHERE Occurred_At__c < :Datetime.now().addDays(-90)
            LIMIT 9000
        ];
        if (!oldIncidents.isEmpty()) delete oldIncidents;
    }
}