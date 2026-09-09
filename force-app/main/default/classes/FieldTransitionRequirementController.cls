/**
 * File Name   :	FieldTransitionRequirementController.cls
 * Description :	LWC-facing entry point for the field transition checklist. Delegates all logic to
 *                  FieldTransitionRequirementService.
 **/
public with sharing class FieldTransitionRequirementController {

    /**
     * Fetches the pending transition requirements for a record, for display in the checklist LWC.
     * @param recordId The record to check.
     * @return one FieldRequirementGroup per governed field with a reachable transition.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldTransitionRequirementService.FieldRequirementGroup> getPendingRequirements(Id recordId) {
        try {
            return FieldTransitionRequirementService.getPendingRequirements(recordId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }
}
