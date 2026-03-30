/**
 * W360GetDevActivitySummaryTest
 * Test coverage for W360GetDevActivitySummary.cls (agent dev activity action)
 *
 * @author   Workspace 360 Hackathon Team
 */
@IsTest
private class W360GetDevActivitySummaryTest {

    @IsTest
    static void testExecute_defaultWindow() {
        W360GetDevActivitySummary.Request req = new W360GetDevActivitySummary.Request();
        req.timeWindow = null;

        Test.startTest();
        List<W360GetDevActivitySummary.Response> res = W360GetDevActivitySummary.execute(new List<W360GetDevActivitySummary.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size(), 'Should return one response');
        System.assertNotEquals(null, res[0].summaryText, 'Summary text should not be null');
        System.assertNotEquals(null, res[0].dashboardUrl, 'Dashboard URL should not be null');
        System.assert(res[0].activityCount >= 0, 'Activity count should be non-negative');
    }

    @IsTest
    static void testExecute_1D() {
        W360GetDevActivitySummary.Request req = new W360GetDevActivitySummary.Request();
        req.timeWindow = '1D';

        Test.startTest();
        List<W360GetDevActivitySummary.Response> res = W360GetDevActivitySummary.execute(new List<W360GetDevActivitySummary.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assert(String.isNotBlank(res[0].summaryText), 'Should have summary text');
    }

    @IsTest
    static void testExecute_7D() {
        W360GetDevActivitySummary.Request req = new W360GetDevActivitySummary.Request();
        req.timeWindow = '7D';

        Test.startTest();
        List<W360GetDevActivitySummary.Response> res = W360GetDevActivitySummary.execute(new List<W360GetDevActivitySummary.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assert(res[0].dashboardUrl.contains('Workspace360Dashboard'), 'Should include dashboard URL');
    }

    @IsTest
    static void testExecute_30D() {
        W360GetDevActivitySummary.Request req = new W360GetDevActivitySummary.Request();
        req.timeWindow = '30D';

        Test.startTest();
        List<W360GetDevActivitySummary.Response> res = W360GetDevActivitySummary.execute(new List<W360GetDevActivitySummary.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size());
        System.assert(res[0].summaryText.contains('30') || res[0].summaryText.contains('last') || res[0].summaryText.contains('days'), 'Should reference 30 days');
    }
}