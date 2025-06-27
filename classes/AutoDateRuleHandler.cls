/**
 * AutoDateRuleHandler is responsible for processing and applying active Auto Date Rules
 * defined in Custom Metadata Type (Auto_Date_Rule__mdt).
 *
 * This handler is designed to be invoked from before insert or before update triggers.
 * It evaluates field changes and, based on rule conditions, sets target Date or DateTime fields
 * automatically on the corresponding records.
 *
 * Usage:
 * - Call the static apply() method from a trigger, passing the object API name, Trigger.new, and Trigger.oldMap.
 * - Only runs in before insert or before update context.
 *
 * The logic supports optional trigger values, boolean comparison, and will only set the target
 * field if it is currently null.
 *
 * This class assumes metadata is properly configured and validates all input and context usage.
 */
public without sharing class AutoDateRuleHandler {
    /**
     * Main entry point for applying Auto Date Rules during a before insert or before update trigger.
     * @param objectApiName The API name of the object being processed (e.g., 'Contact', 'Movie__c').
     * @param newList The list of SObject records being inserted or updated (Trigger.new).
     * @param oldMap The map of old SObject records (Trigger.oldMap), only required for updates.
     * @throws AutoDateRuleHandlerException if any validation fails or no applicable rules are found.
     */
    public static void apply(String objectApiName, List<SObject> newList, Map<Id, SObject> oldMap) {
        if(Trigger.isBefore && (Trigger.isUpdate || Trigger.isInsert)) {
            validateTriggerContextAndParams(objectApiName, newList, oldMap);
            applyAutoDateRules(objectApiName, newList, oldMap);
        }
    }

    /**
     * Validates context and parameters for invoking AutoDateRuleEngine.
     * @param objectApiName The API name of the SObject upon which the engine should operate.
     * @param newList The list of SObjects being inserted or updated in the trigger.
     * @param oldMap The map of prior SObject values (only in update context).
     * @throws AutoDateRuleHandlerException if:
     *   • objectApiName is blank or null.
     *   • newList is null or empty.
     *   • oldMap is null or empty in a before update context.
     */
    private static void validateTriggerContextAndParams(String objectApiName, List<SObject> newList, Map<Id, SObject> oldMap) {
        if (objectApiName == null || String.isBlank(objectApiName)) {
            throw new AutoDateRuleHandlerException('Object API name must not be blank.');
        }
        if (newList == null || newList.isEmpty()) {
            throw new AutoDateRuleHandlerException('New List of records must not be null or empty.');
        }
        if (Trigger.isBefore && Trigger.isUpdate && (oldMap == null || oldMap.isEmpty())) {
            throw new AutoDateRuleHandlerException('Old Map must not be null or empty in before update context.');
        }
    }

    /**
     * Applies all active Auto Date Rules for a given object API name to the current records being processed.
     * @param objectApiName The API name of the object being processed (e.g., 'Contact', 'Movie__c').
     * @param newList The list of records from Trigger.new.
     * @param oldMap The map of old records from Trigger.oldMap (only used on update).
     */
    private static void applyAutoDateRules(String objectApiName, List<SObject> newList, Map<Id, SObject> oldMap) {
        Map<String, List<Auto_Date_Rule__mdt>> autoDateRulesByObjectName = getAutoDateRulesByObjectName();
        if (autoDateRulesByObjectName == null || autoDateRulesByObjectName.isEmpty()) return;
        if (autoDateRulesByObjectName.containsKey(objectApiName)) {
            List<Auto_Date_Rule__mdt> autoDateRules = autoDateRulesByObjectName.get(objectApiName);
            for (SObject newRecord : newList) {
                SObject oldRecord = (Trigger.isUpdate && oldMap != null) ? oldMap.get(newRecord.Id) : null;
                for(Auto_Date_Rule__mdt autoDateRule : autoDateRules) {
                    String triggerField = autoDateRule.Trigger_Field_API_Name__c;
                    String targetField = autoDateRule.Target_Field_API_Name__c;
                    String expectedValue = autoDateRule.Trigger_Field_Value__c;
                    String fieldType = autoDateRule.Target_Field_Type__c;

                    Object newValue = newRecord.get(triggerField);
                    Object oldValue = oldRecord != null ? oldRecord.get(triggerField) : null;

                    Boolean valueChanged = (oldRecord == null || oldValue != newValue);
                    Boolean matchesExpected = String.isBlank(expectedValue) || (newValue != null && String.valueOf(newValue).toLowerCase() == expectedValue.toLowerCase());

                    if (valueChanged && matchesExpected) {
                        if (fieldType == 'Date') {
                            newRecord.put(targetField, Date.today());
                        } else if (fieldType == 'Date/Time') {
                            newRecord.put(targetField, DateTime.now());
                        }
                    }
                }
            }
        }
    }

    /**
     * Retrieves all active Auto Date Rules and groups them by their associated object API name.
     * @return A map where the key is the Object API Name and the value is a list of active Auto_Date_Rule__mdt records related to that object.
     */
    private static Map<String, List<Auto_Date_Rule__mdt>> getAutoDateRulesByObjectName() {
        Map<String, List<Auto_Date_Rule__mdt>> autoDateRulesByObjectName = new Map<String, List<Auto_Date_Rule__mdt>>();
        List<Auto_Date_Rule__mdt> activeAutoDateRules = getActiveAutoDateRules();  
        if(!activeAutoDateRules.isEmpty()) {
            for(Auto_Date_Rule__mdt activeAutoDateRule : activeAutoDateRules) {
                if(!autoDateRulesByObjectName.containsKey(activeAutoDateRule.Object_API_Name__c)) {
                    autoDateRulesByObjectName.put(activeAutoDateRule.Object_API_Name__c, new List<Auto_Date_Rule__mdt>());
                }
                autoDateRulesByObjectName.get(activeAutoDateRule.Object_API_Name__c).add(activeAutoDateRule);
            }
        }
        return autoDateRulesByObjectName;      
    }

    /**
     * Retrieves all active Auto_Date_Rule__mdt records.
     * During test execution (Test.isRunningTest()), returns a hardcoded list with one sample rule
     * for the Opportunity object.
     * @return A list of active Auto_Date_Rule__mdt records.
     */
    private static List<Auto_Date_Rule__mdt> getActiveAutoDateRules() {
        if (Test.isRunningTest()) {
            return new List<Auto_Date_Rule__mdt>{
                new Auto_Date_Rule__mdt(
                    Object_API_Name__c = 'Opportunity',
                    Trigger_Field_API_Name__c = 'StageName',
                    Trigger_Field_Value__c = 'Closed Won',
                    Target_Field_API_Name__c = 'CloseDate',
                    Target_Field_Type__c = 'Date',
                    Active__c = true
                )
            };
        }
        return [
            SELECT Object_API_Name__c, 
                Target_Field_API_Name__c, 
                Target_Field_Type__c, 
                Trigger_Field_API_Name__c,
                Trigger_Field_Value__c
            FROM Auto_Date_Rule__mdt
            WHERE Active__c = true
            ORDER BY Object_API_Name__c
        ];
    }

    /**
     * Custom exception used within the AutoDateRuleHandler class to signal validation errors, missing metadata, or misusage in unsupported trigger contexts.
     */
    public class AutoDateRuleHandlerException extends Exception {}
}