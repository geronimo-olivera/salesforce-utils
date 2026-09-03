@IsTest
private class NotificationServiceTest {

    @IsTest
    static void getCustomNotificationTypeReturnsNullForBlankOrMissing() {
        Assert.areEqual(null, NotificationService.getCustomNotificationType(null));
        Assert.areEqual(null, NotificationService.getCustomNotificationType(''));
        Assert.areEqual(null, NotificationService.getCustomNotificationType('Does_Not_Exist'));
    }

    @IsTest
    static void createAndSendNotificationDoNotThrowForNullOrRealCalls() {
        Account account = new Account(Name = 'Notification Test Account');
        insert account;

        Messaging.CustomNotification notification = NotificationService.createNotification(null, 'Title', 'Body', account.Id);

        Test.startTest();
        NotificationService.sendNotification(null, new Set<Id>{ UserInfo.getUserId() });
        NotificationService.sendNotification(notification, null);
        NotificationService.sendNotification(notification, new Set<Id>());
        NotificationService.sendNotification(notification, new Set<Id>{ UserInfo.getUserId() });
        Test.stopTest();
    }

    @IsTest
    static void recordLookupHelpersHandleNullAndReturnExpectedValues() {
        Assert.areEqual(null, NotificationService.getRecordOwnerId(null));
        Assert.areEqual(new Set<Id>(), NotificationService.getRecordFollowerIds(null));

        Account account = new Account(Name = 'Notification Owner Test Account', OwnerId = UserInfo.getUserId());
        insert account;

        Assert.areEqual(UserInfo.getUserId(), NotificationService.getRecordOwnerId(account.Id));

        insert new EntitySubscription(ParentId = account.Id, SubscriberId = UserInfo.getUserId());
        Set<Id> followerIds = NotificationService.getRecordFollowerIds(account.Id);
        Assert.isTrue(followerIds.contains(UserInfo.getUserId()));
    }

    @IsTest
    static void excludeUsersRemovesGivenIdsAndHandlesNulls() {
        Id userId = UserInfo.getUserId();
        Set<Id> withoutSelf = NotificationService.excludeUsers(new Set<Id>{ userId }, new Set<Id>{ userId });
        Assert.isTrue(withoutSelf.isEmpty());

        Assert.areEqual(new Set<Id>(), NotificationService.excludeUsers(null, new Set<Id>{ userId }));
        Assert.areEqual(new Set<Id>{ userId }, NotificationService.excludeUsers(new Set<Id>{ userId }, null));
    }
}
