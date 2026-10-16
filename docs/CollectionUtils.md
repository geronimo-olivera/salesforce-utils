# CollectionUtils

Static helpers for the collection work that repeats in every trigger handler and service: pull the Ids out of a list, group records by their parent, find the records whose field just changed to a value, add up an amount per account, split a list into chunks. Each of those is five to ten lines of loop and map-building that otherwise gets rewritten, slightly differently, in every class.

Everything here is pure logic: no queries, no DML, no setup. It reads fields off the records you hand it and returns plain collections.

## Contents

- `force-app/main/default/classes/CollectionUtils.cls` — the helpers themselves.
- `force-app/main/default/classes/CollectionUtilsTest.cls` — its test class, 100% code coverage with 8 test methods and no DML (see [Testing](#testing)).

## How it works

Apex has no lambdas and no generics, so there's no way to write `records.map(r -> r.AccountId)`. Instead, every method that looks at a field takes the field itself as a token:

```apex
Set<Id> accountIds = CollectionUtils.getIds(opportunities, Opportunity.AccountId);
```

`Opportunity.AccountId` is checked when the class compiles. A typo is a compile error, and renaming or deleting the field shows up as one, instead of surfacing as a runtime failure the first time that code path runs. Passing the field as a String (`'AccountId'`) isn't supported, on purpose.

A few conventions hold across every method:

- **Null-safe.** A `null` list or map gives back an empty collection (or `null` for `min`/`max`, `0` for `sum`), never an exception. `null` entries inside a list are skipped.
- **Order is kept.** Anything that returns a list keeps the original order.
- **Empty fields are left out.** When grouping, indexing, or extracting, a record whose field is `null` (or blank text) is skipped rather than collected under a `null` key.
- **Typed by the field, not the list.** Methods return `List<SObject>`, so cast where you use it: `(List<Opportunity>) CollectionUtils.getGroup(...)`. The cast works because the list holds the real records.
- **The field has to be on the record.** Records from a SOQL query or `Trigger.new` only carry the fields that were selected; reading any other one throws Salesforce's own `SObjectException`. Records built in memory (`new Opportunity(...)`) read unset fields as `null`.

## Reference

### Extracting

| Method | Returns | What it does |
|---|---|---|
| `getIds(records)` | `Set<Id>` | The records' own Ids. Records without an Id yet (before insert) are skipped. |
| `getIds(records, field)` | `Set<Id>` | The distinct values of a lookup or Id-valued field, e.g. every `AccountId`. |
| `getStrings(records, field)` | `Set<String>` | The distinct non-blank values as text. Numbers and picklists are converted. |
| `getDecimals(records, field)` | `Set<Decimal>` | The distinct values of a Number, Currency, or Percent field. |
| `getDates(records, field)` | `Set<Date>` | The distinct dates of a Date or Date/Time field. A Date/Time is reduced to its date in the running user's time zone. |

### Grouping and indexing

| Method | Returns | What it does |
|---|---|---|
| `groupById(records, field)` | `Map<Id, List<SObject>>` | Records grouped by an Id-valued field, e.g. Opportunities by `AccountId`. |
| `groupByString(records, field)` | `Map<String, List<SObject>>` | Records grouped by a field's value as text, e.g. Accounts by `Industry`. Keys are case-sensitive. |
| `getGroup(grouped, key)` | `List<SObject>` | One group out of either of the two results above. Returns an empty list instead of `null` for a missing key. |
| `indexById(records, field)` | `Map<Id, SObject>` | One record per value of an Id-valued field. On a repeated value the last record wins. |
| `indexByString(records, field)` | `Map<String, SObject>` | One record per value of a text field, e.g. Contacts by `Email`. On a repeated value the last record wins. |

`indexBy*` is for a field that's unique in practice. If two records can share a value, use `groupBy*` — otherwise one of them is silently dropped.

### Filtering

| Method | What it keeps |
|---|---|
| `filterByValue(records, field, expected)` | Records whose field equals `expected`. Text matches case-sensitively. `null` matches empty fields. |
| `filterByAnyValue(records, field, allowed)` | Records whose field equals any value in a `List<Object>`. |
| `filterByIdIn(records, field, ids)` | Records whose Id-valued field is in a `Set<Id>`. |
| `filterWithValue(records, field)` | Records where the field is populated (not null, not blank text). |
| `filterWithoutValue(records, field)` | The opposite: records where the field is empty. |

Numbers compare by value whatever numeric type you pass, so `filterByValue(opps, Opportunity.Amount, 100)` matches an Amount of `100.00`.

### Detecting changes

These are written for trigger code, where you have `Trigger.new` and `Trigger.oldMap` (or any list of new records and a map of their previous versions).

| Method | What it does |
|---|---|
| `hasChanged(newRecord, oldRecord, field)` | Whether one record's field differs from its previous version. |
| `getChanged(newRecords, oldMap, field)` | The records whose field changed. |
| `getChangedTo(newRecords, oldMap, field, value)` | The records whose field changed **and** now equals `value`. A record already at that value before the update doesn't count. |
| `getChangedAny(newRecords, oldMap, fields)` | The records where at least one of several fields changed. Each record is listed once. |

Two behaviors worth knowing:

- **Inserts.** With no previous version (`oldMap` is `null`, or the record isn't in it), a field counts as changed when it has a value. That makes the same handler code work for both insert and update.
- **Text is compared case-sensitively.** A change from `'acme'` to `'ACME'` counts as a change. Apex's plain `==` on Strings would say they're equal and miss it.

A typed map such as `Map<Id, Opportunity>` is accepted wherever a `Map<Id, SObject>` is asked for.

### Numbers

| Method | Returns | What it does |
|---|---|---|
| `sum(records, field)` | `Decimal` | The total of a numeric field. Nulls count as zero; `0` for a null or empty list. |
| `min(records, field)` | `Decimal` | The smallest value, or `null` if no record has one. |
| `max(records, field)` | `Decimal` | The largest value, or `null` if no record has one. |
| `sumGroupedById(records, groupField, valueField)` | `Map<Id, Decimal>` | The total of `valueField` per value of `groupField` — the shape of a rollup, e.g. total Amount per `AccountId`. A parent whose values are all null still appears, with `0`. |

Integer, Long, Double, Decimal, Currency, and Percent fields all work.

### Splitting

| Method | Returns | What it does |
|---|---|---|
| `partition(records, size)` | `List<List<SObject>>` | Consecutive chunks of at most `size`; every chunk is full except possibly the last. |
| `partition(ids, size)` | `List<List<Id>>` | Same, for a `List<Id>`. |
| `partition(values, size)` | `List<List<String>>` | Same, for a `List<String>`. |

A `size` below 1 (or `null`) throws a `CollectionUtils.CollectionUtilsException`.

## Basic usage

### The Ids of a list, and of a lookup

```apex
Set<Id> opportunityIds = CollectionUtils.getIds(opportunities);
Set<Id> accountIds = CollectionUtils.getIds(opportunities, Opportunity.AccountId);
```

### Group children under their parent

```apex
Map<Id, List<SObject>> contactsByAccount = CollectionUtils.groupById(contacts, Contact.AccountId);

for (Account acc : accounts) {
    List<Contact> accountContacts = (List<Contact>) CollectionUtils.getGroup(contactsByAccount, acc.Id);
    System.debug(acc.Name + ': ' + accountContacts.size() + ' contacts');
}
```

`getGroup` is what keeps this loop from throwing on an account with no contacts — a plain `contactsByAccount.get(acc.Id)` returns `null` there, and the loop over it fails.

### Look a record up by something other than its Id

```apex
Map<String, SObject> contactByEmail = CollectionUtils.indexByString(existingContacts, Contact.Email);
Contact match = (Contact) contactByEmail.get(incomingEmail);
```

### Pick out the records you care about

```apex
List<Opportunity> closed = (List<Opportunity>) CollectionUtils.filterByAnyValue(
    opportunities,
    Opportunity.StageName,
    new List<Object>{ 'Closed Won', 'Closed Lost' }
);

List<Opportunity> missingAmount = (List<Opportunity>) CollectionUtils.filterWithoutValue(opportunities, Opportunity.Amount);
```

### React to a field change in a trigger

```apex
List<SObject> justWon = CollectionUtils.getChangedTo(newList, oldMap, Opportunity.StageName, 'Closed Won');
if (justWon.isEmpty()) { return; }
```

### Totals

```apex
Decimal total = CollectionUtils.sum(opportunities, Opportunity.Amount);
Decimal largest = CollectionUtils.max(opportunities, Opportunity.Amount);
```

### Split a big list

```apex
for (List<Id> chunk : CollectionUtils.partition(new List<Id>(accountIds), 200)) {
    System.enqueueJob(new AccountRefreshQueueable(chunk));
}
```

## Complete example

Combines most of it: when opportunities move to Closed Won, work out each affected account's new won total, notify only the accounts that crossed a threshold, and hand the rest of the work to Queueables in chunks. Illustrative — `OpportunityWonHandler`, `Total_Won_Amount__c`, and `AccountRefreshQueueable` aren't part of this repo, only `CollectionUtils` is.

```apex
public class OpportunityWonHandler extends TriggerHandler {

    private static final Decimal VIP_THRESHOLD = 1000000;
    private static final Integer JOB_SIZE = 200;

    protected override void afterUpdate(List<SObject> newList, Map<Id, SObject> oldMap) {
        List<SObject> justWon = CollectionUtils.getChangedTo(newList, oldMap, Opportunity.StageName, 'Closed Won');
        justWon = CollectionUtils.filterWithValue(justWon, Opportunity.AccountId);
        if (justWon.isEmpty()) { return; }

        Set<Id> accountIds = CollectionUtils.getIds(justWon, Opportunity.AccountId);

        List<Opportunity> allWon = [
            SELECT AccountId, Amount
            FROM Opportunity
            WHERE AccountId IN :accountIds AND StageName = 'Closed Won'
        ];
        Map<Id, Decimal> wonByAccount = CollectionUtils.sumGroupedById(allWon, Opportunity.AccountId, Opportunity.Amount);

        List<Account> toUpdate = new List<Account>();
        Set<Id> newVips = new Set<Id>();
        for (Id accountId : accountIds) {
            Decimal total = wonByAccount.containsKey(accountId) ? wonByAccount.get(accountId) : 0;
            toUpdate.add(new Account(Id = accountId, Total_Won_Amount__c = total));
            if (total >= VIP_THRESHOLD) { newVips.add(accountId); }
        }
        update toUpdate;

        for (List<Id> chunk : CollectionUtils.partition(new List<Id>(newVips), JOB_SIZE)) {
            System.enqueueJob(new AccountRefreshQueueable(chunk));
        }
    }
}
```

What the helpers replaced: the `Trigger.new`/`oldMap` comparison loop (`getChangedTo`), the null-account guard (`filterWithValue`), the `Set<Id>` building loop (`getIds`), the per-account `Map<Id, Decimal>` accumulation (`sumGroupedById`), and the manual chunking counter (`partition`). The `[SELECT ...]` is still yours: this class never touches the database.

## Errors

Only three kinds of exception come out of this class, and both mean the call was wrong for the data, not that something transient failed:

| Exception | When |
|---|---|
| `System.TypeException` | A numeric method (`sum`, `min`, `max`, `getDecimals`, `sumGroupedById`) was pointed at a non-numeric field, or `getDates` at a field that's neither a Date nor a Date/Time. |
| `System.StringException` | An Id-valued method (`getIds(records, field)`, `groupById`, `indexById`, `filterByIdIn`, `sumGroupedById`'s group field) was pointed at a text field whose value isn't a valid Id. |
| `CollectionUtils.CollectionUtilsException` | `partition` was given a size below 1 or `null`. |

Plus Salesforce's own `SObjectException` when a field wasn't queried — see [How it works](#how-it-works).

## What you should NOT do

- Don't expect a typed result. Every list comes back as `List<SObject>`; cast it where you use it.
- Don't use `indexById` or `indexByString` on a field that can repeat — the last record silently overwrites the earlier ones. Use `groupById` or `groupByString`.
- Don't use `groupById` and expect records with an empty field to turn up under a `null` key. They're left out. Use `filterWithoutValue` to find them.
- Don't read a group with `map.get(key)` and iterate it. A missing key gives `null`. Use `getGroup`.
- Don't use `getChanged` or `getChangedTo` outside a before/after update, or where you don't have the previous versions, and expect "no change" — with no previous version every populated field counts as changed. That's the right behavior on insert and the wrong one if you simply forgot to pass the old map.
- Don't compare text for equality with `==` in your own code when case matters. `==` on Strings ignores case; these helpers don't.
- Don't pass a field you didn't select in your SOQL. Salesforce throws `SObjectException` on the read.

## Testing

`CollectionUtilsTest` deploys and runs at **100% code coverage** with 8 test methods and no additional mock or helper classes. It builds `Opportunity`, `Account`, and `Event` records in memory with made-up Ids, so there's no DML and no dependency on any data or setup in the org. It covers every method, including the `null`/empty/blank handling of each, the case-sensitive comparisons, insert-versus-update behavior in the change detectors, the numeric edge cases (all-null values, an Integer field, a non-numeric field), the chunking boundaries, and the exceptions listed under [Errors](#errors).
