@IsTest
private class EmailServiceTest {

    @TestSetup
    static void setupData() {
        insert new EmailTemplate(
            Name = 'Email Service Test Template',
            DeveloperName = 'Email_Service_Test_Template',
            FolderId = UserInfo.getUserId(),
            TemplateType = 'text',
            Subject = 'Test Subject {{CUSTOM_VALUE}}',
            Body = 'Hello {!Contact.FirstName}. {{CUSTOM_VALUE}}'
        );

        Account account = new Account(Name = 'Email Service Test Account');
        insert account;

        Contact contact = new Contact(
            AccountId = account.Id,
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'email.service.test@example.com'
        );
        insert contact;
    }

    @IsTest
    static void getEmailTemplateAndOrgWideEmailAddressReturnNullForBlankOrMissing() {
        Assert.areEqual(null, EmailService.getEmailTemplate(null));
        Assert.areEqual(null, EmailService.getEmailTemplate(''));
        Assert.areEqual(null, EmailService.getEmailTemplate('Does_Not_Exist'));

        EmailTemplate template = EmailService.getEmailTemplate('Email_Service_Test_Template');
        Assert.isNotNull(template);
        Assert.areEqual('Email_Service_Test_Template', template.DeveloperName);

        Assert.areEqual(null, EmailService.getOrgWideEmailAddress(null));
        Assert.areEqual(null, EmailService.getOrgWideEmailAddress(''));
        Assert.areEqual(null, EmailService.getOrgWideEmailAddress('no-such-address@example.com'));
    }

    @IsTest
    static void createTemplatedEmailsConfigureCorrectly() {
        EmailTemplate template = EmailService.getEmailTemplate('Email_Service_Test_Template');
        Contact contact = [SELECT Id FROM Contact LIMIT 1];

        Messaging.SingleEmailMessage templatedEmail = EmailService.createTemplatedEmail(template.Id, contact.Id, null, false, null);
        Assert.areEqual(template.Id, templatedEmail.getTemplateId());
        Assert.areEqual(contact.Id, templatedEmail.getTargetObjectId());
        Assert.areEqual(false, templatedEmail.getSaveAsActivity());

        Messaging.SingleEmailMessage renderedEmail = EmailService.createRenderedTemplatedEmail(
            template.Id, contact.Id, null, false, null, new Map<String, String>{ '{{CUSTOM_VALUE}}' => 'Replacement Value' }
        );
        Assert.isNotNull(renderedEmail);
        Assert.isTrue(renderedEmail.getSubject().contains('Replacement Value'));
        Assert.isTrue(renderedEmail.getPlainTextBody().contains('Replacement Value'));
    }

    @IsTest
    static void createEmailAndAdditionalRecipientsAndAttachmentsConfigureCorrectly() {
        Messaging.SingleEmailMessage email = EmailService.createEmail(
            new List<String>{ 'recipient@example.com' }, 'Subject', '<p>HTML</p>', 'Plain text', null
        );
        Assert.areEqual(new List<String>{ 'recipient@example.com' }, email.getToAddresses());
        Assert.areEqual('Subject', email.getSubject());

        EmailService.setAdditionalRecipients(email, new List<String>{ 'cc@example.com' }, new List<String>{ 'bcc@example.com' }, 'reply@example.com');
        Assert.areEqual(new List<String>{ 'cc@example.com' }, email.getCcAddresses());
        Assert.areEqual(new List<String>{ 'bcc@example.com' }, email.getBccAddresses());
        Assert.areEqual('reply@example.com', email.getReplyTo());

        EmailService.addAttachment(email, 'test.txt', 'text/plain', Blob.valueOf('content'));
        Assert.areEqual(1, email.getFileAttachments().size());

        EmailService.setFileAttachments(email, new List<Id>{ '069000000000000AAA' });

        EmailService.setAdditionalRecipients(null, null, null, null);
        EmailService.addAttachment(null, null, null, null);
        EmailService.setFileAttachments(null, null);
    }

    @IsTest
    static void sendEmailsHandlesEmptyAndSucceedsForValidAddresses() {
        Assert.areEqual(0, EmailService.sendEmails(null).size());
        Assert.areEqual(0, EmailService.sendEmails(new List<Messaging.SingleEmailMessage>()).size());

        Messaging.SingleEmailMessage email = EmailService.createEmail(
            new List<String>{ 'recipient@example.com' }, 'Subject', '<p>Body</p>', null, null
        );

        Test.startTest();
        List<Messaging.SendEmailResult> results = EmailService.sendEmails(new List<Messaging.SingleEmailMessage>{ email });
        List<Messaging.SendEmailResult> orThrowResults = EmailService.sendEmailsOrThrow(new List<Messaging.SingleEmailMessage>{ email }, 'Should not fail');
        Integer remaining = EmailService.remainingEmailInvocations();
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].isSuccess());
        Assert.areEqual(1, orThrowResults.size());
        Assert.isTrue(orThrowResults[0].isSuccess());
        Assert.isTrue(remaining >= 0);
    }

    @IsTest
    static void sendEmailsWrapsEmailExceptionWhenAllOrNoneIsTrue() {
        Messaging.SingleEmailMessage invalidEmail = EmailService.createEmail(
            new List<String>{ 'not-an-email-address' }, 'Subject', '<p>Body</p>', null, null
        );

        Test.startTest();
        try {
            EmailService.sendEmails(new List<Messaging.SingleEmailMessage>{ invalidEmail }, true);
            Assert.isTrue(false, 'Expected EmailServiceException to be thrown.');
        } catch (EmailService.EmailServiceException ex) {
            Assert.isNotNull(ex.getCause(), 'The original EmailException should be preserved as the cause.');
        }
        Test.stopTest();
    }

    @IsTest
    static void sendEmailsOrThrowAggregatesPerEmailFailures() {
        Messaging.SingleEmailMessage invalidEmail = EmailService.createEmail(
            new List<String>{ 'not-an-email-address' }, 'Subject', '<p>Body</p>', null, null
        );

        Test.startTest();
        try {
            EmailService.sendEmailsOrThrow(new List<Messaging.SingleEmailMessage>{ invalidEmail }, 'Failed to send test email');
            Assert.isTrue(false, 'Expected EmailServiceException to be thrown.');
        } catch (EmailService.EmailServiceException ex) {
            Assert.isTrue(ex.getMessage().contains('Failed to send test email'));
        }
        Test.stopTest();
    }
}
