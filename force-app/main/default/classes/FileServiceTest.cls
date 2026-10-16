@isTest
private class FileServiceTest {

    private static final Id FAKE_OPPORTUNITY_ID = '006000000000000AAA';
    private static final Id FAKE_DOCUMENT_ID = '069000000000000AAA';
    private static final Id FAKE_VERSION_ID = '068000000000000AAA';

    private static Opportunity createOpportunity(String name) {
        Opportunity opp = new Opportunity(Name = name, StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert opp;
        return opp;
    }

    private static ContentVersion createUnlinkedFile(String fileName) {
        return FileService.createFile(fileName, Blob.valueOf('content of ' + fileName), null);
    }

    private static ContentDocumentLink queryLink(Id contentDocumentId, Id recordId) {
        return [
            SELECT Id, ShareType, Visibility
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId AND LinkedEntityId = :recordId
        ];
    }

    @isTest
    static void testCreateFileAndReadItBack() {
        Opportunity opp = createOpportunity('File Test 1');
        Opportunity otherOpp = createOpportunity('File Test 2');
        Blob content = Blob.valueOf('hello file');

        ContentVersion created = FileService.createFile('report.pdf', content, opp.Id);

        Assert.isNotNull(created.ContentDocumentId, 'the re-queried version carries its document Id');
        Assert.areEqual('report', created.Title, 'the title defaults to the file name without its extension');
        Assert.areEqual('pdf', created.FileExtension, 'the extension comes from the file name');
        Assert.areEqual(created.Id, FileService.getLatestVersion(created.ContentDocumentId).Id, 'the only version is the latest');
        Assert.areEqual('hello file', FileService.getFileBody(created.ContentDocumentId).toString(), 'the body round-trips');
        Assert.areEqual(EncodingUtil.base64Encode(content), FileService.getFileAsBase64(created.ContentDocumentId), 'the Base64 form matches the body');

        ContentVersion shared = FileService.createFile('Custom Title', 'notes.txt', content, opp.Id);
        FileService.linkToRecord(shared.ContentDocumentId, otherOpp.Id);
        Assert.areEqual('Custom Title', shared.Title, 'an explicit title wins over the file name');
        Assert.areEqual(2, FileService.getFilesForRecord(opp.Id).size(), 'both files are linked to the first record');

        Map<Id, List<ContentVersion>> filesByRecord = FileService.getFilesForRecords(new Set<Id>{ opp.Id, otherOpp.Id });
        Assert.areEqual(2, filesByRecord.get(opp.Id).size(), 'bulk lookup groups files per record');
        Assert.areEqual(1, filesByRecord.get(otherOpp.Id).size(), 'a file linked to two records shows under both');

        Assert.areEqual('noextension', FileService.createFile(null, 'noextension', content, null).Title, 'a name without a dot is used whole');
        Assert.areEqual('.hidden', FileService.createFile(null, '.hidden', content, null).Title, 'a leading dot is not treated as an extension');
    }

    @isTest
    static void testNullAndEmptyArgumentsAreHandledGracefully() {
        Opportunity opp = createOpportunity('File Test 3');

        Assert.isNull(FileService.getLatestVersion(null), 'null document gives null');
        Assert.isNull(FileService.getLatestVersion(FAKE_DOCUMENT_ID), 'unknown document gives null');
        Assert.isNull(FileService.getFileBody(null), 'null document gives no body');
        Assert.isNull(FileService.getFileBody(FAKE_DOCUMENT_ID), 'unknown document gives no body');
        Assert.isNull(FileService.getFileAsBase64(null), 'null document gives no Base64');
        Assert.isNull(FileService.getDownloadUrl(null), 'null document gives no URL');
        Assert.isNull(FileService.getVersionDownloadUrl(null), 'null version gives no URL');
        Assert.isTrue(FileService.getFilesForRecord(null).isEmpty(), 'null record has no files');
        Assert.isTrue(FileService.getFilesForRecord(opp.Id).isEmpty(), 'a record with nothing linked has no files');
        Assert.isTrue(FileService.getFilesForRecords(null).isEmpty(), 'null set has no files');
        Assert.isTrue(FileService.getFilesForRecords(new Set<Id>()).isEmpty(), 'empty set has no files');
        Assert.isTrue(FileService.getLinks(null).isEmpty(), 'null document has no links');
        Assert.isTrue(FileService.getLinks(FAKE_DOCUMENT_ID).isEmpty(), 'unknown document has no links');
        Assert.isTrue(FileService.linkToRecords(FAKE_DOCUMENT_ID, null, null, null).isEmpty(), 'null record set links nothing');
        Assert.isTrue(FileService.linkToRecords(FAKE_DOCUMENT_ID, new Set<Id>{ null }, null, null).isEmpty(), 'null entries are skipped');
        Assert.isTrue(FileService.linkToRecords(FAKE_DOCUMENT_ID, new Set<Id>(), null, null).isEmpty(), 'empty record set links nothing');
    }

    @isTest
    static void testInvalidInputAndPlatformFailuresAreWrapped() {
        Opportunity opp = createOpportunity('File Test 4');
        ContentVersion file = createUnlinkedFile('wrapped.txt');
        Blob content = Blob.valueOf('x');
        Integer wrapped = 0;

        try { FileService.createFile('', content, null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.createFile('a.txt', null, null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.createFile('a.txt', content, FAKE_OPPORTUNITY_ID); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.createNewVersion(null, 'a.txt', content, null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.createNewVersion(FAKE_DOCUMENT_ID, '', content, null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.createNewVersion(FAKE_DOCUMENT_ID, 'a.txt', null, null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.createNewVersion(FAKE_DOCUMENT_ID, 'a.txt', content, null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.linkToRecord(null, opp.Id); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.linkToRecord(file.ContentDocumentId, null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.linkToRecord(file.ContentDocumentId, FAKE_OPPORTUNITY_ID); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.updateLink(null, opp.Id, null, null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.updateLink(file.ContentDocumentId, opp.Id, null, null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.createPublicLink(null); } catch (FileService.FileServiceException ex) { wrapped++; }
        try { FileService.createPublicLink(FAKE_VERSION_ID); } catch (FileService.FileServiceException ex) { wrapped++; }

        Assert.areEqual(14, wrapped, 'every invalid input or failed DML surfaces as a FileServiceException');
        Assert.areEqual(1, FileService.getLinks(file.ContentDocumentId).size(), 'no failed attempt left a link behind');
    }

    @isTest
    static void testCreateNewVersionAndDownloadUrls() {
        ContentVersion first = createUnlinkedFile('contract.pdf');

        ContentVersion second = FileService.createNewVersion(first.ContentDocumentId, 'contract-v2.pdf', Blob.valueOf('version two'), 'fixed a typo');

        Assert.areEqual(first.ContentDocumentId, second.ContentDocumentId, 'a new version stays on the same document');
        Assert.areEqual('2', second.VersionNumber, 'the version number increments');
        Assert.areEqual(second.Id, FileService.getLatestVersion(first.ContentDocumentId).Id, 'the new version is now the latest');
        Assert.areEqual('version two', FileService.getFileBody(first.ContentDocumentId).toString(), 'the body is the latest version\'s');

        String orgUrl = URL.getOrgDomainUrl().toExternalForm();
        Assert.areEqual(orgUrl + '/sfc/servlet.shepherd/document/download/' + first.ContentDocumentId, FileService.getDownloadUrl(first.ContentDocumentId), 'document download URL');
        Assert.areEqual(orgUrl + '/sfc/servlet.shepherd/version/download/' + second.Id, FileService.getVersionDownloadUrl(second.Id), 'version download URL');
    }

    @isTest
    static void testLinkOptionsAndIdempotency() {
        Opportunity oppA = createOpportunity('File Test 5');
        Opportunity oppB = createOpportunity('File Test 6');
        ContentVersion file = createUnlinkedFile('shared.txt');
        Id documentId = file.ContentDocumentId;

        ContentDocumentLink viewerLink = FileService.linkToRecord(documentId, oppA.Id);
        Assert.areEqual('V', queryLink(documentId, oppA.Id).ShareType, 'the default share type is Viewer');
        Assert.areEqual(viewerLink.Id, FileService.linkToRecord(documentId, oppA.Id).Id, 'linking twice returns the existing link');

        List<ContentDocumentLink> links = FileService.linkToRecords(
            documentId,
            new Set<Id>{ oppA.Id, oppB.Id, null },
            FileService.FileShareType.INFERRED,
            FileService.FileVisibility.INTERNAL_USERS
        );

        Assert.areEqual(2, links.size(), 'one link per non-null record');
        ContentDocumentLink newLink = queryLink(documentId, oppB.Id);
        Assert.areEqual('I', newLink.ShareType, 'the new link uses the requested share type');
        Assert.areEqual('InternalUsers', newLink.Visibility, 'the new link uses the requested visibility');
        Assert.areEqual('V', queryLink(documentId, oppA.Id).ShareType, 'an existing link is left untouched');
        Assert.areEqual(3, FileService.getLinks(documentId).size(), 'the owner plus the two records');

        FileService.linkToRecord(createUnlinkedFile('all.txt').ContentDocumentId, oppA.Id, FileService.FileShareType.VIEWER, FileService.FileVisibility.ALL_USERS);
        Assert.areEqual(2, FileService.getFilesForRecord(oppA.Id).size(), 'AllUsers visibility is accepted on a record link');
    }

    @isTest
    static void testPlatformRulesForShareTypeAndVisibilityAreSurfaced() {
        Opportunity opp = createOpportunity('File Test 7');
        Id documentId = createUnlinkedFile('rules.txt').ContentDocumentId;
        Integer rejected = 0;

        try { FileService.linkToRecord(documentId, opp.Id, FileService.FileShareType.COLLABORATOR, null); } catch (FileService.FileServiceException ex) { rejected++; }
        try { FileService.linkToRecord(documentId, opp.Id, FileService.FileShareType.VIEWER, FileService.FileVisibility.SHARED_USERS); } catch (FileService.FileServiceException ex) { rejected++; }
        try { FileService.linkToRecord(documentId, Id.valueOf(UserInfo.getOrganizationId()), FileService.FileShareType.INFERRED, null); } catch (FileService.FileServiceException ex) { rejected++; }
        FileService.linkToRecord(documentId, opp.Id);
        try { FileService.updateLink(documentId, opp.Id, FileService.FileShareType.COLLABORATOR, null); } catch (FileService.FileServiceException ex) { rejected++; }

        Assert.areEqual(4, rejected, 'Collaborator and SharedUsers on a record, Inferred on the Organization, and Collaborator on update, are all rejected');
        Assert.areEqual('V', queryLink(documentId, opp.Id).ShareType, 'the rejected update changed nothing');
        Assert.areEqual(2, FileService.getLinks(documentId).size(), 'only the owner and the one valid link exist');
    }

    @isTest
    static void testUpdateLinkChangesOnlyWhatIsPassed() {
        Opportunity opp = createOpportunity('File Test 8');
        Id documentId = createUnlinkedFile('update.txt').ContentDocumentId;
        FileService.linkToRecord(documentId, opp.Id);

        FileService.updateLink(documentId, opp.Id, FileService.FileShareType.INFERRED, FileService.FileVisibility.INTERNAL_USERS);
        ContentDocumentLink changed = queryLink(documentId, opp.Id);
        Assert.areEqual('I', changed.ShareType, 'share type updated');
        Assert.areEqual('InternalUsers', changed.Visibility, 'visibility updated');

        FileService.updateLink(documentId, opp.Id, null, FileService.FileVisibility.ALL_USERS);
        ContentDocumentLink visibilityOnly = queryLink(documentId, opp.Id);
        Assert.areEqual('I', visibilityOnly.ShareType, 'a null share type leaves it unchanged');
        Assert.areEqual('AllUsers', visibilityOnly.Visibility, 'the passed visibility is applied');

        FileService.updateLink(documentId, opp.Id, FileService.FileShareType.VIEWER, null);
        ContentDocumentLink shareTypeOnly = queryLink(documentId, opp.Id);
        Assert.areEqual('V', shareTypeOnly.ShareType, 'the passed share type is applied');
        Assert.areEqual('AllUsers', shareTypeOnly.Visibility, 'a null visibility leaves it unchanged');
    }

    @isTest
    static void testCreateFileWithShareTypeIsAllOrNothing() {
        Opportunity opp = createOpportunity('File Test 9');
        Blob content = Blob.valueOf('x');

        ContentVersion linked = FileService.createFile('Linked', 'linked.txt', content, opp.Id, FileService.FileShareType.INFERRED, FileService.FileVisibility.INTERNAL_USERS);
        ContentDocumentLink link = queryLink(linked.ContentDocumentId, opp.Id);
        Assert.areEqual('I', link.ShareType, 'the file was linked with the requested share type');
        Assert.areEqual('InternalUsers', link.Visibility, 'the file was linked with the requested visibility');

        ContentVersion unlinked = FileService.createFile(null, 'unlinked.txt', content, null, FileService.FileShareType.VIEWER, FileService.FileVisibility.ALL_USERS);
        Assert.areEqual(1, FileService.getLinks(unlinked.ContentDocumentId).size(), 'without a record, only the owner link exists');

        Integer versionsBefore = [SELECT COUNT() FROM ContentVersion];
        try {
            FileService.createFile(null, 'rollback.txt', content, Id.valueOf(UserInfo.getOrganizationId()), FileService.FileShareType.INFERRED, null);
            Assert.fail('an invalid link should have thrown');
        } catch (FileService.FileServiceException ex) {
            Assert.isTrue(ex.getMessage().contains('Organization'), 'the link rule is reported');
        }
        Assert.areEqual(versionsBefore, [SELECT COUNT() FROM ContentVersion], 'the file creation was rolled back with the failed link');
    }

    @isTest
    static void testUnlinkAndDelete() {
        Opportunity oppA = createOpportunity('File Test 10');
        Opportunity oppB = createOpportunity('File Test 11');
        Id documentId = createUnlinkedFile('remove.txt').ContentDocumentId;
        Id otherDocumentId = createUnlinkedFile('remove-too.txt').ContentDocumentId;
        FileService.linkToRecords(documentId, new Set<Id>{ oppA.Id, oppB.Id }, null, null);

        FileService.unlinkFromRecord(documentId, oppA.Id);
        Assert.isTrue(FileService.getFilesForRecord(oppA.Id).isEmpty(), 'the first record no longer has the file');
        Assert.areEqual(1, FileService.getFilesForRecord(oppB.Id).size(), 'the second record still has it');

        FileService.unlinkFromRecords(documentId, new Set<Id>{ oppB.Id });
        Assert.isTrue(FileService.getFilesForRecord(oppB.Id).isEmpty(), 'bulk unlink removed the last record link');

        FileService.unlinkFromRecord(documentId, oppB.Id);
        FileService.unlinkFromRecord(documentId, null);
        FileService.unlinkFromRecord(null, oppB.Id);
        FileService.unlinkFromRecords(documentId, null);
        FileService.unlinkFromRecords(documentId, new Set<Id>());
        FileService.deleteFile(null);
        FileService.deleteFile(FAKE_DOCUMENT_ID);
        FileService.deleteFiles(null);
        FileService.deleteFiles(new Set<Id>());
        Assert.areEqual(2, [SELECT COUNT() FROM ContentDocument WHERE Id IN :new Set<Id>{ documentId, otherDocumentId }], 'no-ops deleted nothing');

        FileService.deleteFile(documentId);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocument WHERE Id IN :new Set<Id>{ documentId, otherDocumentId }], 'deleteFile removed one document');

        FileService.deleteFiles(new Set<Id>{ otherDocumentId, FAKE_DOCUMENT_ID });
        Assert.areEqual(0, [SELECT COUNT() FROM ContentDocument WHERE Id IN :new Set<Id>{ documentId, otherDocumentId }], 'deleteFiles removed the rest and skipped the unknown Id');
    }

    @isTest
    static void testPublicLinkIsCreatedOnceAndReused() {
        ContentVersion version = createUnlinkedFile('public.txt');

        try {
            ContentDistribution first = FileService.createPublicLink(version.Id);
            Assert.isNotNull(first.DistributionPublicUrl, 'the public URL is populated');
            Assert.isNotNull(first.ContentDownloadUrl, 'the direct download URL is populated');
            Assert.areEqual(first.Id, FileService.createPublicLink(version.Id).Id, 'asking again reuses the existing link');
        } catch (FileService.FileServiceException ex) {
            Assert.isTrue(ex.getMessage().contains('public link'), 'the only acceptable failure is public links being disabled');
        }
    }
}
