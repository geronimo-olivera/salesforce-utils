@isTest
private class FieldTransitionFrameworkTest {

    @isTest
    static void testConditionEvaluator_ScalarFieldTypesAndNullHandling() {
        Transition_Condition__mdt c;

        Opportunity opp = new Opportunity(Name = 'Acme Corp', Type = 'New Customer', Probability = 75, Amount = 12345.67, IsPrivate = true, CloseDate = Date.today(), OwnerId = UserInfo.getUserId());
        c = mdt('Parent Field Criteria', 'Name = \'Acme Corp\'');
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'string =');
        c.Parent_Filter_Criteria__c = 'Name LIKE \'Acme%\'';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'string LIKE');
        c.Parent_Filter_Criteria__c = 'Name != \'Other\'';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'string !=');
        c.Parent_Filter_Criteria__c = 'Type IN (\'New Customer\', \'Existing Customer - Upgrade\')';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'picklist IN');
        c.Parent_Filter_Criteria__c = 'Type NOT IN (\'Existing Customer - Upgrade\')';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'picklist NOT IN');
        c.Parent_Filter_Criteria__c = 'Probability >= 75';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'percent >=');
        c.Parent_Filter_Criteria__c = 'Amount > 10000';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'currency >');
        c.Parent_Filter_Criteria__c = 'Amount = 12345.67';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'currency exact decimal =');
        c.Parent_Filter_Criteria__c = 'IsPrivate = true';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'boolean =');
        c.Parent_Filter_Criteria__c = 'CloseDate = TODAY';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'date literal TODAY');
        c.Parent_Filter_Criteria__c = 'CloseDate = ' + Date.today();
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'date absolute');
        c.Parent_Filter_Criteria__c = 'OwnerId = \'' + UserInfo.getUserId() + '\'';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, opp), 'lookup/reference =');

        Datetime gmtInstant = Datetime.newInstanceGmt(2026, 1, 1, 9, 0, 0);
        Event ev = new Event(StartDateTime = gmtInstant, DurationInMinutes = 30);
        c.Parent_Filter_Criteria__c = 'StartDateTime = 2026-01-01T09:00:00Z';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, ev), 'datetime with explicit UTC Z matches the GMT instant');
        c.Parent_Filter_Criteria__c = 'StartDateTime = 2026-01-01 09:00:00';
        Assert.isFalse(FieldTransitionConditionEvaluator.evaluate(c, ev), 'the same literal without Z is local time, a different instant');
        c.Parent_Filter_Criteria__c = 'DurationInMinutes >= 15';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, ev), 'integer >=');
        c.Parent_Filter_Criteria__c = 'DurationInMinutes < 60';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, ev), 'integer <');

        Opportunity oppNull = new Opportunity(Amount = null, LeadSource = null);
        c.Parent_Filter_Criteria__c = 'Amount = null';
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(c, oppNull), '= null on a null field');
        c.Parent_Filter_Criteria__c = 'Amount != null';
        Assert.isFalse(FieldTransitionConditionEvaluator.evaluate(c, oppNull), '!= null on a null field');
        c.Parent_Filter_Criteria__c = 'Amount > 100';
        Assert.isFalse(FieldTransitionConditionEvaluator.evaluate(c, oppNull), '> on a null field never satisfies');
        c.Parent_Filter_Criteria__c = 'LeadSource NOT IN (\'Purchased List\')';
        Assert.isFalse(FieldTransitionConditionEvaluator.evaluate(c, oppNull), 'NOT IN on a null field never satisfies, same convention as every other operator');

        c.Parent_Filter_Criteria__c = 'not a valid criteria string';
        try {
            FieldTransitionConditionEvaluator.evaluate(c, opp);
            Assert.fail('malformed criteria should throw');
        } catch (FieldTransitionConditionEvaluator.FieldTransitionValidatorException ex) {
            Assert.isTrue(ex.getMessage().contains('Invalid'), 'malformed criteria error message');
        }
    }

    @isTest
    static void testConditionEvaluator_ChildConditionTypesAndBulkIsolation() {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 5; i++) {
            opps.add(new Opportunity(Name = 'Child Cond Opp ' + i, StageName = 'Prospecting', CloseDate = Date.today().addDays(30)));
        }
        insert opps;
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) { contacts.add(new Contact(LastName = 'Child Cond Contact ' + i)); }
        insert contacts;

        List<OpportunityContactRole> ocrs = new List<OpportunityContactRole>{
            new OpportunityContactRole(OpportunityId = opps[0].Id, ContactId = contacts[0].Id, Role = 'Decision Maker', IsPrimary = true),
            new OpportunityContactRole(OpportunityId = opps[1].Id, ContactId = contacts[1].Id, Role = 'Decision Maker', IsPrimary = false),
            new OpportunityContactRole(OpportunityId = opps[3].Id, ContactId = contacts[3].Id, Role = 'Business User', IsPrimary = true),
            new OpportunityContactRole(OpportunityId = opps[4].Id, ContactId = contacts[4].Id, Role = 'Decision Maker', IsPrimary = true),
            new OpportunityContactRole(OpportunityId = opps[4].Id, ContactId = contacts[0].Id, Role = 'Decision Maker', IsPrimary = false)
        };
        insert ocrs;

        Transition_Condition__mdt existsCond = mdt('Child Record Exists', null);
        existsCond.Child_Object_API_Name__c = 'OpportunityContactRole';
        existsCond.Child_Relationship_Field__c = 'OpportunityId';
        existsCond.Child_Filter_Criteria__c = 'Role = \'Decision Maker\'';

        Transition_Condition__mdt allSatisfyCond = mdt('All Matching Children Satisfy', null);
        allSatisfyCond.Child_Object_API_Name__c = 'OpportunityContactRole';
        allSatisfyCond.Child_Relationship_Field__c = 'OpportunityId';
        allSatisfyCond.Child_Filter_Criteria__c = 'Role = \'Decision Maker\'';
        allSatisfyCond.Child_Required_Criteria__c = 'IsPrimary = true';

        Set<Id> allParentIds = new Set<Id>();
        for (Opportunity o : opps) { allParentIds.add(o.Id); }

        Test.startTest();
        FieldTransitionConditionEvaluator.BulkContext existsCtx = FieldTransitionConditionEvaluator.prefetch(
            new List<Transition_Condition__mdt>{ existsCond }, new Map<Id, Set<Id>>{ existsCond.Id => allParentIds });
        FieldTransitionConditionEvaluator.BulkContext allSatisfyCtx = FieldTransitionConditionEvaluator.prefetch(
            new List<Transition_Condition__mdt>{ allSatisfyCond }, new Map<Id, Set<Id>>{ allSatisfyCond.Id => allParentIds });

        Boolean[] expectedExists = new Boolean[]{ true, true, false, false, true };
        Boolean[] expectedAllSatisfy = new Boolean[]{ true, false, true, true, false };
        for (Integer i = 0; i < 5; i++) {
            Assert.areEqual(expectedExists[i], FieldTransitionConditionEvaluator.evaluate(existsCond, opps[i], existsCtx), 'Child Record Exists for opp ' + i);
            Assert.areEqual(expectedAllSatisfy[i], FieldTransitionConditionEvaluator.evaluate(allSatisfyCond, opps[i], allSatisfyCtx), 'All Matching Children Satisfy for opp ' + i);
        }

        Transition_Condition__mdt ifExistsCond = mdt('Parent Criteria If Child Exists', 'Amount != null');
        ifExistsCond.Child_Object_API_Name__c = 'OpportunityContactRole';
        ifExistsCond.Child_Relationship_Field__c = 'OpportunityId';
        ifExistsCond.Child_Filter_Criteria__c = 'Role = \'Decision Maker\'';
        opps[0].Amount = 5000;
        FieldTransitionConditionEvaluator.BulkContext ifExistsCtx = FieldTransitionConditionEvaluator.prefetch(
            new List<Transition_Condition__mdt>{ ifExistsCond }, new Map<Id, Set<Id>>{ ifExistsCond.Id => allParentIds });
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(ifExistsCond, opps[0], ifExistsCtx), 'has a Decision Maker and Amount is set');
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(ifExistsCond, opps[2], ifExistsCtx), 'no Decision Maker at all is vacuously true');
        Assert.isFalse(FieldTransitionConditionEvaluator.evaluate(ifExistsCond, opps[1], ifExistsCtx), 'has a Decision Maker but Amount is blank');

        Set<Id> fakeManyIds = new Set<Id>();
        for (Integer i = 0; i < 60; i++) { fakeManyIds.add(opps[0].Id); }
        Integer queriesBefore = Limits.getQueries();
        FieldTransitionConditionEvaluator.BulkContext scaleCtx = FieldTransitionConditionEvaluator.prefetch(
            new List<Transition_Condition__mdt>{ existsCond }, new Map<Id, Set<Id>>{ existsCond.Id => fakeManyIds });
        for (Integer i = 0; i < 60; i++) { FieldTransitionConditionEvaluator.evaluate(existsCond, opps[0], scaleCtx); }
        Assert.areEqual(1, Limits.getQueries() - queriesBefore, 'one prefetch plus 60 evaluate calls against the same condition costs exactly one query');

        Transition_Condition__mdt fakeBad = mdt('Child Record Exists', null);
        fakeBad.Child_Object_API_Name__c = 'NoSuchObject__x';
        fakeBad.Child_Relationship_Field__c = 'X__c';
        Transition_Condition__mdt realCond = [SELECT Id, DeveloperName, Condition_Type__c, Child_Object_API_Name__c, Child_Relationship_Field__c, Child_Filter_Criteria__c FROM Transition_Condition__mdt WHERE DeveloperName = 'Contact_Role_Decision_Maker_Exists' LIMIT 1];
        Set<Id> singleId = new Set<Id>{ opps[0].Id };
        FieldTransitionConditionEvaluator.BulkContext mixedCtx = FieldTransitionConditionEvaluator.prefetch(
            new List<Transition_Condition__mdt>{ realCond, fakeBad },
            new Map<Id, Set<Id>>{ realCond.Id => singleId, fakeBad.Id => singleId });
        Assert.isTrue(FieldTransitionConditionEvaluator.evaluate(realCond, opps[0], mixedCtx), 'a real condition is unaffected by a bad condition sharing the same batch');
        Assert.isFalse(FieldTransitionConditionEvaluator.evaluate(fakeBad, opps[0], mixedCtx), 'the bad condition itself fails closed instead of throwing');
        Test.stopTest();
    }

    @isTest
    static void testValidator_MatchesTransitionEdgeCases() {
        Opportunity sameValueNew = new Opportunity(Id = fakeId(Opportunity.SObjectType, 1), StageName = 'Prospecting');
        Opportunity sameValueOld = new Opportunity(Id = sameValueNew.Id, StageName = 'Prospecting');
        FieldTransitionValidator.validateTransitions(sameValueNew, sameValueOld);
        Assert.isFalse(sameValueNew.hasErrors(), 'setting a field to its own current value is a no-op, not a transition');

        Opportunity wrongFromNew = new Opportunity(Id = fakeId(Opportunity.SObjectType, 2), StageName = 'Needs Analysis');
        Opportunity wrongFromOld = new Opportunity(Id = wrongFromNew.Id, StageName = 'Qualification');
        FieldTransitionValidator.validateTransitions(wrongFromNew, wrongFromOld);
        Assert.isFalse(wrongFromNew.hasErrors(), 'Qualification to Needs Analysis does not match a rule scoped to From_Value__c = Prospecting');

        Opportunity matchingNew = new Opportunity(Id = fakeId(Opportunity.SObjectType, 3), StageName = 'Needs Analysis');
        Opportunity matchingOld = new Opportunity(Id = matchingNew.Id, StageName = 'Prospecting');
        Test.startTest();
        FieldTransitionValidator.validateTransitions(matchingNew, matchingOld);
        Test.stopTest();
        Assert.isTrue(matchingNew.hasErrors(), 'Prospecting to Needs Analysis matches the live rule, and no condition is satisfied on a blank record');

        Opportunity bulkMatch = new Opportunity(Id = fakeId(Opportunity.SObjectType, 4), StageName = 'Needs Analysis');
        Opportunity bulkMatchOld = new Opportunity(Id = bulkMatch.Id, StageName = 'Prospecting');
        Opportunity bulkSkip = new Opportunity(Id = fakeId(Opportunity.SObjectType, 5), StageName = 'Qualification');
        Opportunity bulkSkipOld = new Opportunity(Id = bulkSkip.Id, StageName = 'Prospecting');
        FieldTransitionValidator.validateTransitions(
            new List<SObject>{ bulkMatch, bulkSkip },
            new Map<Id, SObject>{ bulkMatch.Id => bulkMatchOld, bulkSkip.Id => bulkSkipOld });
        Assert.isTrue(bulkMatch.hasErrors(), 'bulk overload blocks the same way the single-record one does');
        Assert.isFalse(bulkSkip.hasErrors(), 'bulk overload correctly separates records that do and do not match a rule in the same batch');
    }

    @isTest
    static void testValidator_EndToEndBulkBlocksAndAllowsWithFewQueries() {
        Integer total = 40;
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < total; i++) {
            opps.add(new Opportunity(Name = 'E2E Opp ' + i, StageName = 'Prospecting', CloseDate = Date.today().addDays(30)));
        }
        insert opps;

        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < total; i++) { contacts.add(new Contact(LastName = 'E2E Contact ' + i)); }
        insert contacts;

        List<OpportunityContactRole> ocrs = new List<OpportunityContactRole>();
        for (Integer i = 0; i < 20; i++) {
            ocrs.add(new OpportunityContactRole(OpportunityId = opps[i].Id, ContactId = contacts[i].Id, Role = 'Decision Maker', IsPrimary = true));
            ocrs.add(new OpportunityContactRole(OpportunityId = opps[i].Id, ContactId = contacts[Math.mod(i + 1, total)].Id, Role = 'Business User', IsPrimary = false));
        }
        insert ocrs;

        Map<Id, SObject> oldStatesByid = new Map<Id, SObject>();
        for (Opportunity o : opps) { oldStatesByid.put(o.Id, o.clone(true, false, false, false)); }
        for (Integer i = 0; i < total; i++) {
            opps[i].StageName = 'Needs Analysis';
            if (i < 20) {
                opps[i].Amount = 5000;
                opps[i].TrackingNumber__c = 'TRK-' + i;
            }
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        FieldTransitionValidator.validateTransitions(opps, oldStatesByid);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Integer blockedCount = 0;
        for (Integer i = 0; i < total; i++) {
            if (i < 20) {
                Assert.isFalse(opps[i].hasErrors(), 'the fully-qualified first half should not be blocked, index ' + i);
            } else {
                blockedCount++;
                Assert.isTrue(opps[i].hasErrors(), 'the unqualified second half should be blocked, index ' + i);
                Assert.isTrue(opps[i].getErrors()[0].getMessage().contains('Cannot set'), 'blocked records get the configured error message');
            }
        }
        Assert.areEqual(20, blockedCount, 'exactly the unqualified half should be blocked');
        Assert.isTrue(queriesUsed < 20, 'bulk validation of ' + total + ' records stays well under the 100 SOQL query limit: used ' + queriesUsed);
    }

    @isTest
    static void testRequirementService_ChecklistShapeAcrossObjects() {
        Opportunity opp = new Opportunity(Name = 'Checklist Opp', StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;

        Test.startTest();
        List<FieldTransitionRequirementService.FieldRequirementGroup> groups = FieldTransitionRequirementService.getPendingRequirements(opp.Id);
        Test.stopTest();

        Assert.areEqual(1, groups.size(), 'Opportunity has exactly one governed field configured, StageName');
        FieldTransitionRequirementService.FieldRequirementGroup requirementGroup = groups[0];
        Assert.areEqual('StageName', requirementGroup.fieldApiName, 'field api name');
        Assert.areEqual('Prospecting', requirementGroup.currentValue, 'current value reflects the real record');
        Assert.isTrue(requirementGroup.transitions.size() > 0, 'at least the Prospecting to Needs Analysis transition is reachable');

        FieldTransitionRequirementService.TransitionRequirement transition = requirementGroup.transitions[0];
        Assert.areEqual('Prospecting', transition.fromValue, 'fromValue comes from the rule');
        Assert.areEqual('Needs Analysis', transition.toValue, 'toValue comes from the rule');
        Assert.isFalse(transition.allSatisfied, 'a brand new Opportunity has not met every condition yet');
        Assert.isTrue(transition.conditions.size() > 0, 'the transition lists its conditions');
        Boolean anyUnsatisfied = false;
        for (FieldTransitionRequirementService.ConditionRequirement condition : transition.conditions) {
            Assert.isNotNull(condition.label, 'every condition has a label');
            if (!condition.satisfied) { anyUnsatisfied = true; }
        }
        Assert.isTrue(anyUnsatisfied, 'at least one condition is unmet on a blank Opportunity');

        Assert.isTrue(FieldTransitionRequirementService.getPendingRequirements(fakeId(Account.SObjectType, 1)).isEmpty(), 'an object with no configured rules returns an empty checklist without needing a real record');
        Assert.isTrue(FieldTransitionRequirementService.getPendingRequirements(null).isEmpty(), 'a null recordId returns an empty checklist');
    }

    @isTest
    static void testController_DelegatesToServiceForRecordPage() {
        Opportunity opp = new Opportunity(Name = 'Controller Opp', StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;

        Test.startTest();
        List<FieldTransitionRequirementService.FieldRequirementGroup> fromController = FieldTransitionRequirementController.getPendingRequirements(opp.Id);
        List<FieldTransitionRequirementService.FieldRequirementGroup> fromService = FieldTransitionRequirementService.getPendingRequirements(opp.Id);
        Test.stopTest();

        Assert.areEqual(fromService.size(), fromController.size(), 'controller returns the same number of groups as the service');
        Assert.areEqual(fromService[0].fieldApiName, fromController[0].fieldApiName, 'same governed field');
        Assert.areEqual(fromService[0].transitions.size(), fromController[0].transitions.size(), 'same number of transitions');
        Assert.areEqual(fromService[0].transitions[0].conditions.size(), fromController[0].transitions[0].conditions.size(), 'same number of conditions');
    }

    private static Transition_Condition__mdt mdt(String conditionType, String parentFilterCriteria) {
        return new Transition_Condition__mdt(
            DeveloperName = 'Test_Condition',
            Condition_Type__c = conditionType,
            Parent_Filter_Criteria__c = parentFilterCriteria
        );
    }

    private static Id fakeId(Schema.SObjectType sObjType, Integer sequence) {
        return Id.valueOf(sObjType.getDescribe().getKeyPrefix() + String.valueOf(sequence).leftPad(12, '0'));
    }
}
