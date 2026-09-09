/**
 * File Name   :	FieldTransitionRequirementService.cls
 * Description :	Reports, per governed field on a record, which reachable transitions exist and which
 *                  of their conditions are already satisfied. Read-only — unlike FieldTransitionValidator,
 *                  it never blocks a save. Built for FieldTransitionRequirementController's LWC. A rule or
 *                  condition referencing a field that no longer exists is skipped/logged rather than
 *                  thrown, so one stale record doesn't take down the checklist for the whole object.
 **/
public inherited sharing class FieldTransitionRequirementService {

    /**
     * Builds the full requirement checklist for one record, grouped by the fields governed by active
     * Field_Transition_Rule__mdt records for that record's object.
     * @param recordId The record to check.
     * @return one FieldRequirementGroup per governed field that has a reachable transition from its current value.
     */
    public static List<FieldRequirementGroup> getPendingRequirements(Id recordId) {
        if (recordId == null) { return new List<FieldRequirementGroup>(); }
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        List<Field_Transition_Rule__mdt> rules = FieldTransitionMetadataService.getActiveRulesForObject(objectApiName);
        if (rules.isEmpty()) { return new List<FieldRequirementGroup>(); }

        Set<Id> ruleIds = new Set<Id>();
        for (Field_Transition_Rule__mdt rule : rules) { ruleIds.add(rule.Id); }
        Map<Id, List<Transition_Condition__mdt>> conditionsByRuleId = FieldTransitionMetadataService.getActiveConditionsByRuleId(ruleIds);
        SObject record = queryRecord(recordId, objectApiName, rules, conditionsByRuleId);

        return buildGroups(rules, conditionsByRuleId, record, objectApiName);
    }

    /**
     * Groups reachable transitions (and their evaluated conditions) by governed field, preserving each
     * field's first-seen order and each rule's Order__c order. A rule whose Field_API_Name__c wasn't
     * queryable (see queryRecord) is skipped and logged rather than thrown.
     * @param rules Active rules for the record's object.
     * @param conditionsByRuleId Active conditions for those rules, keyed by rule Id.
     * @param record The record, already loaded with every valid field the rules and conditions need.
     * @param objectApiName API name of the record's object, for field label lookups.
     * @return one FieldRequirementGroup per governed field with at least one reachable transition.
     */
    private static List<FieldRequirementGroup> buildGroups(List<Field_Transition_Rule__mdt> rules, Map<Id, List<Transition_Condition__mdt>> conditionsByRuleId, SObject record, String objectApiName) {
        Map<String, FieldRequirementGroup> groupsByField = new Map<String, FieldRequirementGroup>();
        List<String> fieldOrder = new List<String>();

        for (Field_Transition_Rule__mdt rule : rules) {
            String currentValue;
            try {
                currentValue = String.valueOf(record.get(rule.Field_API_Name__c));
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Field_Transition_Rule__mdt "' + rule.DeveloperName + '" references a field that does not exist: "' + rule.Field_API_Name__c + '". Rule skipped. ' + ex.getMessage());
                continue;
            }
            if (!isReachableFrom(rule, currentValue) || rule.To_Value__c == currentValue) { continue; }

            if (!groupsByField.containsKey(rule.Field_API_Name__c)) {
                groupsByField.put(rule.Field_API_Name__c, new FieldRequirementGroup(rule.Field_API_Name__c, getFieldLabel(objectApiName, rule.Field_API_Name__c), currentValue));
                fieldOrder.add(rule.Field_API_Name__c);
            }
            groupsByField.get(rule.Field_API_Name__c).transitions.add(buildTransitionRequirement(rule, conditionsByRuleId.get(rule.Id), record));
        }

        List<FieldRequirementGroup> groups = new List<FieldRequirementGroup>();
        for (String fieldApiName : fieldOrder) { groups.add(groupsByField.get(fieldApiName)); }
        return groups;
    }

    /**
     * Checks whether a rule's transition can be reached from the record's current field value.
     * @param rule The rule to check.
     * @param currentValue The field's current value.
     * @return true if rule.From_Value__c is blank (applies from any value) or equals currentValue.
     */
    private static Boolean isReachableFrom(Field_Transition_Rule__mdt rule, String currentValue) {
        return String.isBlank(rule.From_Value__c) || rule.From_Value__c == currentValue;
    }

    /**
     * Evaluates every active condition for one rule against the record, without blocking anything. A
     * condition that throws while evaluating (e.g. an invalid Parent_Filter_Criteria__c field) is shown
     * as not satisfied and logged, rather than breaking the checklist for every other condition.
     * @param rule The rule the transition belongs to.
     * @param conditions The rule's active conditions. Can be null.
     * @param record The record to evaluate against.
     * @return a TransitionRequirement listing each condition's pass/fail state.
     */
    private static TransitionRequirement buildTransitionRequirement(Field_Transition_Rule__mdt rule, List<Transition_Condition__mdt> conditions, SObject record) {
        String fromValue = String.isNotBlank(rule.From_Value__c) ? rule.From_Value__c : 'Any';
        TransitionRequirement transition = new TransitionRequirement(fromValue, rule.To_Value__c);
        if (conditions == null) { return transition; }
        for (Transition_Condition__mdt condition : conditions) {
            Boolean satisfied;
            try {
                satisfied = FieldTransitionConditionEvaluator.evaluate(condition, record);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Failed to evaluate Transition_Condition__mdt "' + condition.DeveloperName + '": ' + ex.getMessage());
                satisfied = false;
            }
            String message = String.isNotBlank(condition.Message__c) ? condition.Message__c : condition.MasterLabel;
            transition.conditions.add(new ConditionRequirement(message, condition.Condition_Type__c, satisfied));
            if (!satisfied) { transition.allSatisfied = false; }
        }
        return transition;
    }

    /**
     * Queries the record with exactly the fields the rules and their conditions need: each governed
     * field, plus every field referenced by a Parent_Filter_Criteria__c comparison. A field that no
     * longer exists on the object is skipped and logged rather than breaking the whole query.
     * @param recordId The record to query.
     * @param objectApiName API name of the record's object.
     * @param rules Active rules for that object.
     * @param conditionsByRuleId Active conditions for those rules, keyed by rule Id.
     * @return the record, loaded with every valid field the checklist needs to evaluate.
     */
    private static SObject queryRecord(Id recordId, String objectApiName, List<Field_Transition_Rule__mdt> rules, Map<Id, List<Transition_Condition__mdt>> conditionsByRuleId) {
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        Set<String> fieldNames = new Set<String>{ 'Id' };
        for (Field_Transition_Rule__mdt rule : rules) { addIfValidField(fieldNames, fieldMap, rule.Field_API_Name__c); }
        for (List<Transition_Condition__mdt> conditions : conditionsByRuleId.values()) {
            for (Transition_Condition__mdt condition : conditions) {
                String parentField = FieldTransitionConditionEvaluator.extractParentCriteriaFieldName(condition.Parent_Filter_Criteria__c);
                if (parentField != null) { addIfValidField(fieldNames, fieldMap, parentField); }
            }
        }
        String query = 'SELECT ' + String.join(new List<String>(fieldNames), ', ') + ' FROM ' + objectApiName + ' WHERE Id = :recordId LIMIT 1';
        return Database.query(query);
    }

    /**
     * Adds fieldName to fieldNames only if it's a real field on the object, logging a warning otherwise.
     * @param fieldNames The set being built up for the dynamic SELECT.
     * @param fieldMap The object's field describe map.
     * @param fieldName The field API name to check.
     */
    private static void addIfValidField(Set<String> fieldNames, Map<String, Schema.SObjectField> fieldMap, String fieldName) {
        if (String.isBlank(fieldName)) { return; }
        if (fieldMap.containsKey(fieldName.toLowerCase())) {
            fieldNames.add(fieldName);
        } else {
            System.debug(LoggingLevel.ERROR, 'Field "' + fieldName + '" does not exist and will be skipped in the transition checklist.');
        }
    }

    /**
     * @param objectApiName API name of the object that defines the field.
     * @param fieldApiName API name of the field to look up.
     * @return the field's display label, or its API name if the field can't be described.
     */
    private static String getFieldLabel(String objectApiName, String fieldApiName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        Schema.SObjectField field = objectType == null ? null : objectType.getDescribe().fields.getMap().get(fieldApiName);
        return field != null ? field.getDescribe().getLabel() : fieldApiName;
    }

    /**
     * All of a record's reachable transitions for one governed field.
     */
    public class FieldRequirementGroup {
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public String currentValue;
        @AuraEnabled public List<TransitionRequirement> transitions = new List<TransitionRequirement>();

        FieldRequirementGroup(String fieldApiName, String fieldLabel, String currentValue) {
            this.fieldApiName = fieldApiName;
            this.fieldLabel = fieldLabel;
            this.currentValue = currentValue;
        }
    }

    /**
     * One reachable transition (rule) and the evaluated state of its conditions.
     */
    public class TransitionRequirement {
        @AuraEnabled public String fromValue;
        @AuraEnabled public String toValue;
        @AuraEnabled public Boolean allSatisfied = true;
        @AuraEnabled public List<ConditionRequirement> conditions = new List<ConditionRequirement>();

        TransitionRequirement(String fromValue, String toValue) {
            this.fromValue = fromValue;
            this.toValue = toValue;
        }
    }

    /**
     * One condition's evaluated pass/fail state, shown in the checklist as label (its Message__c, or
     * its record name if Message__c is blank).
     */
    public class ConditionRequirement {
        @AuraEnabled public String label;
        @AuraEnabled public String conditionType;
        @AuraEnabled public Boolean satisfied;

        ConditionRequirement(String label, String conditionType, Boolean satisfied) {
            this.label = label;
            this.conditionType = conditionType;
            this.satisfied = satisfied;
        }
    }
}
