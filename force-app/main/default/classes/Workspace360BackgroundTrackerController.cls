public without sharing class Workspace360BackgroundTrackerController {
    @AuraEnabled
    public static void logActivity(Map<String, Object> evtMap) {
        if (evtMap == null) return;
        WorkspaceLogger.WorkspaceEvent evt = new WorkspaceLogger.WorkspaceEvent();
        evt.recordId = (String) evtMap.get('recordId');
        evt.objectType = (String) evtMap.get('objectType');
        evt.recordName = (String) evtMap.get('recordName');
        evt.actionType = (String) evtMap.get('actionType');
        evt.tabUrl = (String) evtMap.get('tabUrl');
        evt.stage = (String) evtMap.get('stage');
        Object amt = evtMap.get('amount');
        evt.amount = amt != null ? Decimal.valueOf(String.valueOf(amt)) : null;
        WorkspaceLogger.logActivity(evt);
    }
}