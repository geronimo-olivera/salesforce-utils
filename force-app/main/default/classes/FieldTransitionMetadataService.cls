/**
 * File Name   :	FieldTransitionMetadataService.cls
 * Description :	Read-only data access for Field_Transition_Rule__mdt and Transition_Condition__mdt.
 *                  No evaluation logic — just fetches and organizes the metadata for FieldTransitionValidator.
 **/
public inherited sharing class FieldTransitionMetadataService {

    /**
     * Fetches the active transition rules configured for one object.
     * @param objectApiName API name of the object to look up rules for.
     * @return active Field_Transition_Rule__mdt records for that object, ordered by Order__c.
     */
    public static List<Field_Transition_Rule__mdt> getActiveRulesForObject(String objectApiName) {
        return [
            SELECT Id,
                DeveloperName,
                Field_API_Name__c,
                From_Value__c,
                Is_Active__c,
                Object_API_Name__c,
                Order__c,
                To_Value__c
            FROM Field_Transition_Rule__mdt
            WHERE Is_Active__c = true
            AND Object_API_Name__c = :objectApiName
            ORDER BY Order__c ASC NULLS LAST
        ];
    }

    /**
     * Fetches the active conditions for a set of rules, grouped by rule.
     * @param ruleIds Ids of Field_Transition_Rule__mdt records to fetch conditions for.
     * @return active Transition_Condition__mdt records, grouped by their Field_Transition_Rule__c.
     */
    public static Map<Id, List<Transition_Condition__mdt>> getActiveConditionsByRuleId(Set<Id> ruleIds) {
        Map<Id, List<Transition_Condition__mdt>> conditionsByRuleId = new Map<Id, List<Transition_Condition__mdt>>();
        for (Transition_Condition__mdt condition : [
            SELECT Id,
                DeveloperName,
                MasterLabel,
                Message__c,
                Child_Filter_Criteria__c,
                Child_Object_API_Name__c,
                Child_Relationship_Field__c,
                Child_Required_Criteria__c,
                Condition_Type__c,
                Field_Transition_Rule__c,
                Parent_Filter_Criteria__c,
                Is_Active__c
            FROM Transition_Condition__mdt
            WHERE Is_Active__c = true
            AND Field_Transition_Rule__c IN :ruleIds
        ]) {
            if (!conditionsByRuleId.containsKey(condition.Field_Transition_Rule__c)) {
                conditionsByRuleId.put(condition.Field_Transition_Rule__c, new List<Transition_Condition__mdt>());
            }
            conditionsByRuleId.get(condition.Field_Transition_Rule__c).add(condition);
        }
        return conditionsByRuleId;
    }
}
