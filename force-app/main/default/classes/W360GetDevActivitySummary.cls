/**
 * W360GetDevActivitySummary
 * Agentforce/Einstein Copilot invocable action that returns a natural-language summary
 * of the user's developer activity (metadata changes: Apex, LWC, flows, etc).
 * Does NOT modify any existing methods; uses WorkspaceLogger.getDevActivity().
 *
 * @author   Workspace 360 Hackathon Team
 * @version  1.0
 */
public with sharing class W360GetDevActivitySummary {

    public class Request {
        @InvocableVariable(label='Time Window' description='1D, 7D, or 30D' required=false)
        public String timeWindow;
    }

    public class Response {
        @InvocableVariable(label='Dev Activity Summary')
        public String summaryText;
        @InvocableVariable(label='Dev Activity Count')
        public Integer activityCount;
        @InvocableVariable(label='Dashboard URL')
        public String dashboardUrl;
    }

    @InvocableMethod(
        label='Get Dev Activity Summary'
        description='Returns a summary of the user\'s developer activity (metadata changes: Apex classes, LWC, flows, custom fields, etc). Use when user asks about dev activity, what they coded/changed recently, which Apex classes or components they modified, or developer work in the last 1/7/30 days.'
        category='Workspace360'
    )
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        String window = (requests[0].timeWindow != null) ? requests[0].timeWindow.toUpperCase() : '7D';
        Integer days = parseDays(window);

        try {
            List<WorkspaceLogger.DevActivityRaw> raw = WorkspaceLogger.getDevActivity(days);
            Response res = new Response();
            res.activityCount = raw.size();
            res.dashboardUrl  = buildDashboardUrl();

            if (raw.isEmpty()) {
                String windowLabel = days == 1 ? 'the last day' : 'the last ' + days + ' days';
                res.summaryText = 'No developer activity found in ' + windowLabel + '. You can view your Workspace360 Dashboard for more details.';
            } else {
                res.summaryText = buildSummary(raw, days);
            }
            responses.add(res);
        } catch (Exception e) {
            Response res = new Response();
            res.summaryText  = 'Unable to retrieve dev activity: ' + e.getMessage();
            res.activityCount = 0;
            res.dashboardUrl  = buildDashboardUrl();
            responses.add(res);
        }
        return responses;
    }

    private static Integer parseDays(String window) {
        if (window == '1D') return 1;
        if (window == '30D') return 30;
        return 7;
    }

    /**
     * Builds the URL for Workspace360 Dashboard.
     * Returns relative path so links resolve in the current Lightning tab (avoids "Page doesn't exist").
     */
    private static String buildDashboardUrl() {
        try {
            String host = DomainCreator.getLightningHostname();
            if (String.isNotBlank(host)) {
                return 'https://' + host + '/lightning/n/Workspace360Dashboard';
            }
        } catch (Exception e) { /* fallback */ }
        return System.Url.getOrgDomainUrl().toExternalForm() + '/lightning/n/Workspace360Dashboard';
    }

    private static String buildSummary(List<WorkspaceLogger.DevActivityRaw> raw, Integer days) {
        String windowLabel = days == 1 ? 'the last day' : 'the last ' + days + ' days';

        // Group by component (extract name + section)
        Map<String, GroupedItem> grouped = new Map<String, GroupedItem>();
        for (WorkspaceLogger.DevActivityRaw r : raw) {
            String name  = extractComponentName(r.Display, r.Section);
            String key   = name + '||' + (r.Section != null ? r.Section : '');
            if (!grouped.containsKey(key)) {
                GroupedItem g = new GroupedItem();
                g.name      = name;
                g.section   = r.Section;
                g.typeBadge = getTypeBadge(r.Section);
                g.count     = 0;
                g.lastDate  = r.CreatedDate;
                g.changedBy = r.ChangedBy;  // sysadmin who last touched this component
                grouped.put(key, g);
            }
            GroupedItem g = grouped.get(key);
            g.count++;
            // DevActivityRaw.CreatedDate is formatted string (yyyy-MM-dd...), keep most recent
            // Also update changedBy to whoever made the most recent change
            if (String.isNotBlank(r.CreatedDate) && (String.isBlank(g.lastDate) || r.CreatedDate > g.lastDate)) {
                g.lastDate  = r.CreatedDate;
                g.changedBy = r.ChangedBy;
            }
        }

        List<GroupedItem> items = new List<GroupedItem>(grouped.values());
        items.sort();

        String sb = 'In ' + windowLabel + ', you made ' + raw.size()
          + ' metadata change' + (raw.size() == 1 ? '' : 's')
          + ' across ' + items.size() + ' component'
          + (items.size() == 1 ? '' : 's') + ':\n\n';

        for (Integer i = 0; i < Math.min(items.size(), 15); i++) {
            GroupedItem g = items[i];
            String dateStr = (String.isNotBlank(g.lastDate) && g.lastDate.length() >= 10)
                ? g.lastDate.substring(0, 10) : '';
            sb += '• ' + g.name;
            if (String.isNotBlank(g.typeBadge)) sb += ' (' + g.typeBadge + ')';
            sb += ' — ' + g.count + ' edit' + (g.count > 1 ? 's' : '');
            if (String.isNotBlank(g.changedBy)) sb += ' by ' + g.changedBy;
            if (String.isNotBlank(dateStr)) sb += ' — ' + dateStr;
            sb += '\n';
        }
        if (items.size() > 15) {
            sb += '...and ' + (items.size() - 15) + ' more.\n';
        }
        String dashUrl = buildDashboardUrl();
        sb += '\nView the full Dev Activity list on your Workspace360 Dashboard: ' + dashUrl;
        return sb;
    }

    private static String extractComponentName(String display, String section) {
        if (String.isBlank(display)) return '(unknown)';
        String d = display.trim();
        List<String> verbs = new List<String>{'Changed ', 'Created ', 'Deleted ', 'Deployed ', 'Installed ', 'Activated ', 'Deactivated ', 'Saved '};
        for (String v : verbs) {
            if (d.startsWithIgnoreCase(v)) {
                d = d.substring(v.length()).trim();
                break;
            }
        }
        List<String> suffixes = new List<String>{
            ' Apex Class code', ' Apex Class', ' Lightning Web Component', ' Lightning Component',
            ' Aura Component', ' Flow Definition', ' Flow', ' Custom Object Definition',
            ' Custom Object', ' Custom Field', ' Validation Rule', ' Workflow Rule',
            ' Permission Set', ' Profile', ' Static Resource', ' Custom Label',
            ' Custom Metadata', ' Named Credential', ' Remote Site Setting', ' code'
        };
        for (String suf : suffixes) {
            if (d.endsWithIgnoreCase(suf)) {
                d = d.substring(0, d.length() - suf.length()).trim();
                break;
            }
        }
        return String.isBlank(d) ? display : d;
    }

    private static String getTypeBadge(String section) {
        if (String.isBlank(section)) return 'Config';
        String s = section.toLowerCase();
        if (s.contains('apex class'))   return 'Apex';
        if (s.contains('apex trigger')) return 'Trigger';
        if (s.contains('lwc') || s.contains('lightning web')) return 'LWC';
        if (s.contains('lightning component') || s.contains('aura')) return 'Aura';
        if (s.contains('lightning page'))  return 'Page';
        if (s.contains('flow'))            return 'Flow';
        if (s.contains('custom field'))    return 'Field';
        if (s.contains('custom object'))   return 'Object';
        if (s.contains('validation'))      return 'Rule';
        if (s.contains('workflow'))        return 'Workflow';
        if (s.contains('permission set'))  return 'PermSet';
        if (s.contains('profile'))         return 'Profile';
        if (s.contains('static resource')) return 'Resource';
        if (s.contains('named credential')) return 'Credential';
        if (s.contains('custom label'))    return 'Label';
        if (s.contains('custom metadata')) return 'CMDT';
        return 'Config';
    }

    private class GroupedItem implements Comparable {
        String name;
        String section;
        String typeBadge;
        Integer count;
        String lastDate;   // formatted yyyy-MM-dd, sorts correctly
        String changedBy;  // name of sysadmin who made the most recent change

        public Integer compareTo(Object other) {
            GroupedItem o = (GroupedItem) other;
            if (String.isNotBlank(this.lastDate) && String.isNotBlank(o.lastDate)) {
                return o.lastDate.compareTo(this.lastDate);  // descending (newest first)
            }
            return this.name.compareTo(o.name);
        }
    }
}