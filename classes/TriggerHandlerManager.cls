/**
 * File Name   :	TriggerHandlerManager.cls
 * Description :	Manager for selecting and executing the appropriate trigger handlers.
 **/
public class TriggerHandlerManager {
    /**
     * Method responsible for handling trigger execution logic.
     * @param objectName the api name of the SObject.
     */
    public static void handle(String objectName) {
        if(String.isBlank(objectName)) { return; }
        try {
            List<Trigger_Handler__mdt> triggerHandlers = Test.isRunningTest() ? getMockDataTriggerHandler() : getTriggerHandlersByObjectName(objectName);
            if (triggerHandlers.isEmpty()) { return; }
            for (Trigger_Handler__mdt handler : triggerHandlers) {
                if (!matchesCurrentContext(handler)) { continue; }
                Type classType = Type.forName(handler.Class_Name__c);
                if(classType == null) { continue;}
                TriggerHandlerInterface handlerInterface = (TriggerHandlerInterface) classType.newInstance();
                if (handlerInterface == null) { continue; }
                handlerInterface.execute();
            }
        } catch (Exception ex) {
            System.debug('Error Message: ' + ex.getMessage()+ ' \n' + 'StackTrace: ' + ex.getStackTraceString());
        }
    }

    /**
     * Method to retrieve a list of trigger handler metadata records based on the specified object name, ensuring only active handlers are selected and ordered by their defined order.
     * @param objectName the api name of the SObject.
     * @return a List with the Trigger Handlers of the object.
     */
    private static List<Trigger_Handler__mdt> getTriggerHandlersByObjectName(String objectName) {
        return [
            SELECT Class_Name__c,
            	Before_Insert__c,
            	Before_Update__c,
            	Before_Delete__c,
            	After_Insert__c,
            	After_Update__c,
            	After_Delete__c,
            	After_Undelete__c
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
                Order__c = 1
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
}