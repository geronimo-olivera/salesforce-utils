@isTest
private class CollectionUtilsTest {

    private static final Id ACCOUNT_A = '001000000000001AAA';
    private static final Id ACCOUNT_B = '001000000000002AAA';
    private static final Id ACCOUNT_C = '001000000000003AAA';

    private static Opportunity opp(Integer sequence, Id accountId, String stage, Decimal amount) {
        return new Opportunity(
            Id = Id.valueOf('006' + String.valueOf(sequence).leftPad(12, '0') + 'AAA'),
            Name = 'Opp ' + sequence,
            AccountId = accountId,
            StageName = stage,
            Amount = amount
        );
    }

    @isTest
    static void testExtractingIds() {
        List<SObject> opps = new List<SObject>{
            opp(1, ACCOUNT_A, 'Prospecting', 10),
            opp(2, ACCOUNT_A, 'Prospecting', 20),
            opp(3, ACCOUNT_B, 'Closed Won', 30),
            opp(4, null, 'Closed Won', null),
            new Opportunity(Name = 'not inserted yet'),
            null
        };

        Assert.areEqual(4, CollectionUtils.getIds(opps).size(), 'records without an Id and null entries are skipped');
        Assert.areEqual(new Set<Id>{ ACCOUNT_A, ACCOUNT_B }, CollectionUtils.getIds(opps, Opportunity.AccountId), 'lookup values are distinct and empty ones are skipped');
        Assert.isTrue(CollectionUtils.getIds((List<SObject>) null).isEmpty(), 'null list gives no Ids');
        Assert.isTrue(CollectionUtils.getIds((List<SObject>) null, Opportunity.AccountId).isEmpty(), 'null list gives no field Ids');

        Integer rejected = 0;
        try { CollectionUtils.getIds(opps, Opportunity.StageName); } catch (StringException ex) { rejected++; }
        Assert.areEqual(1, rejected, 'text that is not an Id is rejected');
    }

    @isTest
    static void testExtractingStringsDecimalsAndDates() {
        List<SObject> opps = new List<SObject>{
            opp(1, ACCOUNT_A, 'Prospecting', 100),
            opp(2, ACCOUNT_A, 'Prospecting', 100),
            opp(3, ACCOUNT_B, '  ', 250),
            opp(4, ACCOUNT_B, null, null),
            null
        };
        List<SObject> accounts = new List<SObject>{ new Account(Name = 'A', NumberOfEmployees = 10), new Account(Name = 'B', NumberOfEmployees = 5) };

        Assert.areEqual(new Set<String>{ 'Prospecting' }, CollectionUtils.getStrings(opps, Opportunity.StageName), 'distinct, blank values skipped');
        Assert.areEqual(2, CollectionUtils.getStrings(opps, Opportunity.Amount).size(), 'numbers are converted to text');
        Assert.areEqual(2, CollectionUtils.getDecimals(opps, Opportunity.Amount).size(), 'distinct non-null amounts');
        Assert.isTrue(CollectionUtils.getDecimals(accounts, Account.NumberOfEmployees).contains(10), 'integer fields are read as decimals');

        List<SObject> dated = new List<SObject>{
            new Opportunity(CloseDate = Date.newInstance(2026, 1, 15)),
            new Opportunity(CloseDate = Date.newInstance(2026, 1, 15)),
            new Opportunity(CloseDate = Date.newInstance(2026, 2, 20)),
            new Opportunity(Name = 'no date')
        };
        Assert.areEqual(2, CollectionUtils.getDates(dated, Opportunity.CloseDate).size(), 'distinct non-null dates');

        List<SObject> events = new List<SObject>{ new Event(ActivityDateTime = Datetime.newInstance(2026, 3, 1, 10, 0, 0)) };
        Assert.isTrue(CollectionUtils.getDates(events, Event.ActivityDateTime).contains(Date.newInstance(2026, 3, 1)), 'a date/time is reduced to its date');

        Assert.isTrue(CollectionUtils.getStrings(null, Opportunity.StageName).isEmpty(), 'null list gives no strings');
        Assert.isTrue(CollectionUtils.getDecimals(null, Opportunity.Amount).isEmpty(), 'null list gives no decimals');
        Assert.isTrue(CollectionUtils.getDates(null, Opportunity.CloseDate).isEmpty(), 'null list gives no dates');

        Integer rejected = 0;
        try { CollectionUtils.getDates(opps, Opportunity.StageName); } catch (TypeException ex) { rejected++; }
        try { CollectionUtils.getDecimals(opps, Opportunity.StageName); } catch (TypeException ex) { rejected++; }
        Assert.areEqual(2, rejected, 'a field of the wrong type is rejected');
    }

