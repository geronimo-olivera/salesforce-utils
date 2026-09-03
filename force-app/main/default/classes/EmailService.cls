public inherited sharing class EmailService {

    private static final String DEFAULT_EMAIL_SERVICE_SETTING = 'Default';
    private static OrgWideEmailAddress defaultOrgWideEmail;

    /**
     * Returns an Email Template by Developer Name (exact match).
     * @param developerName The DeveloperName of the template.
     * @return The matching EmailTemplate, or null if not found or developerName is blank.
     */
    public static EmailTemplate getEmailTemplate(String developerName) {
        if (String.isBlank(developerName)) { return null; }
        List<EmailTemplate> templates = [
            SELECT Id, DeveloperName, Name, Subject
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0];
    }

    /**
     * Returns an Org-Wide Email Address by its Address value.
     * @param address The Address of the Org-Wide Email Address.
     * @return The matching OrgWideEmailAddress, or null if not found or address is blank.
     */
    public static OrgWideEmailAddress getOrgWideEmailAddress(String address) {
        if (String.isBlank(address)) { return null; }
        List<OrgWideEmailAddress> addresses = [
            SELECT Id, Address, DisplayName
            FROM OrgWideEmailAddress
            WHERE Address = :address
            LIMIT 1
        ];
        return addresses.isEmpty() ? null : addresses[0];
    }

    /**
     * Creates a SingleEmailMessage using an Email Template.
     * @param templateId The Id of the EmailTemplate to use.
     * @param whoId The Contact, Lead, or User Id the email is about (also determines the recipient address).
     * @param whatId Optional related record Id (e.g. an Opportunity) for template merge fields.
     * @param saveAsActivity Whether to log this email as an Activity on whoId.
     * @param orgWideEmailAddressId Optional Org-Wide Email Address Id. Falls back to the configured default when null.
     * @return A configured SingleEmailMessage, not yet sent.
     */
    public static Messaging.SingleEmailMessage createTemplatedEmail(
        Id templateId, 
        Id whoId, 
        Id whatId, 
        Boolean saveAsActivity, 
        Id orgWideEmailAddressId
    ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setTemplateId(templateId);
        configureEmail(email, whoId, whatId, saveAsActivity, orgWideEmailAddressId);
        return email;
    }

    /**
     * Renders an Email Template and replaces custom placeholders.
     * @param templateId The Id of the EmailTemplate to render.
     * @param whoId The Contact, Lead, or User Id the email is about (also determines the recipient address).
     * @param whatId Optional related record Id (e.g. an Opportunity) for template merge fields.
     * @param saveAsActivity Whether to log this email as an Activity on whoId.
     * @param orgWideEmailAddressId Optional Org-Wide Email Address Id. Falls back to the configured default when null.
     * @param replacements Map of placeholder text to its replacement value, applied to subject/HTML body/plain text body.
     * @return A configured SingleEmailMessage, not yet sent, or null if the template couldn't be rendered.
     */
    public static Messaging.SingleEmailMessage createRenderedTemplatedEmail(
        Id templateId, 
        Id whoId, 
        Id whatId, 
        Boolean saveAsActivity, 
        Id orgWideEmailAddressId, 
        Map<String, String> replacements
    ) {
        Messaging.SingleEmailMessage email = Messaging.renderStoredEmailTemplate(templateId, whoId, whatId);
        if (email == null) { return null; }
        if (replacements != null && !replacements.isEmpty()) {
            email.setSubject(replacePlaceholders(email.getSubject(), replacements));
            email.setHtmlBody(replacePlaceholders(email.getHtmlBody(), replacements));
            if (!String.isBlank(email.getPlainTextBody())) {
                email.setPlainTextBody(replacePlaceholders(email.getPlainTextBody(), replacements));
            }
        }
        configureEmail(email, whoId, whatId, saveAsActivity, orgWideEmailAddressId);
        return email;
    }

    /**
     * Creates an ad-hoc SingleEmailMessage with no Email Template, sent to explicit addresses.
     * @param toAddresses Recipient email addresses. Required — at least one address.
     * @param subject The email subject.
     * @param htmlBody The HTML body. Can be null if plainTextBody is provided.
     * @param plainTextBody The plain-text body. Can be null if htmlBody is provided.
     * @param orgWideEmailAddressId Optional Org-Wide Email Address Id. Falls back to the configured default when null.
     * @return A configured SingleEmailMessage, not yet sent.
     */
    public static Messaging.SingleEmailMessage createEmail(
        List<String> toAddresses, 
        String subject, 
        String htmlBody, 
        String plainTextBody, 
        Id orgWideEmailAddressId
    ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(toAddresses);
        email.setSubject(subject);
        if (htmlBody != null) { email.setHtmlBody(htmlBody); }
        if (plainTextBody != null) { email.setPlainTextBody(plainTextBody); }
        email.setSaveAsActivity(false);
        applyOrgWideEmailAddress(email, orgWideEmailAddressId);
        return email;
    }

    /**
     * Sets CC/BCC/reply-to on any SingleEmailMessage — templated or ad-hoc. Only touches the values passed in.
     * @param email The email to configure. No-op if null.
     * @param ccAddresses CC addresses. Can be null.
     * @param bccAddresses BCC addresses. Can be null.
     * @param replyToAddress A single reply-to address. Can be null.
     */
    public static void setAdditionalRecipients(
        Messaging.SingleEmailMessage email, 
        List<String> ccAddresses, 
        List<String> bccAddresses, 
        String replyToAddress
    ) {
        if (email == null) { return; }
        if (ccAddresses != null && !ccAddresses.isEmpty()) { email.setCcAddresses(ccAddresses); }
        if (bccAddresses != null && !bccAddresses.isEmpty()) { email.setBccAddresses(bccAddresses); }
        if (!String.isBlank(replyToAddress)) { email.setReplyTo(replyToAddress); }
    }

    /**
     * Attaches a file to a SingleEmailMessage, preserving any attachments already set.
     * @param email The email to attach the file to. No-op if null.
     * @param fileName The attachment's file name (e.g. "invoice.pdf").
     * @param contentType The attachment's MIME type (e.g. "application/pdf").
     * @param body The file content.
     */
    public static void addAttachment(
        Messaging.SingleEmailMessage email, 
        String fileName, 
        String contentType, 
        Blob body
    ) {
        if (email == null) { return; }
        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
        attachment.setFileName(fileName);
        attachment.setContentType(contentType);
        attachment.setBody(body);
        List<Messaging.EmailFileAttachment> attachments = email.getFileAttachments();
        if (attachments == null) { attachments = new List<Messaging.EmailFileAttachment>(); }
        attachments.add(attachment);
        email.setFileAttachments(attachments);
    }

    /**
     * Attaches existing Salesforce Files to a SingleEmailMessage by ContentDocument Id, without loading
     * their content into memory (unlike addAttachment, which needs the raw Blob).
     * @param email The email to attach files to. No-op if null.
     * @param contentDocumentIds Ids of the ContentDocument records to attach. No-op if null or empty.
     */
    public static void setFileAttachments(Messaging.SingleEmailMessage email, List<Id> contentDocumentIds) {
        if (email == null || contentDocumentIds == null || contentDocumentIds.isEmpty()) { return; }
        email.setEntityAttachments(contentDocumentIds);
    }

    /**
     * Sends the provided email messages if the list is not empty.
     * @param emailsToSend The emails to send.
     * @return The per-email results from Messaging.sendEmail, or an empty list if there was nothing to send.
     */
    public static List<Messaging.SendEmailResult> sendEmails(List<Messaging.SingleEmailMessage> emailsToSend) {
        return sendEmails(emailsToSend, false);
    }

    /**
     * Sends the provided email messages if the list is not empty.
     * @param emailsToSend The emails to send.
     * @param allOrNone When true (Apex's default for the single-arg Messaging.sendEmail), a single
     * invalid recipient aborts the whole batch with an uncaught System.EmailException instead of a
     * per-email result. Pass false (used by the single-arg overload) so one bad address doesn't stop
     * the rest of the batch from sending.
     * @return The per-email results from Messaging.sendEmail, or an empty list if there was nothing to send.
     */
    public static List<Messaging.SendEmailResult> sendEmails(List<Messaging.SingleEmailMessage> emailsToSend, Boolean allOrNone) {
        if (emailsToSend == null || emailsToSend.isEmpty()) { return new List<Messaging.SendEmailResult>(); }
        try {
            return Messaging.sendEmail(emailsToSend, allOrNone);
        } catch (System.EmailException ex) {
            EmailServiceException wrapped = new EmailServiceException('Failed to send ' + emailsToSend.size() + ' email(s): ' + ex.getMessage());
            wrapped.initCause(ex);
            throw wrapped;
        }
    }

    /**
     * Sends the provided email messages and throws if any of them failed.
     * @param emailsToSend The emails to send.
     * @param errorMessage The error message to include if any email failed.
     * @return The per-email results from Messaging.sendEmail.
     */
    public static List<Messaging.SendEmailResult> sendEmailsOrThrow(List<Messaging.SingleEmailMessage> emailsToSend, String errorMessage) {
        List<Messaging.SendEmailResult> results = sendEmails(emailsToSend);
        List<String> failures = new List<String>();
        for (Messaging.SendEmailResult result : results) {
            if (!result.isSuccess()) {
                for (Messaging.SendEmailError err : result.getErrors()) {
                    failures.add(err.getMessage());
                }
            }
        }
        if (!failures.isEmpty()) {
            throw new EmailServiceException(errorMessage + '\n' + String.join(failures, '\n'));
        }
        return results;
    }

    /**
     * @return how many more Messaging.sendEmail invocations are available in the current transaction (org limit is 10 per transaction).
     */
    public static Integer remainingEmailInvocations() {
        return Limits.getLimitEmailInvocations() - Limits.getEmailInvocations();
    }

    /**
     * Applies the provided Org-Wide Email Address or, when no Id is provided, applies the default Org-Wide Email Address.
     * @param email The email to configure. No-op if null.
     * @param orgWideEmailAddressId Optional Org-Wide Email Address Id.
     */
    private static void applyOrgWideEmailAddress(Messaging.SingleEmailMessage email, Id orgWideEmailAddressId) {
        if (email == null) { return; }
        Id addressId = orgWideEmailAddressId != null ? orgWideEmailAddressId : getDefaultOrgWideEmailAddressId();
        if (addressId != null) { email.setOrgWideEmailAddressId(addressId); }
    }

    /**
     * Returns the Id of the default Org-Wide Email Address.
     * @return The default OrgWideEmailAddress Id, or null if not configured.
     */
    private static Id getDefaultOrgWideEmailAddressId() {
        OrgWideEmailAddress orgWideEmail = getDefaultOrgWideEmailAddress();
        return orgWideEmail == null ? null : orgWideEmail.Id;
    }

    /**
     * Returns the default Org-Wide Email Address, per Email_Service_Setting__mdt.
     * The result is cached for the current transaction to avoid repeating the same SOQL query.
     * @return The default OrgWideEmailAddress, or null if not configured.
     */
    private static OrgWideEmailAddress getDefaultOrgWideEmailAddress() {
        if (defaultOrgWideEmail == null) {
            Email_Service_Setting__mdt setting = Email_Service_Setting__mdt.getInstance(DEFAULT_EMAIL_SERVICE_SETTING);
            if (setting != null && !String.isBlank(setting.Default_Org_Wide_Email_Address__c)) { defaultOrgWideEmail = getOrgWideEmailAddress(setting.Default_Org_Wide_Email_Address__c); }
        }
        return defaultOrgWideEmail;
    }

    /**
     * Applies the common configuration to a templated email message.
     * @param email The email to configure. No-op if null.
     * @param whoId The Contact, Lead, or User Id the email is about.
     * @param whatId Optional related record Id for template merge fields.
     * @param saveAsActivity Whether to log this email as an Activity on whoId.
     * @param orgWideEmailAddressId Optional Org-Wide Email Address Id.
     */
    private static void configureEmail(Messaging.SingleEmailMessage email, Id whoId, Id whatId, Boolean saveAsActivity, Id orgWideEmailAddressId) {
        if (email == null) { return; }
        email.setTargetObjectId(whoId);
        email.setSaveAsActivity(saveAsActivity);
        if (whatId != null) { email.setWhatId(whatId); }
        applyOrgWideEmailAddress(email, orgWideEmailAddressId);
    }

    /**
     * Replaces custom placeholders in an email body.
     * @param content The text to search and replace in.
     * @param replacements Map of placeholder text to its replacement value.
     * @return The text with all placeholders replaced, or the original content if there's nothing to replace.
     */
    private static String replacePlaceholders(String content, Map<String, String> replacements) {
        if (String.isBlank(content) || replacements == null || replacements.isEmpty()) { return content; }
        String result = content;
        for (String placeholder : replacements.keySet()) {
            result = result.replace(placeholder, replacements.get(placeholder) == null ? '' : replacements.get(placeholder));
        }
        return result;
    }

    /**
     * Exception thrown when sending one or more emails fails.
     */
    public class EmailServiceException extends Exception {}
}
