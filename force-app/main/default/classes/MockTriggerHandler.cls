/**
 * File Name   :	MockTriggerHandler.cls
 * Description :	Test-only TriggerHandler implementation used by TriggerHandlerManagerTest to
 *                  verify dispatch, context matching, and recursion guarding through real DML.
 **/
@isTest
public class MockTriggerHandler extends TriggerHandler {
    public static Integer beforeInsertCount = 0;
    public static Integer afterInsertCount = 0;
    public static Integer beforeUpdateCount = 0;
    public static Integer afterUpdateCount = 0;
    public static Integer beforeDeleteCount = 0;
    public static Integer afterDeleteCount = 0;
    public static Integer afterUndeleteCount = 0;

    public static void resetCounts() {
        beforeInsertCount = 0;
        afterInsertCount = 0;
        beforeUpdateCount = 0;
        afterUpdateCount = 0;
        beforeDeleteCount = 0;
        afterDeleteCount = 0;
        afterUndeleteCount = 0;
    }

    protected override void beforeInsert(List<SObject> newList) {
        beforeInsertCount++;
    }

    protected override void afterInsert(List<SObject> newList) {
        afterInsertCount++;
    }

    protected override void beforeUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        beforeUpdateCount++;
    }

    protected override void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        afterUpdateCount++;
    }

    protected override void beforeDelete(List<SObject> oldList) {
        beforeDeleteCount++;
    }

    protected override void afterDelete(List<SObject> oldList) {
        afterDeleteCount++;
    }

    protected override void afterUndelete(List<SObject> newList) {
        afterUndeleteCount++;
    }
}
