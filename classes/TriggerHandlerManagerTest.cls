@isTest
private class TriggerHandlerManagerTest {

    @isTest
    static void handleReturnsEarlyForBlankOrNullObjectName() {
        Test.startTest();
        TriggerHandlerManager.handle('');
        TriggerHandlerManager.handle(null);
        Test.stopTest();
    }

    @isTest
    static void handleDoesNothingWithoutActiveTriggerContext() {
        MockTriggerHandler.resetCounts();

        Test.startTest();
        TriggerHandlerManager.handle('Account');
        Test.stopTest();

        Assert.areEqual(0, MockTriggerHandler.afterInsertCount, 'Called outside a trigger, Trigger.operationType is null, so no context matches and nothing should execute.');
    }
}