    @isTest
    static void testGroupingAndReadingGroups() {
        List<SObject> opps = new List<SObject>{
            opp(1, ACCOUNT_A, 'Prospecting', 10),
            opp(2, ACCOUNT_B, 'Closed Won', 20),
            opp(3, ACCOUNT_A, 'Prospecting', 30),
            opp(4, null, 'closed won', 40),
            opp(5, ACCOUNT_A, '  ', 50)
        };

        Map<Id, List<SObject>> byAccount = CollectionUtils.groupById(opps, Opportunity.AccountId);
        Assert.areEqual(2, byAccount.size(), 'records without an account are left out');
        Assert.areEqual(3, byAccount.get(ACCOUNT_A).size(), 'all of the first account\'s records are grouped');
        Assert.areEqual(opps[0].Id, byAccount.get(ACCOUNT_A)[0].Id, 'the original order is kept');
        Assert.areEqual(opps[4].Id, byAccount.get(ACCOUNT_A)[2].Id, 'the original order is kept to the end');

        Map<String, List<SObject>> byStage = CollectionUtils.groupByString(opps, Opportunity.StageName);
        Assert.areEqual(3, byStage.size(), 'blank stages are left out and keys are case-sensitive');
        Assert.areEqual(2, byStage.get('Prospecting').size(), 'records sharing a value are grouped');
        Assert.areEqual(1, byStage.get('closed won').size(), 'a different case is a different key');

        List<Opportunity> typed = (List<Opportunity>) CollectionUtils.getGroup(byAccount, ACCOUNT_A);
        Assert.areEqual('Opp 1', typed[0].Name, 'a group casts back to its concrete type');
        Assert.isTrue(CollectionUtils.getGroup(byAccount, ACCOUNT_C).isEmpty(), 'a missing key gives an empty list');
        Assert.isTrue(CollectionUtils.getGroup(byAccount, (Id) null).isEmpty(), 'a null key gives an empty list');
        Assert.isTrue(CollectionUtils.getGroup((Map<Id, List<SObject>>) null, ACCOUNT_A).isEmpty(), 'a null map gives an empty list');
        Assert.areEqual(2, CollectionUtils.getGroup(byStage, 'Prospecting').size(), 'a string group is read');
        Assert.isTrue(CollectionUtils.getGroup(byStage, 'Unknown').isEmpty(), 'a missing string key gives an empty list');
        Assert.isTrue(CollectionUtils.getGroup(byStage, (String) null).isEmpty(), 'a null string key gives an empty list');
        Assert.isTrue(CollectionUtils.getGroup((Map<String, List<SObject>>) null, 'Prospecting').isEmpty(), 'a null string map gives an empty list');

        Assert.isTrue(CollectionUtils.groupById(null, Opportunity.AccountId).isEmpty(), 'null list groups into nothing');
        Assert.isTrue(CollectionUtils.groupByString(null, Opportunity.StageName).isEmpty(), 'null list groups into nothing by string');
    }

    @isTest
    static void testIndexing() {
        List<SObject> opps = new List<SObject>{
            opp(1, ACCOUNT_A, 'Prospecting', 10),
            opp(2, ACCOUNT_A, 'Prospecting', 20),
            opp(3, ACCOUNT_B, 'Closed Won', 30),
            opp(4, null, 'Closed Won', 40),
            new Opportunity(Name = ' '),
            null
        };

        Map<Id, SObject> byAccount = CollectionUtils.indexById(opps, Opportunity.AccountId);
        Assert.areEqual(2, byAccount.size(), 'one entry per distinct account');
        Assert.areEqual(opps[1].Id, byAccount.get(ACCOUNT_A).Id, 'the last record wins on a repeated value');

        Map<String, SObject> byName = CollectionUtils.indexByString(opps, Opportunity.Name);
        Assert.areEqual(4, byName.size(), 'blank names and null entries are left out');
        Assert.areEqual(opps[2].Id, byName.get('Opp 3').Id, 'a record is found by its text value');

        Assert.isTrue(CollectionUtils.indexById(null, Opportunity.AccountId).isEmpty(), 'null list indexes into nothing');
        Assert.isTrue(CollectionUtils.indexByString(null, Opportunity.Name).isEmpty(), 'null list indexes into nothing by string');
    }

