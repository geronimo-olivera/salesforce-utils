# Async Apex Framework

A metadata-driven Apex framework that removes the repetitive boilerplate around Batch Apex and Queueable Apex — active/inactive control, configurable batch size, automatic retry, and failure-email notifications, all driven by a single `Async_Job_Configuration__mdt` custom metadata type shared by both. Extend `BatchApexHandler` or `QueueableApexHandler`, implement the one or two methods that actually do your work, and launch it through `run()`.

Standalone repo with the full project scaffold (deployable manifest, generated docs, etc.): [github.com/geronimo-olivera/Async-Apex-Framework](https://github.com/geronimo-olivera/Async-Apex-Framework).

## Purpose

- **Configuration over code** — active flag, batch size, retry count, and failure email all live in `Async_Job_Configuration__mdt` records, one per class. A class with no configuration record runs with sane defaults; nothing requires a record to exist.
- **One shared base, two genuinely different subclasses** — `AsyncJobHandlerBase` resolves a class's own configuration once and holds the state and `onFinish` hook both patterns need. `BatchApexHandler` and `QueueableApexHandler` each implement only the retry/completion logic that's actually different between the two — that logic is **not** unified, on purpose (see [Why Batch and Queueable retry differently](#why-batch-and-queueable-retry-differently) below).
- **Built-in retry, with the cost made explicit** — either framework can automatically retry a failed job (capped at 10 attempts, regardless of what's configured). A retry always reprocesses everything from scratch, not just what failed — see [Retry behavior and idempotency](#retry-behavior-and-idempotency).
- **Failure emails with multiple recipients** — check a box, list one or more semicolon-separated addresses, get notified once a job (after retries) still failed.

## Contents

- `force-app/main/default/classes/AsyncJobHandlerBase.cls` — shared abstract base. Resolves the concrete subclass's own `Async_Job_Configuration__mdt` record once, exposes the resolved settings and a retry counter, and declares the `onFinish` hook. Holds no retry/execution logic itself.
- `force-app/main/default/classes/AsyncJobHandlerHelper.cls` — static logic shared by both handlers: resolving a subclass's own class name, applying the configuration's defaults, parsing a semicolon-separated recipient list, and sending the failure email.
- `force-app/main/default/classes/AsyncJobConfigurationService.cls` — read-only access to `Async_Job_Configuration__mdt`.
- `force-app/main/default/classes/BatchApexHandler.cls` — extend this and implement `getQueryLocator()`/`executeScope()` instead of `Database.Batchable` directly.
- `force-app/main/default/classes/QueueableApexHandler.cls` — extend this and implement `executeJob()` instead of `Queueable` directly. Add `Database.AllowsCallouts` to your own subclass if it needs one.
- `force-app/main/default/classes/BatchApexHandlerTest.cls` and `BatchApexHandlerTestBatch.cls` — test coverage for `BatchApexHandler`. The second file is a one-method top-level class, not a mock — see [Testing](#testing) for why it has to exist as its own file.
- `force-app/main/default/classes/QueueableApexHandlerTest.cls` — test coverage for `QueueableApexHandler`, including its own test-only subclass as an inner class (Queueable, unlike Batch, has no restriction against that).
- `force-app/main/default/objects/Async_Job_Configuration__mdt/` — the custom metadata type, its fields, and its validation rules.

## Custom metadata: `Async_Job_Configuration__mdt`

One record per `BatchApexHandler` or `QueueableApexHandler` subclass, matched automatically at runtime by class name. Entirely optional — a class with no record runs active, with no retry and no batch-size override.

| Field | Type | Description |
|---|---|---|
| `Class_Name__c` | Text (required, unique) | API name of the `BatchApexHandler`/`QueueableApexHandler` subclass this record configures. |
| `Job_Type__c` | Picklist (required) | `Batch` or `Queueable`. Not read by either framework class at runtime — the class itself already determines that — it's here purely so Setup's list view is scannable and filterable. |
| `Is_Active__c` | Checkbox | Defaults to `true`. If `false`, `run()` skips the job instead of enqueuing it. |
| `Batch_Size__c` | Number | Only meaningful when `Job_Type__c` is `Batch`. Blank defaults to 200; always clamped to the platform's own 1–2000 range regardless of what's entered. |
| `Max_Retry_Attempts__c` | Number | How many times to automatically retry after a failure. Blank or 0 disables retry. Capped at 10 regardless of what's entered. |
| `Send_Email_On_Failure__c` | Checkbox | If `true`, sends a failure email once the job (after any configured retries) still failed. |
| `Notification_Emails__c` | Long Text Area | One address, or several separated by semicolons (`first@x.com; second@x.com`). Required whenever `Send_Email_On_Failure__c` is checked (enforced by a validation rule). |
| `Org_Wide_Email_Address_Id__c` | Text | Id of a verified Organization-Wide Email Address (Setup → Organization-Wide Email Addresses → click the address → the Id, starting with `0D8`, is in the URL) to send the failure email from. Required whenever `Send_Email_On_Failure__c` is checked (enforced by a validation rule) — **the email can fail to send without it**, since sending falls back to the running user's own address otherwise, which can throw `INVALID_SENDER` in a Batch/Queueable context. |

Three validation rules enforce the dependencies above: `Batch_Size_Requires_Batch_Type`, `Send_Email_Requires_Address`, and `Send_Email_Requires_Org_Wide_Address`.

## Writing a Batch job — easy example

```apex
public class CloseStaleOpportunitiesBatch extends BatchApexHandler {

    protected override Database.QueryLocator getQueryLocator() {
        return Database.getQueryLocator([
            SELECT Id, StageName
            FROM Opportunity
            WHERE IsClosed = false AND LastActivityDate < LAST_N_DAYS:90
        ]);
    }

    protected override void executeScope(List<SObject> scope) {
        List<Opportunity> staleOpportunities = (List<Opportunity>) scope;
        for (Opportunity opp : staleOpportunities) {
            opp.StageName = 'Closed Lost';
        }
        update staleOpportunities;
    }
}
```

Launch it with `BatchApexHandler.run(new CloseStaleOpportunitiesBatch());`. With no `Async_Job_Configuration__mdt` record for this class, it runs with batch size 200, no retry, and no failure email — `getQueryLocator()`/`executeScope()` are all you had to write.

## Writing a Batch job — advanced example

Takes a constructor argument, builds its query dynamically, makes a callout (needs `Database.AllowsCallouts` added to your own subclass — the base class doesn't declare it, since not every job needs it), and chains a second batch from `onFinish()` once it completes cleanly:

```apex
public class SyncAccountsToExternalSystemBatch extends BatchApexHandler implements Database.AllowsCallouts {

    private String industryFilter;

    public SyncAccountsToExternalSystemBatch(String industryFilter) {
        this.industryFilter = industryFilter;
    }

    protected override Database.QueryLocator getQueryLocator() {
        String query = 'SELECT Id, Name, Website FROM Account';
        if (String.isNotBlank(industryFilter)) {
            query += ' WHERE Industry = :industryFilter';
        }
        return Database.getQueryLocator(query);
    }

    protected override void executeScope(List<SObject> scope) {
        for (Account acc : (List<Account>) scope) {
            HttpRequest request = new HttpRequest();
            request.setEndpoint('callout:External_CRM/accounts/' + acc.Id);
            request.setMethod('POST');
            request.setBody(JSON.serialize(new Map<String, Object>{ 'name' => acc.Name, 'website' => acc.Website }));
            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() >= 300) {
                throw new CalloutException('Sync failed for ' + acc.Id + ': ' + response.getStatus());
            }
        }
    }

    protected override void onFinish(Boolean hadErrors) {
        if (!hadErrors) {
            BatchApexHandler.run(new CreateFollowUpTasksBatch(industryFilter));
        }
    }
}
```

A dynamic SOQL string can still reference a local variable with `:variableName` the same way an inline query would — Salesforce resolves it from the enclosing scope at call time, so this isn't string concatenation and isn't a SOQL injection risk the way building the literal value into the string would be.

## Writing a Queueable job — easy example

There's no scope/chunking concept here, unlike Batch — get whatever data you need from your own constructor:

```apex
public class EscalateCasesQueueable extends QueueableApexHandler {

    private List<Id> caseIds;

    public EscalateCasesQueueable(List<Id> caseIds) {
        this.caseIds = caseIds;
    }

    protected override void executeJob() {
        List<Case> cases = [SELECT Id, Status FROM Case WHERE Id IN :caseIds];
        for (Case c : cases) {
            c.Status = 'Escalated';
        }
        update cases;
    }
}
```

Launch it with `QueueableApexHandler.run(new EscalateCasesQueueable(caseIds));`.

## Writing a Queueable job — advanced example

A callout, and manual self-chaining for **continuation** (processing another page of records) rather than **retry** (redoing a failure) — these are different concepts, and the framework only automates the second one.

```apex
public class SlackNotificationQueueable extends QueueableApexHandler implements Database.AllowsCallouts {

    private String message;

    public SlackNotificationQueueable(String message) {
        this.message = message;
    }

    protected override void executeJob() {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:Slack_Webhook');
        request.setMethod('POST');
        request.setBody(JSON.serialize(new Map<String, Object>{ 'text' => message }));
        HttpResponse response = new Http().send(request);
        if (response.getStatusCode() >= 300) {
            throw new CalloutException('Slack notification failed: ' + response.getStatus());
        }
    }
}
```

Manual chaining for pagination, driven from `onFinish()` instead of the framework's built-in retry:

```apex
public class NormalizeContactEmailsQueueable extends QueueableApexHandler {

    private static final Integer PAGE_SIZE = 200;

    private Id lastProcessedId;
    private Boolean morePagesRemain = true;

    public NormalizeContactEmailsQueueable() {
        this(null);
    }

    public NormalizeContactEmailsQueueable(Id lastProcessedId) {
        this.lastProcessedId = lastProcessedId;
    }

    protected override void executeJob() {
        String query = 'SELECT Id, Email FROM Contact';
        if (lastProcessedId != null) {
            query += ' WHERE Id > :lastProcessedId';
        }
        query += ' ORDER BY Id LIMIT :PAGE_SIZE';
        List<Contact> page = Database.query(query);

        for (Contact c : page) {
            if (c.Email != null) {
                c.Email = c.Email.toLowerCase();
            }
        }
        update page;

        morePagesRemain = page.size() == PAGE_SIZE;
        if (!page.isEmpty()) {
            lastProcessedId = page[page.size() - 1].Id;
        }
    }

    protected override void onFinish(Boolean hadErrors) {
        if (!hadErrors && morePagesRemain) {
            QueueableApexHandler.run(new NormalizeContactEmailsQueueable(lastProcessedId));
        }
    }
}
```

Watch the first page carefully: `WHERE Id > :lastProcessedId` is only added once `lastProcessedId` is non-null. Comparing a field to a bind variable that's `null` doesn't mean "match everything" in SOQL — it matches zero rows. Track "is there more to do" with your own boolean (`morePagesRemain` here) instead of overloading `null` to mean two different things.

## Retry behavior and idempotency

Both handlers can automatically retry a failed job, capped at 10 attempts regardless of what `Max_Retry_Attempts__c` says. What "retry" means is more aggressive than it sounds:

- **Batch**: a retry calls `getQueryLocator()` again from scratch and reprocesses **every** matching record — including the ones that already succeeded on the failed attempt. The retry check is at the whole-job level (`AsyncApexJob.NumberOfErrors > 0`), not per chunk.
- **Queueable**: a retry re-runs `executeJob()` from scratch, on the same instance, with the same constructor state it started with.

Neither one tracks "what already succeeded" for you. If `executeScope()`/`executeJob()` does anything that isn't safe to repeat — an external callout, sending an email, incrementing a counter — a retry after a partial failure can double it. Write your job logic so it's safe to run again on records it already touched: prefer `upsert` keyed by an external Id over `insert`, check a status field before acting, and use an idempotency key for callouts to a system you don't control.

## Why Batch and Queueable retry differently

`BatchApexHandler.execute()` catches the subclass's exception, logs it, and **re-throws** it. That's deliberate — `AsyncApexJob.NumberOfErrors` (what `finish()` checks to decide whether to retry) only increments when an exception actually escapes `execute()`. Swallowing it there would silently disable retry.

`QueueableApexHandler.execute()` **never** re-throws, even after retries are exhausted — also deliberate, and verified against a real org rather than assumed: enqueueing a retry with `System.enqueueJob(this)` and then letting the original exception propagate rolls back that enqueue along with the rest of the failing transaction. A chained job enqueued right before a throw never actually runs. So a Queueable job that ultimately fails always shows as "Completed" in Setup → Apex Jobs; failure visibility comes from debug logs and the optional email, never from the job's own status.

## Failure emails

Check `Send_Email_On_Failure__c`, set one or more semicolon-separated addresses in `Notification_Emails__c`, and set `Org_Wide_Email_Address_Id__c` to a verified Organization-Wide Email Address Id — validation rules require both of the latter whenever the checkbox is set. The email fires once, after the job (following any configured retries) still has errors.

`Org_Wide_Email_Address_Id__c` is not optional in practice, even though the field allows blank: `AsyncJobHandlerHelper.sendFailureEmail` only calls `setOrgWideEmailAddressId` when it's populated, and leaving it blank means sending falls back to the running user's own address — often an automated/integration identity with no confirmed deliverable email, which can throw `INVALID_SENDER`. A malformed value here (or in `Notification_Emails__c`) doesn't break job processing either way — it's caught and only logged, on purpose — but that also means nothing tells you the notification silently failed except that debug log line.

A malformed address doesn't block your job from running and doesn't throw — `AsyncJobHandlerHelper.sendFailureEmail` catches that internally and only logs it, on purpose, so a typo in a notification address can never take down the actual record processing. The tradeoff is that nothing else tells you the notification silently failed — check debug logs for `'Failed to send failure notification for ...'` if you suspect a configured email isn't arriving.

## Scheduling a job

Neither handler implements `Schedulable`, and that's intentional: Setup's own **Schedule Apex** UI can only launch a class that implements `Schedulable` with a public no-argument constructor, and most real Batch/Queueable subclasses take constructor arguments a UI has no way to supply. Instead, write a tiny `Schedulable` wrapper per job that needs a real cron schedule:

```apex
public class NormalizeContactEmailsScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        QueueableApexHandler.run(new NormalizeContactEmailsQueueable());
    }
}
```

```apex
System.schedule('Normalize Contact Emails Nightly', '0 0 2 * * ?', new NormalizeContactEmailsScheduler());
```

This keeps the scheduling concern (when, and with what fixed inputs) separate from the job's own logic, and works identically for a Batch or a Queueable subclass.

## Testing

`BatchApexHandlerTest` (plus its companion top-level class `BatchApexHandlerTestBatch`) and `QueueableApexHandlerTest` together reach **100% coverage on `BatchApexHandler`, `QueueableApexHandler`, `AsyncJobHandlerHelper`, and `AsyncJobConfigurationService`**, and 83% on `AsyncJobHandlerBase` (the one uncovered line is the default `onFinish` no-op body, which nothing calls without being overridden — covering it would mean shipping a subclass built only to not override a hook, which isn't worth the extra file).

Getting there required working around three real, empirically-confirmed Salesforce platform quirks — and if you write your own subclass and want to unit test its retry or failure-email path, you'll run into the exact same ones:

1. **A `Database.Batchable` implementer must be a top-level class.** An inner class that inherits the interface through an abstract base compiles fine but can't be reliably executed via `Database.executeBatch` at runtime. That's why `BatchApexHandlerTestBatch` exists as its own file instead of an inner class.
2. **In Apex test context, if a Batch's only `execute()` call throws an uncaught exception, `finish()` never runs at all**, and only one `Database.executeBatch` call is allowed per test method — so a real retry chain can't be triggered by making `executeScope()` throw for real. `BatchApexHandler` exposes `protected void handleFinish(Integer numberOfErrors)` for exactly this — tests call it directly with whatever error count they want to simulate, without needing a live `Database.BatchableContext` (which test code can't construct anyway).
3. **A chained `System.enqueueJob(this)` retry runs in its own transaction**, with its own governor limits — a test asserting `Limits.getEmailInvocations()` after `Test.stopTest()` won't see an email sent from inside that chained transaction. `QueueableApexHandlerTest` works around this by pre-setting the retry counter so the exhausted-retry path (and its email) runs synchronously, in the same transaction as the assertion.

## What you should NOT do

- Don't write `executeScope()`/`executeJob()` as non-idempotent if `Max_Retry_Attempts__c` is anything above 0 — see [Retry behavior and idempotency](#retry-behavior-and-idempotency) above.
- Don't set `Max_Retry_Attempts__c` expecting more than 10 attempts — it's hard-clamped in code regardless of what the record says.
- Don't point Setup's **Schedule Apex** UI at a subclass that needs constructor arguments — it can't supply them. Use a small `Schedulable` wrapper instead.
- Don't assume `Notification_Emails__c` or `Org_Wide_Email_Address_Id__c` will tell you if either is misconfigured — a malformed value fails silently into a debug log line, not into the job's own success/failure state.
- Don't leave `Org_Wide_Email_Address_Id__c` blank and assume `Notification_Emails__c` alone is enough — see [Failure emails](#failure-emails) above.
- Don't try to create a second `Async_Job_Configuration__mdt` record for the same `Class_Name__c` — the field is unique, so the save/deploy is rejected outright.
- Don't assume a Queueable job's Setup → Apex Jobs status reflects whether it actually failed — it always shows "Completed" by design, even after exhausting retries. Check debug logs or the failure email instead.
- Don't assume `finish()` is guaranteed to run in every conceivable Batch failure scenario — if an extreme majority of a real job's chunks fail, the platform itself can abort the job early. If a configured failure email doesn't show up when you expect one, check Setup → Apex Jobs for a job stuck in "Failed" status rather than assuming the framework silently swallowed it.
