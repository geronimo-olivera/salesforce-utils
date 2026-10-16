public inherited sharing class FileService {

    /**
     * ContentDocumentLink.ShareType. The permission the linked entity gets on the file.
     * VIEWER (V): can view, not edit.
     * COLLABORATOR (C): can view and edit. Meant for users, groups, and libraries: Salesforce rejects it on a link to a
     * record (verified on Opportunity: "Invalid sharing type C"), and never allows creating one from an Apex trigger.
     * INFERRED (I): permission comes from the linked record (or from the library, for library links). Not valid for the Organization object.
     */
    public enum FileShareType { VIEWER, COLLABORATOR, INFERRED }

    /**
     * ContentDocumentLink.Visibility. Who can see the file on the linked record.
     * ALL_USERS (AllUsers): every user with permission to see the file, external included.
     * INTERNAL_USERS (InternalUsers): only internal users with permission to see the file.
     * SHARED_USERS (SharedUsers): users who can see the feed the file is posted to. Only for files shared with users, and only
     * available when the org's default sharing is private. Salesforce rejects it on a link to a record (verified on Opportunity:
     * "not permitted for this linked record").
     * Applies to links on standard and custom object records, not to users, groups, or libraries. External users can only use ALL_USERS.
     */
    public enum FileVisibility { ALL_USERS, INTERNAL_USERS, SHARED_USERS }

    private static final Map<FileShareType, String> SHARE_TYPE_VALUES = new Map<FileShareType, String>{
        FileShareType.VIEWER => 'V',
        FileShareType.COLLABORATOR => 'C',
        FileShareType.INFERRED => 'I'
    };

    private static final Map<FileVisibility, String> VISIBILITY_VALUES = new Map<FileVisibility, String>{
        FileVisibility.ALL_USERS => 'AllUsers',
        FileVisibility.INTERNAL_USERS => 'InternalUsers',
        FileVisibility.SHARED_USERS => 'SharedUsers'
    };

    private static final String DOWNLOAD_DOCUMENT_PATH = '/sfc/servlet.shepherd/document/download/';
    private static final String DOWNLOAD_VERSION_PATH = '/sfc/servlet.shepherd/version/download/';

    /**
     * Creates a file (a new ContentDocument with its first ContentVersion) and, optionally, links it to a record.
     * The link is created by Salesforce itself with its default ShareType and Visibility; use the six-argument
     * overload to choose them.
     * @param title The file's title. If blank, derived from fileName without its extension.
     * @param fileName The file name including its extension (e.g. 'contract.pdf'). The extension is what tells Salesforce the file type.
     * @param body The file's content.
     * @param linkedEntityId Optional record Id (or User/Library Id) to link the file to on creation. Pass null to create an unlinked file.
     * @return The inserted ContentVersion, re-queried so ContentDocumentId and the other standard fields are populated.
     * @throws FileServiceException if fileName or body is blank/null, or the insert fails.
     */
    public static ContentVersion createFile(String title, String fileName, Blob body, Id linkedEntityId) {
        if (String.isBlank(fileName)) { throw new FileServiceException('Cannot create a file without a fileName.'); }
        if (body == null) { throw new FileServiceException('Cannot create file "' + fileName + '" without a body.'); }
        ContentVersion version = new ContentVersion(
            Title = String.isNotBlank(title) ? title : getNameWithoutExtension(fileName),
            PathOnClient = fileName,
            VersionData = body
        );
        if (linkedEntityId != null) { version.FirstPublishLocationId = linkedEntityId; }
        try {
            insert version;
        } catch (DmlException ex) {
            throw wrap('Failed to create file "' + fileName + '"', ex);
        }
        return getVersionById(version.Id);
    }

    /**
     * Creates a file titled after its fileName (minus extension). Shortcut for the four-argument overload.
     * @param fileName The file name including its extension (e.g. 'contract.pdf').
     * @param body The file's content.
     * @param linkedEntityId Optional record Id to link the file to on creation. Pass null to create an unlinked file.
     * @return The inserted ContentVersion.
     * @throws FileServiceException if fileName or body is blank/null, or the insert fails.
     */
    public static ContentVersion createFile(String fileName, Blob body, Id linkedEntityId) {
        return createFile(null, fileName, body, linkedEntityId);
    }

    /**
     * Creates a file and links it to a record with an explicit ShareType and Visibility. All-or-nothing: if the
     * link fails, the file isn't left behind.
     * @param title The file's title. If blank, derived from fileName without its extension.
     * @param fileName The file name including its extension.
     * @param body The file's content.
     * @param linkedEntityId The record to link the file to. If null, the file is created unlinked and shareType/visibility are ignored.
     * @param shareType The permission to grant. Null defaults to VIEWER.
     * @param visibility Who can see the file on the record. Null lets Salesforce pick its default.
     * @return The inserted ContentVersion.
     * @throws FileServiceException if validation, the insert, or the link fails.
     */
    public static ContentVersion createFile(String title, String fileName, Blob body, Id linkedEntityId, FileShareType shareType, FileVisibility visibility) {
        Savepoint savepoint = Database.setSavepoint();
        try {
            ContentVersion version = createFile(title, fileName, body, null);
            if (linkedEntityId != null) {
                linkToRecord(version.ContentDocumentId, linkedEntityId, shareType, visibility);
            }
            return version;
        } catch (FileServiceException ex) {
            Database.rollback(savepoint);
            throw ex;
        }
    }

    /**
     * Uploads a new version of an existing file. Every record the file is linked to automatically sees the new version.
     * @param contentDocumentId The Id of the existing file (ContentDocument).
     * @param fileName The new version's file name including its extension.
     * @param body The new version's content.
     * @param reasonForChange Optional note shown in the file's version history.
     * @return The inserted ContentVersion, re-queried.
     * @throws FileServiceException if any required argument is blank/null, or the insert fails.
     */
    public static ContentVersion createNewVersion(Id contentDocumentId, String fileName, Blob body, String reasonForChange) {
        if (contentDocumentId == null) { throw new FileServiceException('Cannot create a new version without a contentDocumentId.'); }
        if (String.isBlank(fileName)) { throw new FileServiceException('Cannot create a new version without a fileName.'); }
        if (body == null) { throw new FileServiceException('Cannot create a new version of file ' + contentDocumentId + ' without a body.'); }
        ContentVersion version = new ContentVersion(
            ContentDocumentId = contentDocumentId,
            Title = getNameWithoutExtension(fileName),
            PathOnClient = fileName,
            VersionData = body,
            ReasonForChange = reasonForChange
        );
        try {
            insert version;
        } catch (DmlException ex) {
            throw wrap('Failed to create a new version of file ' + contentDocumentId, ex);
        }
        return getVersionById(version.Id);
    }

    /**
     * Links an existing file to a record as a VIEWER, leaving Visibility to Salesforce's default. Shortcut for the four-argument overload.
     * @param contentDocumentId The file to link.
     * @param recordId The record (or User/Group/Library) to link it to.
     * @return The existing or newly created ContentDocumentLink.
     * @throws FileServiceException if either Id is null, or the insert fails.
     */
    public static ContentDocumentLink linkToRecord(Id contentDocumentId, Id recordId) {
        return linkToRecord(contentDocumentId, recordId, FileShareType.VIEWER, null);
    }

    /**
     * Links an existing file to one record. Shortcut for linkToRecords with a single Id.
     * @param contentDocumentId The file to link.
     * @param recordId The record (or User/Group/Library) to link it to.
     * @param shareType The permission to grant. Null defaults to VIEWER.
     * @param visibility Who can see the file on the record. Null lets Salesforce pick its default.
     * @return The existing or newly created ContentDocumentLink.
     * @throws FileServiceException if either Id is null, a ShareType/Visibility rule is violated, or the insert fails.
     */
    public static ContentDocumentLink linkToRecord(Id contentDocumentId, Id recordId, FileShareType shareType, FileVisibility visibility) {
        if (recordId == null) { throw new FileServiceException('Cannot link a file without a recordId.'); }
        return linkToRecords(contentDocumentId, new Set<Id>{ recordId }, shareType, visibility)[0];
    }

    /**
     * Links an existing file to several records in one DML statement. Safe to call twice: a record the file is
     * already linked to keeps its existing link untouched (it is returned as-is, even if its ShareType/Visibility
     * differ from the ones passed here; use updateLink to change those).
     * @param contentDocumentId The file to link.
     * @param recordIds The records (or Users/Groups/Libraries) to link it to. Null entries are skipped.
     * @param shareType The permission to grant. Null defaults to VIEWER.
     * @param visibility Who can see the file on the records. Null lets Salesforce pick its default.
     * @return One ContentDocumentLink per record Id passed, existing or newly created.
     * @throws FileServiceException if contentDocumentId is null, COLLABORATOR is requested from an Apex trigger,
     *         INFERRED is requested for the Organization object, or the insert fails.
     */
    public static List<ContentDocumentLink> linkToRecords(Id contentDocumentId, Set<Id> recordIds, FileShareType shareType, FileVisibility visibility) {
        if (contentDocumentId == null) { throw new FileServiceException('Cannot link a file without a contentDocumentId.'); }
        List<ContentDocumentLink> result = new List<ContentDocumentLink>();
        if (recordIds == null || recordIds.isEmpty()) { return result; }

        FileShareType effectiveShareType = shareType != null ? shareType : FileShareType.VIEWER;
        if (effectiveShareType == FileShareType.COLLABORATOR && System.Trigger.isExecuting) {
            throw new FileServiceException('Salesforce does not allow creating a COLLABORATOR link from an Apex trigger.');
        }

        Map<Id, ContentDocumentLink> existingByRecord = new Map<Id, ContentDocumentLink>();
        for (ContentDocumentLink link : [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId AND LinkedEntityId IN :recordIds
        ]) {
            existingByRecord.put(link.LinkedEntityId, link);
        }

        List<ContentDocumentLink> newLinks = new List<ContentDocumentLink>();
        for (Id recordId : recordIds) {
            if (recordId == null) { continue; }
            if (existingByRecord.containsKey(recordId)) {
                result.add(existingByRecord.get(recordId));
                continue;
            }
            if (effectiveShareType == FileShareType.INFERRED && recordId.getSObjectType() == Organization.SObjectType) {
                throw new FileServiceException('INFERRED permission cannot be used on a link to the Organization.');
            }
            ContentDocumentLink link = new ContentDocumentLink(
                ContentDocumentId = contentDocumentId,
                LinkedEntityId = recordId,
                ShareType = SHARE_TYPE_VALUES.get(effectiveShareType)
            );
            if (visibility != null) { link.Visibility = VISIBILITY_VALUES.get(visibility); }
            newLinks.add(link);
            result.add(link);
        }
        if (!newLinks.isEmpty()) {
            try {
                insert newLinks;
            } catch (DmlException ex) {
                throw wrap('Failed to link file ' + contentDocumentId + ' to ' + newLinks.size() + ' record(s)', ex);
            }
        }
        return result;
    }

    /**
     * Changes the ShareType and/or Visibility of an existing link. Only internal users can update Visibility, and
     * only on links to standard/custom object records (not users, groups, or libraries).
     * @param contentDocumentId The linked file.
     * @param recordId The record the file is linked to.
     * @param shareType The new permission, or null to leave it unchanged.
     * @param visibility The new visibility, or null to leave it unchanged.
     * @return The updated ContentDocumentLink.
     * @throws FileServiceException if either Id is null, the file isn't linked to the record, or the update fails.
     */
    public static ContentDocumentLink updateLink(Id contentDocumentId, Id recordId, FileShareType shareType, FileVisibility visibility) {
        if (contentDocumentId == null || recordId == null) {
            throw new FileServiceException('Cannot update a link without both a contentDocumentId and a recordId.');
        }
        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId AND LinkedEntityId = :recordId
            LIMIT 1
        ];
        if (links.isEmpty()) {
            throw new FileServiceException('File ' + contentDocumentId + ' is not linked to record ' + recordId + '.');
        }
        ContentDocumentLink link = links[0];
        if (shareType != null) { link.ShareType = SHARE_TYPE_VALUES.get(shareType); }
        if (visibility != null) { link.Visibility = VISIBILITY_VALUES.get(visibility); }
        try {
            update link;
        } catch (DmlException ex) {
            throw wrap('Failed to update the link between file ' + contentDocumentId + ' and record ' + recordId, ex);
        }
        return link;
    }

    /**
     * Returns every link of a file: the owner, and every record, user, group, or library it's shared with.
     * @param contentDocumentId The file whose links to list.
     * @return The file's ContentDocumentLinks. Empty if contentDocumentId is null or the file isn't found.
     */
    public static List<ContentDocumentLink> getLinks(Id contentDocumentId) {
        if (contentDocumentId == null) { return new List<ContentDocumentLink>(); }
        return [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
        ];
    }

    /**
     * Removes a file's link to a record without deleting the file itself. Shortcut for unlinkFromRecords with a single Id.
     * @param contentDocumentId The file to unlink.
     * @param recordId The record to unlink it from.
     * @throws FileServiceException if the delete fails. No-op if either Id is null or no such link exists.
     */
    public static void unlinkFromRecord(Id contentDocumentId, Id recordId) {
        if (recordId == null) { return; }
        unlinkFromRecords(contentDocumentId, new Set<Id>{ recordId });
    }

    /**
     * Removes a file's links to several records in one DML statement, without deleting the file itself. The file
     * stays available anywhere else it's linked.
     * @param contentDocumentId The file to unlink.
     * @param recordIds The records to unlink it from.
     * @throws FileServiceException if the delete fails. No-op if null/empty or no such links exist.
     */
    public static void unlinkFromRecords(Id contentDocumentId, Set<Id> recordIds) {
        if (contentDocumentId == null || recordIds == null || recordIds.isEmpty()) { return; }
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId AND LinkedEntityId IN :recordIds
        ];
        if (links.isEmpty()) { return; }
        try {
            delete links;
        } catch (DmlException ex) {
            throw wrap('Failed to unlink file ' + contentDocumentId + ' from ' + links.size() + ' record(s)', ex);
        }
    }

    /**
     * Returns the latest version of a file, without its binary content (see getFileBody for that).
     * @param contentDocumentId The file's ContentDocument Id.
     * @return The latest ContentVersion, or null if contentDocumentId is null or not found.
     */
    public static ContentVersion getLatestVersion(Id contentDocumentId) {
        if (contentDocumentId == null) { return null; }
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, PathOnClient, FileExtension, FileType, ContentSize, VersionNumber, Description, CreatedDate, CreatedById
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0];
    }

    /**
     * Returns the latest version of every file linked to a record, newest first.
     * @param recordId The record whose files to list.
     * @return Latest ContentVersions without binary content. Empty if recordId is null or nothing is linked.
     */
    public static List<ContentVersion> getFilesForRecord(Id recordId) {
        if (recordId == null) { return new List<ContentVersion>(); }
        List<ContentVersion> files = getFilesForRecords(new Set<Id>{ recordId }).get(recordId);
        return files != null ? files : new List<ContentVersion>();
    }

    /**
     * Bulk version of getFilesForRecord: two queries total no matter how many records are passed.
     * @param recordIds The records whose files to list. Can be null.
     * @return A map from each record Id that has at least one file to its files' latest versions, newest first.
     */
    public static Map<Id, List<ContentVersion>> getFilesForRecords(Set<Id> recordIds) {
        Map<Id, List<ContentVersion>> filesByRecord = new Map<Id, List<ContentVersion>>();
        if (recordIds == null || recordIds.isEmpty()) { return filesByRecord; }

        Map<Id, Set<Id>> recordIdsByDocument = new Map<Id, Set<Id>>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :recordIds
        ]) {
            if (!recordIdsByDocument.containsKey(link.ContentDocumentId)) {
                recordIdsByDocument.put(link.ContentDocumentId, new Set<Id>());
            }
            recordIdsByDocument.get(link.ContentDocumentId).add(link.LinkedEntityId);
        }
        if (recordIdsByDocument.isEmpty()) { return filesByRecord; }

        for (ContentVersion version : [
            SELECT Id, ContentDocumentId, Title, PathOnClient, FileExtension, FileType, ContentSize, VersionNumber, Description, CreatedDate, CreatedById
            FROM ContentVersion
            WHERE ContentDocumentId IN :recordIdsByDocument.keySet() AND IsLatest = true
            ORDER BY CreatedDate DESC
        ]) {
            for (Id recordId : recordIdsByDocument.get(version.ContentDocumentId)) {
                if (!filesByRecord.containsKey(recordId)) {
                    filesByRecord.put(recordId, new List<ContentVersion>());
                }
                filesByRecord.get(recordId).add(version);
            }
        }
        return filesByRecord;
    }

    /**
     * Returns the binary content of a file's latest version, for processing it in Apex (parsing a CSV, forwarding
     * it in a callout, attaching it to an email). Counts fully against the heap limit (6 MB synchronous,
     * 12 MB asynchronous), so it isn't suitable for very large files.
     * @param contentDocumentId The file's ContentDocument Id.
     * @return The latest version's content, or null if contentDocumentId is null or not found.
     */
    public static Blob getFileBody(Id contentDocumentId) {
        if (contentDocumentId == null) { return null; }
        List<ContentVersion> versions = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0].VersionData;
    }

    /**
     * Returns a file's latest version as a Base64 string, the usual way to hand a file to a Lightning web
     * component (which can rebuild it into a downloadable Blob). Same heap limits as getFileBody, and Base64
     * grows the content by about a third.
     * @param contentDocumentId The file's ContentDocument Id.
     * @return The Base64-encoded content, or null if contentDocumentId is null or not found.
     */
    public static String getFileAsBase64(Id contentDocumentId) {
        Blob body = getFileBody(contentDocumentId);
        return body == null ? null : EncodingUtil.base64Encode(body);
    }

    /**
     * Builds the URL that downloads a file's latest version. It needs an authenticated Salesforce session, so
     * it works for a logged-in user opening it in a browser or a Lightning component, not for anonymous access
     * (see createPublicLink for that). Doesn't check that the file exists or that the user can access it.
     * Experience Cloud sites serve this path under their own base URL, so build it there instead.
     * @param contentDocumentId The file's ContentDocument Id.
     * @return An absolute download URL on the org's My Domain, or null if contentDocumentId is null.
     */
    public static String getDownloadUrl(Id contentDocumentId) {
        if (contentDocumentId == null) { return null; }
        return URL.getOrgDomainUrl().toExternalForm() + DOWNLOAD_DOCUMENT_PATH + contentDocumentId;
    }

    /**
     * Builds the URL that downloads one specific version of a file. Same authentication caveats as getDownloadUrl.
     * @param contentVersionId The ContentVersion Id.
     * @return An absolute download URL on the org's My Domain, or null if contentVersionId is null.
     */
    public static String getVersionDownloadUrl(Id contentVersionId) {
        if (contentVersionId == null) { return null; }
        return URL.getOrgDomainUrl().toExternalForm() + DOWNLOAD_VERSION_PATH + contentVersionId;
    }

    /**
     * Permanently deletes a file, including all its versions and every link to every record. Shortcut for deleteFiles.
     * @param contentDocumentId The file to delete.
     * @throws FileServiceException if the delete fails. No-op if contentDocumentId is null or not found.
     */
    public static void deleteFile(Id contentDocumentId) {
        if (contentDocumentId == null) { return; }
        deleteFiles(new Set<Id>{ contentDocumentId });
    }

    /**
     * Permanently deletes files, including all their versions and every link to every record. The cascaded
     * ContentDocumentLink deletes don't fire ContentDocumentLink triggers; ContentDocument triggers do fire.
     * @param contentDocumentIds The files to delete.
     * @throws FileServiceException if the delete fails. No-op if null/empty; Ids that don't exist are skipped.
     */
    public static void deleteFiles(Set<Id> contentDocumentIds) {
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) { return; }
        List<ContentDocument> documents = [SELECT Id FROM ContentDocument WHERE Id IN :contentDocumentIds];
        if (documents.isEmpty()) { return; }
        try {
            delete documents;
        } catch (DmlException ex) {
            throw wrap('Failed to delete ' + documents.size() + ' file(s)', ex);
        }
    }

    /**
     * Creates a public link anyone with the URL can open, without logging in. Safe to call twice for the same version:
     * returns the existing link instead of creating a second one. Requires public links to be enabled in the org's
     * file sharing settings, otherwise the insert fails.
     * @param contentVersionId The specific version to expose (use getLatestVersion(...).Id for the current one).
     * @return The ContentDistribution, with DistributionPublicUrl and ContentDownloadUrl populated.
     * @throws FileServiceException if contentVersionId is null/not found, or the insert fails (commonly: public links not enabled).
     */
    public static ContentDistribution createPublicLink(Id contentVersionId) {
        if (contentVersionId == null) { throw new FileServiceException('Cannot create a public link without a contentVersionId.'); }
        List<ContentDistribution> existing = [
            SELECT Id, ContentVersionId, DistributionPublicUrl, ContentDownloadUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :contentVersionId
            LIMIT 1
        ];
        if (!existing.isEmpty()) { return existing[0]; }

        ContentVersion version = getVersionById(contentVersionId);
        ContentDistribution distribution = new ContentDistribution(
            Name = version.Title,
            ContentVersionId = contentVersionId,
            PreferencesAllowViewInBrowser = true
        );
        try {
            insert distribution;
        } catch (DmlException ex) {
            throw wrap('Failed to create a public link for version ' + contentVersionId, ex);
        }
        return [
            SELECT Id, ContentVersionId, DistributionPublicUrl, ContentDownloadUrl
            FROM ContentDistribution
            WHERE Id = :distribution.Id
        ];
    }

    private static ContentVersion getVersionById(Id contentVersionId) {
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, PathOnClient, FileExtension, FileType, ContentSize, VersionNumber, Description, CreatedDate, CreatedById
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];
        if (versions.isEmpty()) { throw new FileServiceException('ContentVersion ' + contentVersionId + ' not found.'); }
        return versions[0];
    }

    private static String getNameWithoutExtension(String fileName) {
        Integer dotIndex = fileName.lastIndexOf('.');
        return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    }

    private static FileServiceException wrap(String message, Exception cause) {
        FileServiceException wrapped = new FileServiceException(message + ': ' + cause.getMessage());
        wrapped.initCause(cause);
        return wrapped;
    }

    /**
     * Exception thrown when a file operation fails.
     */
    public class FileServiceException extends Exception {}
}