    @isTest
    static void testFiltering() {
        List<SObject> opps = new List<SObject>{
            opp(1, ACCOUNT_A, 'Prospecting', 100),
            opp(2, ACCOUNT_B, 'prospecting', 200),
            opp(3, ACCOUNT_A, 'Closed Won', 300),
            opp(4, null, 'Closed Lost', null),
            null
        };

        Assert.areEqual(1, CollectionUtils.filterByValue(opps, Opportunity.StageName, 'Prospecting').size(), 'text matches case-sensitively');
        Assert.areEqual(1, CollectionUtils.filterByValue(opps, Opportunity.Amount, 100).size(), 'a number matches whatever numeric type is passed');
        Assert.areEqual(1, CollectionUtils.filterByValue(opps, Opportunity.Amount, null).size(), 'null matches an empty field and never a null entry');
        Assert.isTrue(CollectionUtils.filterByValue(null, Opportunity.Amount, 100).isEmpty(), 'null list matches nothing');

        List<SObject> closed = CollectionUtils.filterByAnyValue(opps, Opportunity.StageName, new List<Object>{ 'Closed Won', 'Closed Lost' });
        Assert.areEqual(2, closed.size(), 'a record matches if its value is any of the allowed ones');
        Assert.isTrue(CollectionUtils.filterByAnyValue(opps, Opportunity.StageName, new List<Object>()).isEmpty(), 'no allowed values matches nothing');
        Assert.isTrue(CollectionUtils.filterByAnyValue(opps, Opportunity.StageName, null).isEmpty(), 'null allowed values matches nothing');
        Assert.isTrue(CollectionUtils.filterByAnyValue(null, Opportunity.StageName, new List<Object>{ 'x' }).isEmpty(), 'null list matches nothing');

        Assert.areEqual(2, CollectionUtils.filterByIdIn(opps, Opportunity.AccountId, new Set<Id>{ ACCOUNT_A }).size(), 'records whose lookup is in the set');
        Assert.isTrue(CollectionUtils.filterByIdIn(opps, Opportunity.AccountId, new Set<Id>()).isEmpty(), 'empty set matches nothing');
        Assert.isTrue(CollectionUtils.filterByIdIn(opps, Opportunity.AccountId, null).isEmpty(), 'null set matches nothing');
        Assert.isTrue(CollectionUtils.filterByIdIn(null, Opportunity.AccountId, new Set<Id>{ ACCOUNT_A }).isEmpty(), 'null list matches nothing');

        Assert.areEqual(3, CollectionUtils.filterWithValue(opps, Opportunity.Amount).size(), 'records with a value');
        Assert.areEqual(1, CollectionUtils.filterWithoutValue(opps, Opportunity.Amount).size(), 'records without a value, never a null entry');
        Assert.isTrue(CollectionUtils.filterWithValue(null, Opportunity.Amount).isEmpty(), 'null list has nothing with a value');
        Assert.isTrue(CollectionUtils.filterWithoutValue(null, Opportunity.Amount).isEmpty(), 'null list has nothing without a value');
    }

