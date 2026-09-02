/**
 * File Name   :	TriggerHandlerManager.cls
 * Description :	Manager for selecting and executing the appropriate trigger handlers.
 **/
public inherited sharing class TriggerHandlerManager {

    private static Map<String, Set<Id>> processedIdsByHandler = new Map<String, Set<Id>>();

    /**
     * Method responsible for handling trigger execution logic.
     * @param objectName the api name of the SObject.
     */
    public static void handle(String objectName) {
        if(String.isBlank(objectName)) { return; }
        List<Trigger_Handler__mdt> triggerHandlers = Test.isRunningTest() ? getMockDataTriggerHandler() : getTriggerHandlersByObjectName(objectName);
        if (triggerHandlers.isEmpty()) { return; }
        for (Trigger_Handler__mdt handler : triggerHandlers) {
            if (!matchesCurrentContext(handler)) { continue; }
            String handlerKey = handler.Class_Name__c + ':' + Trigger.operationType;
            Set<Id> currentIds = getCurrentContextRecordIds();
            if (currentIds != null) {
                Set<Id> processedIds = processedIdsByHandler.get(handlerKey);
                if (processedIds != null && processedIds.containsAll(currentIds)) { continue; }
                if (processedIds == null) {
                    processedIds = new Set<Id>();
                    processedIdsByHandler.put(handlerKey, processedIds);
                }
                processedIds.addAll(currentIds);
            }
            Type classType = Type.forName(handler.Class_Name__c);
            if(classType == null) { 
                System.debug(LoggingLevel.WARN, 'Trigger_Handler__mdt references unknown Apex class: ' + handler.Class_Name__c);
                continue;
            }
            Object instance = classType.newInstance();
            if (!(instance instanceof TriggerHandlerInterface)) {
                System.debug(LoggingLevel.WARN, handler.Class_Name__c + ' does not implement TriggerHandlerInterface.');
                continue;
            }
            ((TriggerHandlerInterface) instance).execute();
        }
    }

    /**
     * Method to retrieve a list of trigger handler metadata records based on the specified object name, ensuring only active handlers are selected and ordered by their defined order.
     * @param objectName the api name of the SObject.
     * @return a List with the Trigger Handlers of the object.
     */
    private static List<Trigger_Handler__mdt> getTriggerHandlersByObjectName(String objectName) {
        return [
            SELECT After_Delete__c,
            	After_Insert__c,
            	After_Undelete__c,
            	After_Update__c,
            	Before_Delete__c,
            	Before_Insert__c,
            	Before_Update__c,
                Class_Name__c,
                Is_Active__c, 
                Object__c, 
                Order__c
            FROM Trigger_Handler__mdt 
            WHERE Is_Active__c = TRUE 
            AND Object__c = :objectName 
            ORDER BY Order__c ASC
        ];
    }

    /**
     * Method to retrieve a mock list of trigger handler metadata records for testing purposes.
     * @return a List with the Trigger Handlers records for testing purposes.
     */
    private static List<Trigger_Handler__mdt> getMockDataTriggerHandler() {
        return new List<Trigger_Handler__mdt>{
            new Trigger_Handler__mdt(
                MasterLabel = 'Test Handler',
                Class_Name__c = 'MockTriggerHandler',
                Is_Active__c = true,
                Object__c = 'Account',
                Order__c = 1,
                Before_Insert__c = true,
                After_Insert__c = true,
                Before_Update__c = true,
                After_Update__c = true,
                Before_Delete__c = true,
                After_Delete__c = true,
                After_Undelete__c = true
            )
        };
    }

    /**
     * Determines whether a given trigger handler should execute in the current trigger context.
     * @param triggerHandler The Trigger_Handler__mdt metadata record representing the handler configuration.
     * @return true if the handler should execute for the current trigger operation, otherwise false.
     */
    private static Boolean matchesCurrentContext(Trigger_Handler__mdt triggerHandler) {
        System.TriggerOperation triggerOperationType = Trigger.operationType;
        switch on triggerOperationType {
            when BEFORE_INSERT  { return triggerHandler.Before_Insert__c; }
            when BEFORE_UPDATE  { return triggerHandler.Before_Update__c; }
            when BEFORE_DELETE  { return triggerHandler.Before_Delete__c; }
            when AFTER_INSERT   { return triggerHandler.After_Insert__c; }
            when AFTER_UPDATE   { return triggerHandler.After_Update__c; }
            when AFTER_DELETE   { return triggerHandler.After_Delete__c; }
            when AFTER_UNDELETE { return triggerHandler.After_Undelete__c; }
        }
        return false;
    }

    /**
     * Retrieves the Ids of the records in the current trigger context, when available.
     * @return the Ids from Trigger.newMap or Trigger.oldMap, or null when the current context
     * has no records with an assigned Id yet (e.g. before insert).
     */
    private static Set<Id> getCurrentContextRecordIds() {
        if (Trigger.newMap != null) { return Trigger.newMap.keySet(); }
        if (Trigger.oldMap != null) { return Trigger.oldMap.keySet(); }
        return null;
    }
}