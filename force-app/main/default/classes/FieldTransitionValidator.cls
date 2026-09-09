/**
 * File Name   :	FieldTransitionValidator.cls
 * Description :	Blocks a field from changing to a configured value until all of that transition's
 *                  active conditions are met. Call from a trigger handler's beforeUpdate hook. Bulk-safe:
 *                  child-object lookups run once per distinct condition for the whole batch, not once
 *                  per record, so this scales to any batch size without hitting the SOQL query limit.
 **/
public inherited sharing class FieldTransitionValidator {

    /**
     * Validates a batch of records against every active Field_Transition_Rule__mdt for their object.
     * A rule whose Field_API_Name__c no longer exists on the object is skipped and logged rather than
     * thrown, so a stale rule can't block every save of that object.
     * @param newRecords The records being saved.
     * @param oldMap The previous version of each record, keyed by Id. Pass null if there's no old state (e.g. insert).
     */
    public static void validateTransitions(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        if (newRecords == null || newRecords.isEmpty()) { return; }
        String objectApiName = newRecords[0].getSObjectType().getDescribe().getName();
        List<Field_Transition_Rule__mdt> rules = FieldTransitionMetadataService.getActiveRulesForObject(objectApiName);
        if (rules.isEmpty()) { return; }

        Set<Id> ruleIds = new Set<Id>();
        for (Field_Transition_Rule__mdt rule : rules) { ruleIds.add(rule.Id); }
        Map<Id, List<Transition_Condition__mdt>> conditionsByRuleId = FieldTransitionMetadataService.getActiveConditionsByRuleId(ruleIds);

        Map<Id, List<SObject>> matchingRecordsByRuleId = groupMatchingRecordsByRule(newRecords, oldMap, rules);
        if (matchingRecordsByRuleId.isEmpty()) { return; }

        FieldTransitionConditionEvaluator.BulkContext context = buildBulkContext(matchingRecordsByRuleId, conditionsByRuleId);

        for (Field_Transition_Rule__mdt rule : rules) {
            List<SObject> matchingRecords = matchingRecordsByRuleId.get(rule.Id);
            List<Transition_Condition__mdt> conditions = conditionsByRuleId.get(rule.Id);
            if (matchingRecords == null || conditions == null || conditions.isEmpty()) { continue; }
            for (SObject record : matchingRecords) {
                if (!allConditionsSatisfied(rule, conditions, record, context)) {
                    record.addError(buildErrorMessage(rule));
                }
            }
        }
    }

    /**
     * Single-record convenience overload of validateTransitions.
     * @param newRecord The record being saved.
     * @param oldRecord The previous version of the record. Pass null if there's no old state.
     */
    public static void validateTransitions(SObject newRecord, SObject oldRecord) {
        Map<Id, SObject> oldMap = oldRecord != null ? new Map<Id, SObject>{ newRecord.Id => oldRecord } : null;
        validateTransitions(new List<SObject>{ newRecord }, oldMap);
    }

    /**
     * Groups the records that match each rule's transition, so conditions only need to be prefetched
     * and evaluated for the records that actually need them.
     * @param newRecords The records being saved.
     * @param oldMap The previous version of each record, keyed by Id. Can be null.
     * @param rules Active rules for the records' object.
     * @return matching records, keyed by the Id of the rule they match.
     */
    private static Map<Id, List<SObject>> groupMatchingRecordsByRule(List<SObject> newRecords, Map<Id, SObject> oldMap, List<Field_Transition_Rule__mdt> rules) {
        Map<Id, List<SObject>> matchingRecordsByRuleId = new Map<Id, List<SObject>>();
        for (SObject newRecord : newRecords) {
            SObject oldRecord = oldMap != null ? oldMap.get((Id) newRecord.get('Id')) : null;
            for (Field_Transition_Rule__mdt rule : rules) {
                if (!matchesTransition(rule, newRecord, oldRecord)) { continue; }
                if (!matchingRecordsByRuleId.containsKey(rule.Id)) {
                    matchingRecordsByRuleId.put(rule.Id, new List<SObject>());
                }
                matchingRecordsByRuleId.get(rule.Id).add(newRecord);
            }
        }
        return matchingRecordsByRuleId;
    }

    /**
     * Prefetches every child-object lookup the matched records will need, one query per distinct
     * condition for the whole batch rather than one per (condition, record) pair.
     * @param matchingRecordsByRuleId Records that matched each rule's transition, keyed by rule Id.
     * @param conditionsByRuleId Active conditions for each rule, keyed by rule Id.
     * @return a BulkContext ready to pass into FieldTransitionConditionEvaluator.evaluate.
     */
    private static FieldTransitionConditionEvaluator.BulkContext buildBulkContext(Map<Id, List<SObject>> matchingRecordsByRuleId, Map<Id, List<Transition_Condition__mdt>> conditionsByRuleId) {
        List<Transition_Condition__mdt> allConditions = new List<Transition_Condition__mdt>();
        Map<Id, Set<Id>> parentIdsByConditionId = new Map<Id, Set<Id>>();
        for (Id ruleId : matchingRecordsByRuleId.keySet()) {
            List<Transition_Condition__mdt> conditions = conditionsByRuleId.get(ruleId);
            if (conditions == null) { continue; }
            Set<Id> parentIds = new Set<Id>();
            for (SObject record : matchingRecordsByRuleId.get(ruleId)) { parentIds.add(record.Id); }
            for (Transition_Condition__mdt condition : conditions) {
                allConditions.add(condition);
                parentIdsByConditionId.put(condition.Id, parentIds);
            }
        }
        return FieldTransitionConditionEvaluator.prefetch(allConditions, parentIdsByConditionId);
    }

    /**
     * Checks whether a rule's watched field is changing to (and, if set, from) the values the rule cares
     * about. A rule whose Field_API_Name__c doesn't exist on the record can never really match a live
     * transition, so it's skipped and logged rather than thrown.
     * @param rule The rule to check.
     * @param newRecord The record's new (in-memory) state.
     * @param oldRecord The record's previous state. Can be null.
     * @return true if rule.Field_API_Name__c is changing to rule.To_Value__c (and, if set, from rule.From_Value__c).
     */
    private static Boolean matchesTransition(Field_Transition_Rule__mdt rule, SObject newRecord, SObject oldRecord) {
        String newValue;
        String oldValue;
        try {
            newValue = String.valueOf(newRecord.get(rule.Field_API_Name__c));
            oldValue = oldRecord != null ? String.valueOf(oldRecord.get(rule.Field_API_Name__c)) : null;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Field_Transition_Rule__mdt "' + rule.DeveloperName + '" references a field that does not exist on ' + newRecord.getSObjectType().getDescribe().getName() + ': "' + rule.Field_API_Name__c + '". Rule skipped. ' + ex.getMessage());
            return false;
        }
        if (newValue != rule.To_Value__c) { return false; }
        if (newValue == oldValue) { return false; }
        if (String.isNotBlank(rule.From_Value__c) && oldValue != rule.From_Value__c) { return false; }
        return true;
    }

    /**
     * Checks that every one of a rule's active conditions is satisfied. A condition that throws while
     * evaluating (e.g. an invalid Parent_Filter_Criteria__c field) is treated as not satisfied and
     * logged, so a misconfigured condition blocks only this record's transition, not the whole batch.
     * @param rule The rule the conditions belong to, for logging.
     * @param conditions The active conditions to check (all must pass).
     * @param record The record's new (in-memory) state.
     * @param context Child-object data prefetched by buildBulkContext.
     * @return true only if every condition is satisfied.
     */
    private static Boolean allConditionsSatisfied(Field_Transition_Rule__mdt rule, List<Transition_Condition__mdt> conditions, SObject record, FieldTransitionConditionEvaluator.BulkContext context) {
        for (Transition_Condition__mdt condition : conditions) {
            try {
                if (!FieldTransitionConditionEvaluator.evaluate(condition, record, context)) { return false; }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Failed to evaluate Transition_Condition__mdt "' + condition.DeveloperName + '" for rule "' + rule.DeveloperName + '" on record ' + record.Id + ': ' + ex.getMessage());
                return false;
            }
        }
        return true;
    }

    /**
     * Builds the error shown to the user when a rule blocks a transition.
     * @param rule The rule that blocked the transition.
     * @return the Field_Transition_Blocked_Error custom label, with {0}/{1} filled in.
     */
    private static String buildErrorMessage(Field_Transition_Rule__mdt rule) {
        return String.format(Label.Field_Transition_Blocked_Error, new List<Object>{ rule.Field_API_Name__c, rule.To_Value__c });
    }
}