    @isTest
    static void testDetectingChanges() {
        Opportunity oldA = opp(1, ACCOUNT_A, 'Prospecting', 100);
        Opportunity newA = opp(1, ACCOUNT_A, 'Closed Won', 100);
        Opportunity oldB = opp(2, ACCOUNT_B, 'Prospecting', 50);
        Opportunity newB = opp(2, ACCOUNT_B, 'Prospecting', 75);
        Opportunity oldC = opp(3, ACCOUNT_B, 'Prospecting', 10);
        Opportunity newC = opp(3, ACCOUNT_B, 'Closed Won', 20);
        Opportunity oldD = opp(4, ACCOUNT_B, 'Closed Won', 5);
        Opportunity newD = opp(4, ACCOUNT_B, 'Closed Won', 5);
        Opportunity oldE = opp(5, ACCOUNT_B, 'Closed Won', 1);
        Opportunity newE = opp(5, ACCOUNT_B, 'closed won', 1);
        List<SObject> newList = new List<SObject>{ newA, newB, newC, newD, newE };
        Map<Id, SObject> oldMap = new Map<Id, SObject>(new List<SObject>{ oldA, oldB, oldC, oldD, oldE });

        Assert.isFalse(CollectionUtils.hasChanged(null, oldA, Opportunity.StageName), 'no record means no change');
        Assert.isTrue(CollectionUtils.hasChanged(newA, null, Opportunity.StageName), 'on insert a populated field counts as changed');
        Assert.isFalse(CollectionUtils.hasChanged(new Opportunity(), null, Opportunity.StageName), 'on insert an empty field does not');
        Assert.isTrue(CollectionUtils.hasChanged(newA, oldA, Opportunity.StageName), 'a different value is a change');
        Assert.isFalse(CollectionUtils.hasChanged(newA, oldA, Opportunity.Amount), 'the same value is not');
        Assert.isTrue(CollectionUtils.hasChanged(newE, oldE, Opportunity.StageName), 'a change of case only is a change');

        Assert.areEqual(3, CollectionUtils.getChanged(newList, oldMap, Opportunity.StageName).size(), 'three records changed stage');
        Assert.areEqual(2, CollectionUtils.getChanged(newList, oldMap, Opportunity.Amount).size(), 'two records changed amount');
        Assert.areEqual(5, CollectionUtils.getChanged(newList, null, Opportunity.StageName).size(), 'with no old map every populated record counts as changed');
        Assert.areEqual(4, CollectionUtils.getChanged(newList, new Map<Id, Opportunity>(new List<Opportunity>{ oldA, oldB, oldC }), Opportunity.Amount).size(), 'a typed old map is accepted and records missing from it count as inserts');
        Assert.areEqual(1, CollectionUtils.getChanged(new List<SObject>{ new Opportunity(StageName = 'New') }, oldMap, Opportunity.StageName).size(), 'a record without an Id counts as an insert');
        Assert.isTrue(CollectionUtils.getChanged(null, oldMap, Opportunity.StageName).isEmpty(), 'null list has no changes');

        List<SObject> movedToWon = CollectionUtils.getChangedTo(newList, oldMap, Opportunity.StageName, 'Closed Won');
        Assert.areEqual(2, movedToWon.size(), 'only records that changed to the value count, not those already at it');
        Assert.areEqual(3, CollectionUtils.getChangedTo(newList, null, Opportunity.StageName, 'Closed Won').size(), 'on insert every record at the value counts');
        Assert.isTrue(CollectionUtils.getChangedTo(null, oldMap, Opportunity.StageName, 'Closed Won').isEmpty(), 'null list has no changes');

        List<SObject> anyChanged = CollectionUtils.getChangedAny(newList, oldMap, new List<SObjectField>{ Opportunity.StageName, Opportunity.Amount });
        Assert.areEqual(4, anyChanged.size(), 'a record that changed in both fields is listed once');
        Assert.isTrue(CollectionUtils.getChangedAny(newList, oldMap, new List<SObjectField>()).isEmpty(), 'no fields matches nothing');
        Assert.isTrue(CollectionUtils.getChangedAny(newList, oldMap, null).isEmpty(), 'null fields matches nothing');
        Assert.isTrue(CollectionUtils.getChangedAny(null, oldMap, new List<SObjectField>{ Opportunity.Amount }).isEmpty(), 'null list has no changes');
    }

    @isTest
    static void testNumericAggregates() {
        List<SObject> opps = new List<SObject>{
            opp(1, ACCOUNT_A, 'Prospecting', 100),
            opp(2, ACCOUNT_A, 'Prospecting', 50),
            opp(3, ACCOUNT_B, 'Prospecting', 25),
            opp(4, ACCOUNT_B, 'Prospecting', null),
            opp(5, ACCOUNT_C, 'Prospecting', null),
            opp(6, null, 'Prospecting', 1000),
            null
        };
        List<SObject> accounts = new List<SObject>{ new Account(Name = 'A', NumberOfEmployees = 10), new Account(Name = 'B', NumberOfEmployees = 5) };

        Assert.areEqual(1175, CollectionUtils.sum(opps, Opportunity.Amount), 'null values count as zero');
        Assert.areEqual(0, CollectionUtils.sum(null, Opportunity.Amount), 'null list sums to zero');
        Assert.areEqual(15, CollectionUtils.sum(accounts, Account.NumberOfEmployees), 'integer fields are summed');
        Assert.areEqual(25, CollectionUtils.min(opps, Opportunity.Amount), 'smallest value');
        Assert.areEqual(1000, CollectionUtils.max(opps, Opportunity.Amount), 'largest value');
        Assert.areEqual(5, CollectionUtils.min(accounts, Account.NumberOfEmployees), 'smallest integer');
        Assert.areEqual(10, CollectionUtils.max(accounts, Account.NumberOfEmployees), 'largest integer');
        Assert.isNull(CollectionUtils.min(null, Opportunity.Amount), 'null list has no minimum');
        Assert.isNull(CollectionUtils.max(null, Opportunity.Amount), 'null list has no maximum');
        Assert.isNull(CollectionUtils.min(new List<SObject>{ opp(7, ACCOUNT_A, 'x', null) }, Opportunity.Amount), 'no values means no minimum');
        Assert.isNull(CollectionUtils.max(new List<SObject>{ opp(7, ACCOUNT_A, 'x', null) }, Opportunity.Amount), 'no values means no maximum');

        Map<Id, Decimal> totals = CollectionUtils.sumGroupedById(opps, Opportunity.AccountId, Opportunity.Amount);
        Assert.areEqual(3, totals.size(), 'records without a parent are left out');
        Assert.areEqual(150, totals.get(ACCOUNT_A), 'a parent\'s records are added up');
        Assert.areEqual(25, totals.get(ACCOUNT_B), 'null amounts add nothing');
        Assert.areEqual(0, totals.get(ACCOUNT_C), 'a parent whose amounts are all null still appears with zero');
        Assert.isTrue(CollectionUtils.sumGroupedById(null, Opportunity.AccountId, Opportunity.Amount).isEmpty(), 'null list has no totals');

        Integer rejected = 0;
        try { CollectionUtils.sum(opps, Opportunity.StageName); } catch (TypeException ex) { rejected++; }
        try { CollectionUtils.min(opps, Opportunity.StageName); } catch (TypeException ex) { rejected++; }
        try { CollectionUtils.max(opps, Opportunity.StageName); } catch (TypeException ex) { rejected++; }
        try { CollectionUtils.sumGroupedById(opps, Opportunity.AccountId, Opportunity.StageName); } catch (TypeException ex) { rejected++; }
        Assert.areEqual(4, rejected, 'a non-numeric field is rejected by every numeric method');
    }

