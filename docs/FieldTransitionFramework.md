# Field Transition Framework

A metadata-driven Apex framework that blocks a field from changing to a configured value until a set of configurable conditions are met — checks against the record itself, against related child records, or both. Ships with a Lightning web component that shows a record's outstanding requirements before you even try to save.

Standalone repo with the full project scaffold (deployable manifest, generated docs, etc.): [github.com/geronimo-olivera/Field-Transition-Framework](https://github.com/geronimo-olivera/Field-Transition-Framework).

## Purpose

- **Configuration over code** — which field, which transition, and which conditions block it live in `Field_Transition_Rule__mdt` and `Transition_Condition__mdt` records. Adding, disabling, or changing a requirement doesn't require touching Apex.
- **Works on any object and any field** — nothing in the framework is specific to any object. `Object_API_Name__c` and `Field_API_Name__c` are plain text.
- **Four ways to express a requirement** — a related child record must (or must not) exist, a field on the record itself must match a comparison, or a combination of both.
- **Bulk-safe** — validating a batch of records costs one query per distinct condition that batch actually needs, not one per record. A 500-record update doesn't come close to the governor limit.
- **A companion checklist, not just a blocker** — `fieldTransitionChecklist` is a Lightning web component you can drop on any record page. It shows every reachable next value for a governed field and which of its conditions are already met, before the user tries to save.

## Contents

- `force-app/main/default/classes/FieldTransitionValidator.cls` — call this from a trigger's `before update` to block a transition. Bulk-safe.
- `force-app/main/default/classes/FieldTransitionConditionEvaluator.cls` — evaluates a single condition against a record. Shared by the validator and the checklist service; has no idea which one is calling it.
- `force-app/main/default/classes/FieldTransitionMetadataService.cls` — read-only access to the two custom metadata types.
- `force-app/main/default/classes/FieldTransitionRequirementService.cls` — builds the read-only checklist (never blocks anything) for the LWC.
- `force-app/main/default/classes/FieldTransitionRequirementController.cls` — thin `@AuraEnabled` entry point the LWC calls.
- `force-app/main/default/classes/FieldTransitionFrameworkTest.cls` — test coverage. Doesn't cover everything — see [Tests](#tests) below.
- `force-app/main/default/lwc/fieldTransitionChecklist/` — drop this on a record page to show pending requirements.
- `force-app/main/default/objects/Field_Transition_Rule__mdt/` and `Transition_Condition__mdt/` — the two custom metadata types. Types, fields, and layouts only — no records. Your rules and conditions are your org's own configuration; see [Creating a rule](#creating-a-rule) below.

## Deploy to an org

You need [VS Code with the Salesforce Extension Pack](https://developer.salesforce.com/tools/vscode/) and an authenticated org.

1. Clone this repo and open it in VS Code.
2. Authenticate to your target org (`SFDX: Authorize an Org`, or `sf org login web` from the CLI).
3. Right-click [`manifest/package.xml`](../manifest/package.xml) and choose **SFDX: Deploy Source in Manifest to Org**.

That manifest covers every utility in this repo together, this one included — see the note at the bottom of the main [README](../README.md) if you'd rather deploy just this one.

## Custom metadata: `Field_Transition_Rule__mdt`

One record per governed transition (one field, one target value, optionally scoped to a specific starting value).

| Field | Type | Description |
|---|---|---|
| `Object_API_Name__c` | Text (required) | API name of the SObject this rule applies to, e.g. `Opportunity`. |
| `Field_API_Name__c` | Text (required) | API name of the field on that object this rule watches, e.g. `StageName`. |
| `To_Value__c` | Text (required) | The value the field must be changing **to** for this rule to apply. |
| `From_Value__c` | Text | The value the field must be changing **from**. Leave blank to match a transition from any value. |
| `Is_Active__c` | Checkbox | Must be `true` for the rule to be enforced at all. |
| `Order__c` | Number | Evaluation order relative to other active rules on the same object/field. Doesn't make rules mutually exclusive — see [Creating a rule](#creating-a-rule). |

## Custom metadata: `Transition_Condition__mdt`

One or more per rule. **Every** active condition on a rule must be satisfied for the transition to be allowed.

| Field | Type | Description |
|---|---|---|
| `Field_Transition_Rule__c` | Metadata Relationship (required) | The rule this condition belongs to. |
| `Condition_Type__c` | Picklist (required) | `Child Record Exists`, `All Matching Children Satisfy`, `Parent Field Criteria`, or `Parent Criteria If Child Exists`. See [Creating conditions](#creating-conditions) for what each one does. |
| `Child_Object_API_Name__c` | Text | API name of the child object to check. Used by every type except `Parent Field Criteria`. |
| `Child_Relationship_Field__c` | Text | API name of the lookup/master-detail field on the child that points back to the parent. Used by every type except `Parent Field Criteria`. |
| `Child_Filter_Criteria__c` | Long Text Area | A WHERE-clause fragment against the child object. Meaning depends on `Condition_Type__c`. |
| `Child_Required_Criteria__c` | Long Text Area | A WHERE-clause fragment every selected child must also match. Used only by `All Matching Children Satisfy`. |
| `Parent_Filter_Criteria__c` | Long Text Area | A single `Field Operator Value` comparison against the record being saved. Used by `Parent Field Criteria` and `Parent Criteria If Child Exists`. Full reference in [Parent Filter Criteria syntax](#parent-filter-criteria-syntax). |
| `Message__c` | Text | What to show for this condition in the checklist LWC, instead of the record's name. Falls back to the condition record's own label if blank. |
| `Is_Active__c` | Checkbox | Must be `true` for the condition to be enforced at all. |

## Wiring it into your org

This is the framework, not a trigger — whether you already have a trigger framework (like the [Trigger Handler Framework](TriggerHandlerFramework.md) elsewhere in this repo), want one trigger per object, or something else entirely is your call. Whatever you already have, call `FieldTransitionValidator.validateTransitions` from a `before update` context on the object(s) you're governing:

```apex
trigger OpportunityTrigger on Opportunity (before update) {
    FieldTransitionValidator.validateTransitions(Trigger.new, Trigger.oldMap);
}
```

There's also a single-record overload if you're calling it from somewhere that isn't natively bulk:

```apex
FieldTransitionValidator.validateTransitions(newOpportunity, oldOpportunity);
```

Only `before update` matters — an `insert` has no "from" value to compare, so a rule with a blank `From_Value__c` would otherwise fire on every insert that happens to land on `To_Value__c`, which isn't a transition at all.

## Creating a rule

Create rule and condition records either way CMDT records normally get created:

- **Setup UI** — Setup → Custom Metadata Types → **Field Transition Rule** / **Transition Condition** → Manage Records → New.
- **Source** — add a `.md-meta.xml` file under `force-app/main/default/customMetadata/` and deploy it. For example, `Field_Transition_Rule.Prospecting_to_Qualification.md-meta.xml`:

  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <CustomMetadata xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://soap.sforce.com/2006/04/metadata">
      <label>Prospecting to Qualification</label>
      <protected>false</protected>
      <values><field>Object_API_Name__c</field><value xsi:type="xsd:string">Opportunity</value></values>
      <values><field>Field_API_Name__c</field><value xsi:type="xsd:string">StageName</value></values>
      <values><field>From_Value__c</field><value xsi:type="xsd:string">Prospecting</value></values>
      <values><field>To_Value__c</field><value xsi:type="xsd:string">Qualification</value></values>
      <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
      <values><field>Order__c</field><value xsi:type="xsd:double">10</value></values>
  </CustomMetadata>
  ```

`Order__c` controls the order rules are evaluated in when more than one is active for the same object/field — it does **not** make rules mutually exclusive. If two active rules both match the same transition (e.g. one scoped to `From_Value__c = Prospecting` and another left blank so it matches from anywhere), both apply, and their conditions are effectively ANDed together — every matching rule has to pass independently, it isn't "first match wins."

A rule with no active conditions attached never blocks anything — it's allowed unconditionally the moment it matches.

## Creating conditions

Each condition belongs to one rule (`Field_Transition_Rule__c`) and has a `Condition_Type__c` that determines which of the other fields apply.

### Child Record Exists

Passes if at least one child record matches `Child_Filter_Criteria__c`.

```
Child_Object_API_Name__c:    OpportunityContactRole
Child_Relationship_Field__c: OpportunityId
Child_Filter_Criteria__c:    Role = 'Decision Maker'
```

"At least one Contact Role with Role = Decision Maker must exist." Leave `Child_Filter_Criteria__c` blank to require any child record of that type at all, regardless of its fields.

### All Matching Children Satisfy

Selects children with `Child_Filter_Criteria__c` (blank selects every child of that type), and passes only if **all** of them also match `Child_Required_Criteria__c`. Vacuously true if none are selected.

```
Child_Object_API_Name__c:    OpportunityContactRole
Child_Relationship_Field__c: OpportunityId
Child_Filter_Criteria__c:    Role = 'Decision Maker'
Child_Required_Criteria__c:  IsPrimary = true
```

"Of all the Decision Maker contact roles, every one of them must be marked Primary." If there are two Decision Makers and only one is Primary, this fails — that's the difference from `Child Record Exists`, which would already be satisfied by the first one existing at all.

### Parent Field Criteria

Evaluates a single comparison against the record being saved — see [Parent Filter Criteria syntax](#parent-filter-criteria-syntax) below for the full operator and field-type reference.

```
Parent_Filter_Criteria__c: Amount != null
```

### Parent Criteria If Child Exists

An IF-THEN: if a child matching `Child_Filter_Criteria__c` exists, the parent must also match `Parent_Filter_Criteria__c`. Vacuously true if no such child exists at all — the requirement simply doesn't apply.

```
Child_Object_API_Name__c:    OpportunityContactRole
Child_Relationship_Field__c: OpportunityId
Child_Filter_Criteria__c:    Role = 'Decision Maker'
Parent_Filter_Criteria__c:   NextStep != null
```

"If this Opportunity has a Decision Maker contact role, NextStep must be populated. If it has no Decision Maker at all, this condition doesn't apply." That last part is the important one to get right when configuring this type — it's not "block the transition unless NextStep is set," it's conditional on the child existing at all.

## Parent Filter Criteria syntax

One comparison per condition record, always `FieldApiName OPERATOR Value` — no `AND`/`OR`. If you need multiple comparisons, add another condition record; every active condition on a rule is ANDed together anyway.

| Operator | Meaning |
|---|---|
| `=`, `!=` | Equals / not equals. Works for every field type below. |
| `>`, `>=`, `<`, `<=` | Ordering. Numbers and dates/datetimes only. |
| `LIKE` | SOQL-style pattern match, `%` for any run of characters, `_` for exactly one, case-insensitive. |
| `IN`, `NOT IN` | Match against a parenthesized list, e.g. `('A', 'B')`. |
| `INCLUDES`, `EXCLUDES` | Multi-select picklists only. |

`Field = null` and `Field != null` are the only way to test for blank — see [Null handling](#null-handling) below for what every other operator does with a blank field.

### String

```
Name = 'Acme Corp'
Name != 'Acme Corp'
Name LIKE 'Acme%'
Name LIKE '%Corp'
Name LIKE 'Ac_e Corp'
```

### Picklist

Same as string, plus list membership:

```
Type = 'New Customer'
Type IN ('New Customer', 'Existing Customer - Upgrade')
LeadSource NOT IN ('Purchased List', 'Other')
```

### Multi-select Picklist

Multi-select picklists store their selected values internally separated by `;`. `=`/`!=` test for a single exact value being selected (among possibly others); `INCLUDES`/`EXCLUDES` test for combinations, matching real SOQL semantics:

```
Interests__c = 'Golf'
Interests__c != 'Golf'
Interests__c INCLUDES ('Golf')
Interests__c INCLUDES ('Golf;Tennis')
Interests__c INCLUDES ('Golf', 'Tennis')
Interests__c EXCLUDES ('Skiing')
```

- `INCLUDES ('Golf;Tennis')` — one quoted group with a `;` inside — means **both** Golf AND Tennis must be selected.
- `INCLUDES ('Golf', 'Tennis')` — two separate quoted groups — means Golf **or** Tennis (or both) is enough; any one group fully matching is a pass.
- You can combine both inside the same list: `INCLUDES ('Golf;Tennis', 'Skiing')` passes if either (Golf and Tennis are both selected) or (Skiing is selected).
- `EXCLUDES` is the negation of the same grouping logic — `EXCLUDES ('Skiing')` passes if Skiing is not among the selected values.
- On a completely blank multi-select field, every `EXCLUDES` comparison passes (there's nothing selected to exclude) and every `INCLUDES`/`=` comparison fails.
- `IN`/`NOT IN` also work on multi-select fields and behave like `INCLUDES`/`EXCLUDES` with only single-value (no `;`) groups — match if any listed value is selected.

### Number, Currency, Percent

All three compare as decimals — there's no meaningful difference in how the framework evaluates them:

```
Amount > 10000
Amount >= 5000
Probability >= 75
NumberOfEmployees < 1000
Amount = 12345.67
```

In a multi-currency org, `Amount` comparisons are against the record's raw stored amount, in whatever currency that record is in — there's no conversion to a corporate/reference currency. A rule like `Amount > 10000` means something different for a USD Opportunity than a JPY one; scope separate rules per currency if that matters for you.

### Boolean

```
IsPrivate = true
IsPrimary != false
```

Only `=` and `!=` are supported for booleans.

### Date

Either an absolute `YYYY-MM-DD` value or a SOQL date literal:

```
CloseDate = 2026-01-01
CloseDate > 2026-01-01
CloseDate = TODAY
CloseDate = THIS_WEEK
CloseDate >= LAST_N_DAYS:30
```

Supported literals: `TODAY`, `YESTERDAY`, `TOMORROW`, `THIS_WEEK`, `LAST_WEEK`, `NEXT_WEEK`, `THIS_MONTH`, `LAST_MONTH`, `NEXT_MONTH`, `THIS_QUARTER`, `LAST_QUARTER`, `NEXT_QUARTER`, `THIS_YEAR`, `LAST_YEAR`, `NEXT_YEAR`, and the `:n`-suffixed family — `LAST_N_DAYS:n`, `NEXT_N_DAYS:n`, `N_DAYS_AGO:n`, `LAST_N_WEEKS:n`, `NEXT_N_WEEKS:n`, `N_WEEKS_AGO:n`, `LAST_N_MONTHS:n`, `NEXT_N_MONTHS:n`, `N_MONTHS_AGO:n`, `LAST_N_QUARTERS:n`, `NEXT_N_QUARTERS:n`, `N_QUARTERS_AGO:n`, `LAST_N_YEARS:n`, `NEXT_N_YEARS:n`, `N_YEARS_AGO:n`. Weeks start on Sunday; quarters are calendar quarters. **Fiscal-year literals aren't supported** — they depend on org-specific fiscal year settings this framework has no visibility into.

Single-day literals (`TODAY`, `N_DAYS_AGO:n`, etc.) support all six operators. Range literals (`THIS_WEEK`, `LAST_MONTH`, `THIS_QUARTER`, etc.) only support `=` (falls within the range) and `!=` (falls outside it) — `>`/`<` against a range doesn't have an unambiguous meaning, so it throws rather than guessing.

### Date/Time

Same literals as Date work here too (they widen to midnight–end-of-day on the field's date component). For an absolute value, you additionally get to choose how the time is anchored:

```
CreatedDate > 2026-01-01T09:00:00
CreatedDate > 2026-01-01 09:00:00
CreatedDate > 2026-01-01T09:00:00Z
```

**Without a trailing `Z`, the value is interpreted in the timezone of whoever saves the record** — the same way `Datetime.valueOf()` behaves in Apex. That's convenient for a single-timezone team, but means the exact same criteria string can produce different results for two users in different timezones, or for a scheduled/batch job running under a different user than the one who configured the rule. **Add a trailing `Z`** (e.g. `2026-01-01T09:00:00Z`) to pin an exact, unambiguous UTC instant — recommended for anything where the moment matters more than "business hours where I am."

### Null handling

`Amount = null` and `Amount != null` are the explicit way to test for blank. Every other operator (`>`, `<`, `LIKE`, `IN`, `NOT IN`, etc.) treats a blank field as **not satisfying the comparison**, full stop — `Amount > 100` on a blank Amount is `false`, not an error and not vacuously true. This is deliberately consistent across every operator, including `NOT IN`, even though a strict SQL reading might expect `NOT IN` to treat a blank field as automatically matching. If you want "blank is fine, but if it's set it must satisfy X," that specific "blank OR matches X" shape isn't expressible as two `Parent Field Criteria` conditions on the same rule, since conditions are ANDed, not ORed — model it as two separate rules instead (one for each acceptable case), or reconsider whether the field should be required in the first place.

The only exception is multi-select picklists, where a blank field is treated as an empty set: every `EXCLUDES` passes, every `INCLUDES`/`=` fails — see [Multi-select Picklist](#multi-select-picklist) above.

## Adding the checklist LWC to a record page

`fieldTransitionChecklist` targets `lightning__RecordPage` and isn't restricted to any particular object — it works on any object that has active `Field_Transition_Rule__mdt` records configured for it, and shows nothing (a graceful empty state) for one that doesn't.

1. Open the record page in Lightning App Builder.
2. Drag **Transition Checklist** onto the page — anywhere a component fits, including inside a Tabs component.
3. Save and activate.

It groups its output by governed field, shows every reachable next value from the record's current state, and marks each condition as met or not yet met. It's read-only — it never blocks a save, it only reports.

The checklist shows the same thing to every user who can see the record and the page it's on — it doesn't hide a condition or its `Message__c` based on the viewer's field-level security. That's a deliberate default (everyone sees the same requirements), not an oversight; if your org needs the checklist itself restricted by FLS, that's a change to make in `FieldTransitionRequirementService` before deploying it.

Its title and empty-state text come from two custom labels — `Field_Transition_Checklist_Title` and `Field_Transition_Checklist_Empty_State` — so either can be reworded from Setup without touching code.

## Tests

`FieldTransitionFrameworkTest` calls `FieldTransitionValidator`, `FieldTransitionConditionEvaluator`, `FieldTransitionRequirementService`, and `FieldTransitionRequirementController` directly rather than through a trigger, since wiring a trigger up is your own org's setup, not something this repo ships (see [Wiring it into your org](#wiring-it-into-your-org) above). It covers, among other things:

- Every scalar comparison type `Parent Field Criteria` supports (string, picklist, number, percent, currency, boolean, date, datetime — including the UTC/`Z` behavior) and the null-handling convention.
- All four condition types, backed by real child records.
- Bulk behavior: the query cost of validating many records stays flat instead of growing per record, and one misconfigured condition doesn't take down the others in the same batch.
- The read-only checklist service and its controller, including objects with no configured rules.

It does **not** cover everything, and it isn't meant to. Multi-select picklist and record-type comparisons, for example, exercise the exact same code paths already covered by the other operator tests, so they aren't duplicated here — but they also depend on fields/record types this framework has no way of guaranteeing exist in any given org, so there's no dedicated test for them either. If you configure rules using field types or scenarios this test class doesn't touch, that's on you to cover with your own tests, the same way it would be for any framework you install rather than write yourself.

## What you should NOT do

- Don't call `FieldTransitionValidator` from anywhere except a `before update` context (or something that mimics one, like a batch that supplies its own before/after pair). It compares old vs. new field values; without a genuine "before" state it can't tell what's actually transitioning.
- Don't combine multiple comparisons in one `Parent_Filter_Criteria__c` with `AND`/`OR` — it's not supported, and the parser will reject it. Use another condition record instead; every active condition on a rule is already ANDed.
- Don't rely on a field reference in `Field_API_Name__c`, `Child_Object_API_Name__c`, or a criteria string surviving a later field rename or deletion without you noticing — a rule or condition that references something that no longer exists is skipped/treated as unsatisfied and logged via `System.debug(LoggingLevel.ERROR, ...)`, rather than throwing and taking down every other save on that object. Check debug logs after any schema change touching a field these records reference.
- Don't expect `!=`/`NOT IN`/`>` to treat a blank field as a pass — see [Null handling](#null-handling) above.
- Don't assume an absolute datetime literal means the same instant for every user — add `Z` if you need it to.
- Don't assume unlimited headroom for rules and conditions — Custom Metadata Type storage is capped org-wide (10 MB across every custom metadata type in the org, not just this framework's), and each Long Text Area field on a condition counts as a flat 255 bytes toward that regardless of how much text it actually holds. That's room for many thousands of conditions in practice, but it's not infinite, and it's shared with whatever other CMDT your org uses.
