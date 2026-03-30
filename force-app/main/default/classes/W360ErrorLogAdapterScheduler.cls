/**
 * W360ErrorLogAdapterScheduler
 * ─────────────────────────────────────────────────────────────────────────────
 * Runs W360ErrorLogAdapter.syncAll() on a schedule so W360_Incident_Log__c
 * stays fresh with the latest errors from the org's existing error log tables.
 *
 * ── Schedule it (run once in Developer Console → Execute Anonymous) ──────────
 *
 *   // Every hour at the top of the hour:
 *   System.schedule('W360 Error Log Sync - Hourly',
 *       '0 0 * * * ?',
 *       new W360ErrorLogAdapterScheduler());
 *
 *   // Every 30 minutes (two separate jobs):
 *   System.schedule('W360 Error Log Sync - Half Hour 1',
 *       '0 0 * * * ?',
 *       new W360ErrorLogAdapterScheduler());
 *   System.schedule('W360 Error Log Sync - Half Hour 2',
 *       '0 30 * * * ?',
 *       new W360ErrorLogAdapterScheduler());
 *
 * ── To run manually ──────────────────────────────────────────────────────────
 *
 *   W360ErrorLogAdapter.SyncResult result = W360ErrorLogAdapter.syncAll();
 *   System.debug(result.summary());
 *   for (String msg : result.messages) System.debug(msg);
 *
 * ── To stop the schedule ─────────────────────────────────────────────────────
 *
 *   for (CronTrigger ct : [SELECT Id FROM CronTrigger
 *                          WHERE CronJobDetail.Name LIKE 'W360 Error Log Sync%']) {
 *       System.abortJob(ct.Id);
 *   }
 */
public class W360ErrorLogAdapterScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        try {
            W360ErrorLogAdapter.SyncResult result = W360ErrorLogAdapter.syncAll();
            System.debug(LoggingLevel.INFO, result.summary());
            for (String msg : result.messages) {
                System.debug(LoggingLevel.INFO, 'W360Sync: ' + msg);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'W360ErrorLogAdapterScheduler: unexpected error — ' + e.getMessage());
        }
    }
}
