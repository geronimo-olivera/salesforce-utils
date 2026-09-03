# NotificationService

A centralized entry point for Salesforce custom notifications (the bell icon). Every part of the org that needs to notify users — about a record, to a set of followers, to an owner, to an explicit list of people — builds and sends it through this class, so recipient-building and error handling stay consistent everywhere.

## Contents

- `force-app/main/default/classes/NotificationService.cls` — the service itself.
- `force-app/main/default/classes/NotificationServiceTest.cls` — its test class, 90% code coverage (see [Testing](#testing) for why it can't reach 100%).

## Before you can use it: Custom Notification Types

Unlike `EmailService`, this class has no custom metadata of its own to configure. What it does need is at least one **Custom Notification Type**, which only exists as a Setup-configured record — it can't be created via Apex or a metadata deploy from this repo:

1. Setup → Notification Builder → Custom Notifications → **New**.
2. Give it a Developer Name (e.g. `Account_Renewal_Due`) — that's what you pass to `getCustomNotificationType`.
3. Under the notification's settings, enable the channels you want (desktop, mobile) for the relevant apps.

Without at least one of these configured, `getCustomNotificationType` will always return `null`, and `sendNotification` will fail (see [Error handling](#error-handling)).

## Basic usage

### Look up a notification type and send to explicit users

```apex
CustomNotificationType type = NotificationService.getCustomNotificationType('Account_Renewal_Due');

Messaging.CustomNotification notification = NotificationService.createNotification(
    type.Id,
    'Renewal due soon',
    acc.Name + ' renews in 30 days.',
    acc.Id
);

NotificationService.sendNotification(notification, new Set<Id>{ userId1, userId2 });
```

### Notify everyone following a record

```apex
Set<Id> recipients = NotificationService.getRecordFollowerIds(acc.Id);
NotificationService.sendNotification(notification, recipients);
```

### Notify the record owner

```apex
Id ownerId = NotificationService.getRecordOwnerId(acc.Id);
NotificationService.sendNotification(notification, new Set<Id>{ ownerId });
```

### Don't notify the user who triggered the action

```apex
Set<Id> recipients = NotificationService.excludeUsers(
    NotificationService.getRecordFollowerIds(acc.Id),
    new Set<Id>{ UserInfo.getUserId() }
);
NotificationService.sendNotification(notification, recipients);
```

## Complete example

Combines every method: looks up the notification type once, notifies both the record owner and its followers, and excludes whoever triggered the update so they don't get notified about their own change. Illustrative — `OpportunityStageChangeHandler` isn't part of this repo, only `NotificationService` is.

```apex
public class OpportunityStageChangeHandler {

    public static void notifyStageChange(Opportunity opp) {
        CustomNotificationType type = NotificationService.getCustomNotificationType('Opportunity_Stage_Changed');
        if (type == null) {
            return; // Not configured in this org yet — nothing to send.
        }

        Messaging.CustomNotification notification = NotificationService.createNotification(
            type.Id,
            'Stage changed: ' + opp.Name,
            opp.Name + ' moved to ' + opp.StageName + '.',
            opp.Id
        );

        Set<Id> recipients = new Set<Id>();
        recipients.add(NotificationService.getRecordOwnerId(opp.Id));
        recipients.addAll(NotificationService.getRecordFollowerIds(opp.Id));

        // Batch every recipient into one send() call rather than looping — the platform caps how
        // many times you can call send() per transaction, but a single call can notify many users.
        recipients = NotificationService.excludeUsers(recipients, new Set<Id>{ UserInfo.getUserId() });

        NotificationService.sendNotification(notification, recipients);
    }
}
```

## Error handling

`sendNotification` wraps any failure from the underlying `Messaging.CustomNotification.send()` call — most commonly an invalid or missing `notificationTypeId` — into a single `NotificationService.NotificationServiceException`, so callers only need one `catch` block:

```apex
try {
    NotificationService.sendNotification(notification, recipients);
} catch (NotificationService.NotificationServiceException ex) {
    Logger.log(ex.getMessage());
}
```

There is no per-recipient result to inspect (unlike `EmailService.sendEmails`, which returns `Messaging.SendEmailResult`) — custom notification delivery is fire-and-forget from Apex's perspective, and a recipient's own notification preferences (which channels they've enabled) aren't visible to Apex at all.

There's also no `remainingNotificationInvocations()`-style helper like `EmailService.remainingEmailInvocations()` — Salesforce doesn't expose a `Limits` counter for custom notifications. The mitigation is structural, not a governor check: always pass every recipient into **one** `sendNotification` call (it takes a `Set<Id>`) instead of looping a call per recipient.

## Testing

`NotificationServiceTest` deploys and runs at **90% code coverage** with 4 test methods and no additional mock or helper classes. The gap is a real platform limitation, not a missing test: `Messaging.CustomNotification.send()` doesn't validate its `notificationTypeId` or simulate a failure in test context — a test was written explicitly to try to force the exception-wrapping branch (via an invalid `notificationTypeId`), and it didn't throw, confirming there's no way to exercise that `catch` block from a test. `Messaging.SendEmailResult`-style test hooks or an `HttpCalloutMock`-style test interface simply don't exist for this API.
