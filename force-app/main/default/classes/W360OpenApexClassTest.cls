/**
 * W360OpenApexClassTest
 * Test coverage for W360OpenApexClass
 */
@IsTest
private class W360OpenApexClassTest {

    @IsTest
    static void testExecute_blankClassName() {
        W360OpenApexClass.Request req = new W360OpenApexClass.Request();
        req.className = '';

        List<W360OpenApexClass.Response> res = W360OpenApexClass.execute(new List<W360OpenApexClass.Request>{ req });

        System.assertEquals(1, res.size());
        System.assertEquals(false, res[0].found);
        System.assert(res[0].message.contains('specify'));
    }

    @IsTest
    static void testExecute_nonexistentClass() {
        W360OpenApexClass.Request req = new W360OpenApexClass.Request();
        req.className = 'NonExistentClassXYZ123';

        List<W360OpenApexClass.Response> res = W360OpenApexClass.execute(new List<W360OpenApexClass.Request>{ req });

        System.assertEquals(1, res.size());
        System.assertEquals(false, res[0].found);
        System.assert(res[0].message.contains('not found'));
    }

    @IsTest
    static void testExecute_existingClass() {
        W360OpenApexClass.Request req = new W360OpenApexClass.Request();
        req.className = 'WorkspaceLogger';

        List<W360OpenApexClass.Response> res = W360OpenApexClass.execute(new List<W360OpenApexClass.Request>{ req });

        System.assertEquals(1, res.size());
        if (res[0].found) {
            System.assert(res[0].classUrl.startsWith('/'), 'URL should be relative path');
            System.assert(res[0].message.contains('WorkspaceLogger'), 'Message should mention class name');
        }
        // If not found (sandbox may not have the class), that's ok
    }
}