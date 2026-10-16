# FileService

A centralized entry point for Salesforce Files. Every part of the org that needs to create a file, version it, share it with records, list what's attached to a record, download it, or delete it goes through this class, so the `ContentVersion` / `ContentDocument` / `ContentDocumentLink` plumbing, the ShareType and Visibility rules, and error handling stay consistent everywhere.

## Contents

- `force-app/main/default/classes/FileService.cls` — the service itself.
- `force-app/main/default/classes/FileServiceTest.cls` — its test class, 96% code coverage with 10 test methods and no additional mock or helper classes (see [Testing](#testing) for what the remaining 4% is).

No custom metadata, labels, or Setup configuration is needed to use it. The only optional one is the org's public-links setting, if you use `createPublicLink` (see [Public links](#public-links)).

## How Salesforce Files fit together

Three objects are involved, and `FileService` hides most of that:

- **`ContentVersion`** — one uploaded version of a file, holding the actual bytes. Inserting your first one automatically creates the file's `ContentDocument`.
- **`ContentDocument`** — the file itself, stable across versions. Its `Id` (starts with `069`) is what you pass to almost every method here.
- **`ContentDocumentLink`** — one row per place the file is shared: its owner, each record it's attached to, each user, group, or library. Its `ShareType` and `Visibility` decide who can do what with it.

## ShareType and Visibility

`FileService` models both picklists as enums instead of strings, so an invalid value doesn't compile.

**`FileService.FileShareType`** — the permission the link grants:

| Value | API value | Meaning |
|---|---|---|
| `VIEWER` | `V` | Can view, not edit. The default whenever you don't pass one. |
| `COLLABORATOR` | `C` | Can view and edit. Meant for users, groups, and libraries. |
| `INFERRED` | `I` | Permission comes from the linked record (or from the library, for library links). |

**`FileService.FileVisibility`** — who can see the file on the linked record:

| Value | API value | Meaning |
|---|---|---|
| `ALL_USERS` | `AllUsers` | Every user with permission to see the file, external users included. |
| `INTERNAL_USERS` | `InternalUsers` | Only internal users with permission to see the file. |
| `SHARED_USERS` | `SharedUsers` | Users who can see the feed the file is posted to. Only for files shared with users, and only when the org's default sharing is private. |

Passing `null` for either one is always allowed: a null `shareType` means `VIEWER`, and a null `visibility` leaves the field unset so **Salesforce picks its own default** (for a record link made by an internal user, `InternalUsers`).

### Rules the platform enforces (verified against a real org)

These aren't `FileService` limitations — Salesforce rejects them, and `FileService` surfaces the rejection as a `FileServiceException`:

- **`COLLABORATOR` on a link to a record fails** (`Invalid sharing type C`), on both create and update. Use `VIEWER` or `INFERRED` for records.
- **`SHARED_USERS` on a link to a record fails** (`Visibility SharedUsers is not permitted for this linked record`).
- **`INFERRED` can't be used on a link to the Organization.** `FileService` checks this one itself before touching the database.
- **`COLLABORATOR` can never be created from an Apex trigger.** `FileService` checks this one itself too. If you need a file linked from inside a trigger, use `VIEWER` or `INFERRED`.
- Only internal users can change `Visibility`, and only on links to standard or custom object records — not users, groups, or libraries.

## Basic usage

### Create a file and attach it to a record

```apex
Blob pdf = Blob.valueOf('...');
ContentVersion created = FileService.createFile('contract.pdf', pdf, opp.Id);
```

The file name needs its extension: Salesforce reads the file type from it. The title defaults to the name without the extension (`contract`). To set one yourself:

```apex
ContentVersion created = FileService.createFile('Signed contract', 'contract.pdf', pdf, opp.Id);
```

Pass `null` as the record to create a file that isn't attached to anything yet.

### List the files on a record

```apex
for (ContentVersion file : FileService.getFilesForRecord(opp.Id)) {
    System.debug(file.Title + '.' + file.FileExtension + ' (' + file.ContentSize + ' bytes)');
}
```

Each result is the file's **latest** version, without its content. For several records at once, use the bulk form — it costs two queries however many records you pass:

```apex
Map<Id, List<ContentVersion>> filesByRecord = FileService.getFilesForRecords(new Set<Id>{ opp1.Id, opp2.Id });
```

### Attach an existing file to another record

```apex
FileService.linkToRecord(documentId, otherOpp.Id);
```

Calling it twice for the same file and record is safe: the existing link is returned untouched instead of failing on a duplicate.

### Choose the permission and visibility

```apex
FileService.linkToRecord(
    documentId,
    opp.Id,
    FileService.FileShareType.INFERRED,
    FileService.FileVisibility.INTERNAL_USERS
);
```

### Detach a file without deleting it

```apex
FileService.unlinkFromRecord(documentId, opp.Id);
```

The file stays available everywhere else it's linked. To delete the file itself, along with all its versions and every link:

```apex
FileService.deleteFile(documentId);
```

## Downloading a file

"Download" can mean three different things in Apex, so there are three answers:

**1. Use the bytes inside Apex** — parse a CSV, forward the file in a callout, attach it to an email:

```apex
Blob content = FileService.getFileBody(documentId);
List<String> lines = content.toString().split('\n');
```

**2. Hand the file to a Lightning web component** — as Base64, which the component can rebuild into a downloadable Blob:

```apex
@AuraEnabled
public static String getFileForDownload(Id documentId) {
    return FileService.getFileAsBase64(documentId);
}
```

**3. Give a logged-in user a link** — no bytes pass through Apex at all:

```apex
String latest = FileService.getDownloadUrl(documentId);
String specific = FileService.getVersionDownloadUrl(versionId);
```

These URLs need an authenticated Salesforce session, so they work for someone logged in opening them in a browser, not for anonymous access. They also don't check that the file exists or that the user can see it, and they point at the org's My Domain — an Experience Cloud site serves the same path under its own base URL, so build it there instead.

`getFileBody` and `getFileAsBase64` load the whole file into memory, so they count fully against the heap limit (6 MB synchronous, 12 MB asynchronous, and Base64 adds about a third). They aren't suitable for very large files — use a download URL for those.

## Public links

For access without logging in, `createPublicLink` creates a `ContentDistribution` for one version:

```apex
ContentVersion latest = FileService.getLatestVersion(documentId);
ContentDistribution link = FileService.createPublicLink(latest.Id);

System.debug(link.DistributionPublicUrl);  // opens the file in a browser, no login
System.debug(link.ContentDownloadUrl);     // downloads it directly
```

Calling it again for the same version returns the existing link. The link points at that specific version — if you upload a new version later, create a link for it too. This needs public links enabled in the org's file sharing settings; without it the insert fails and `createPublicLink` throws a `FileServiceException`.

## Versions

```apex
ContentVersion v2 = FileService.createNewVersion(documentId, 'contract-v2.pdf', newBytes, 'Fixed the payment terms');
```

Every record the file is linked to sees the new version automatically — you don't re-link anything. `getLatestVersion` and `getFileBody` always return the newest one.

## Complete example

Combines most of it: generates a document for an opportunity, attaches it to the opportunity as an internal-only file, also attaches it to the related account's other open opportunities, versions it on a later change, and hands it to a component. Illustrative — `ProposalService` isn't part of this repo, only `FileService` is.

```apex
public with sharing class ProposalService {

    public static ContentVersion publishProposal(Opportunity opp, Blob proposalPdf, Set<Id> siblingOpportunityIds) {
        ContentVersion proposal = FileService.createFile(
            'Proposal - ' + opp.Name,
            'proposal-' + opp.Id + '.pdf',
            proposalPdf,
            opp.Id,
            FileService.FileShareType.INFERRED,
            FileService.FileVisibility.INTERNAL_USERS
        );

        FileService.linkToRecords(
            proposal.ContentDocumentId,
            siblingOpportunityIds,
            FileService.FileShareType.VIEWER,
            FileService.FileVisibility.INTERNAL_USERS
        );

        return proposal;
    }

    public static void replaceProposal(Id contentDocumentId, Blob revisedPdf) {
        FileService.createNewVersion(contentDocumentId, 'proposal-revised.pdf', revisedPdf, 'Revised after legal review');
    }

    public static void shareWithCustomer(Id contentDocumentId, Id oppId) {
        FileService.updateLink(contentDocumentId, oppId, null, FileService.FileVisibility.ALL_USERS);
    }

    @AuraEnabled
    public static String downloadProposal(Id contentDocumentId) {
        return FileService.getFileAsBase64(contentDocumentId);
    }
}
```

`createFile` with a ShareType and Visibility is all-or-nothing: if the link is rejected, the file isn't left behind. `linkToRecords` is one DML statement however many records you pass.

## Changing and inspecting links

```apex
FileService.updateLink(documentId, opp.Id, null, FileService.FileVisibility.ALL_USERS);
```

`updateLink` changes only what you pass — a `null` leaves that field as it is. It throws if the file isn't linked to the record. To see who a file is shared with:

```apex
for (ContentDocumentLink link : FileService.getLinks(documentId)) {
    System.debug(link.LinkedEntityId + ' -> ' + link.ShareType + ' / ' + link.Visibility);
}
```

The list always includes the file's owner.

## Error handling

Anything that can fail on a write — invalid arguments, a rejected ShareType or Visibility, an Id that doesn't exist or you can't access, public links being disabled — is thrown as a single `FileService.FileServiceException`, with the original `DmlException` as its cause, so callers only need one `catch`:

```apex
try {
    FileService.linkToRecord(documentId, opp.Id, FileService.FileShareType.COLLABORATOR, null);
} catch (FileService.FileServiceException ex) {
    System.debug(ex.getMessage());
}
```

Methods that only read, or that remove something, are forgiving instead: a `null` or unknown Id gives back `null` or an empty list (and `unlink*` and `delete*` do nothing) rather than throwing. Methods that create or link something throw on missing required arguments, since returning nothing there would hide a bug.

## What you should NOT do

- Don't pass a file name without its extension and expect Salesforce to know the type — it reads the type from the extension.
- Don't use `COLLABORATOR` or `SHARED_USERS` on a link to a record — Salesforce rejects both.
- Don't call `getFileBody` or `getFileAsBase64` on large files — they load everything into heap. Use `getDownloadUrl` or `createPublicLink`.
- Don't expect `linkToRecord` to change an existing link — it returns it as it is, even if you passed a different ShareType or Visibility. Use `updateLink`.
- Don't hand `getDownloadUrl` to someone who isn't logged in — use `createPublicLink` for that.
- Don't run a `ContentDocumentLink` query of your own without filtering on `Id`, `ContentDocumentId`, or `LinkedEntityId` — Salesforce rejects unfiltered queries, which is why `FileService` always filters on one of them.

## Testing

`FileServiceTest` deploys and runs at **96% code coverage** with 10 test methods and no additional mock or helper classes. It creates real files and links against real `Opportunity` records, and covers creating, versioning, linking, updating, unlinking, deleting, the bulk reads, the download URLs, the all-or-nothing rollback, and each platform rule above.

What it doesn't reach, and why:

- **The "`COLLABORATOR` from an Apex trigger" guard** can only run inside a trigger, and this repo ships no trigger on a file object.
- **The DML `catch` blocks of `unlinkFromRecords`, `deleteFiles`, and `createPublicLink`** need Salesforce to reject an otherwise valid delete or insert, and there's no way to force that from a test.

One test, `testPublicLinkIsCreatedOnceAndReused`, depends on the org having public links enabled. If it doesn't, the test accepts the resulting `FileServiceException` instead of failing, so it never blocks a deploy to an org where that setting is off — it just covers less there.