    @isTest
    static void testPartitioning() {
        List<SObject> five = new List<SObject>{
            opp(1, ACCOUNT_A, 'x', 1), opp(2, ACCOUNT_A, 'x', 2), opp(3, ACCOUNT_A, 'x', 3), opp(4, ACCOUNT_A, 'x', 4), opp(5, ACCOUNT_A, 'x', 5)
        };

        List<List<SObject>> chunks = CollectionUtils.partition(five, 2);
        Assert.areEqual(3, chunks.size(), 'five records in chunks of two');
        Assert.areEqual(2, chunks[0].size(), 'the first chunk is full');
        Assert.areEqual(1, chunks[2].size(), 'the last chunk holds the remainder');
        Assert.areEqual(five[4].Id, chunks[2][0].Id, 'the original order is kept');
        Assert.areEqual(2, CollectionUtils.partition(new List<SObject>{ five[0], five[1], five[2], five[3] }, 2).size(), 'an exact multiple leaves no empty chunk');
        Assert.areEqual(1, CollectionUtils.partition(five, 5).size(), 'a size equal to the list is one chunk');
        Assert.areEqual(1, CollectionUtils.partition(five, 10).size(), 'a size larger than the list is one chunk');
        Assert.areEqual(5, CollectionUtils.partition(five, 1).size(), 'a size of one gives one chunk per record');
        Assert.isTrue(CollectionUtils.partition((List<SObject>) null, 2).isEmpty(), 'null list has no chunks');
        Assert.isTrue(CollectionUtils.partition(new List<SObject>(), 2).isEmpty(), 'empty list has no chunks');

        List<List<Id>> idChunks = CollectionUtils.partition(new List<Id>{ ACCOUNT_A, ACCOUNT_B, ACCOUNT_C }, 2);
        Assert.areEqual(2, idChunks.size(), 'Ids are chunked');
        Assert.areEqual(1, idChunks[1].size(), 'the Id remainder is last');
        Assert.isTrue(CollectionUtils.partition((List<Id>) null, 2).isEmpty(), 'null Ids have no chunks');

        List<List<String>> stringChunks = CollectionUtils.partition(new List<String>{ 'a', 'b', 'c' }, 2);
        Assert.areEqual(2, stringChunks.size(), 'Strings are chunked');
        Assert.areEqual('c', stringChunks[1][0], 'the String remainder is last');
        Assert.isTrue(CollectionUtils.partition((List<String>) null, 2).isEmpty(), 'null Strings have no chunks');

        Integer rejected = 0;
        for (Integer invalidSize : new List<Integer>{ 0, -1, null }) {
            try { CollectionUtils.partition(five, invalidSize); } catch (CollectionUtils.CollectionUtilsException ex) { rejected++; }
            try { CollectionUtils.partition(new List<Id>{ ACCOUNT_A }, invalidSize); } catch (CollectionUtils.CollectionUtilsException ex) { rejected++; }
            try { CollectionUtils.partition(new List<String>{ 'a' }, invalidSize); } catch (CollectionUtils.CollectionUtilsException ex) { rejected++; }
        }
        Assert.areEqual(9, rejected, 'every overload rejects a size below one');
    }
}
