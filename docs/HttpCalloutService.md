# HttpCalloutService

A centralized entry point for outbound HTTP callouts. Every integration builds and sends its request through this class instead of hand-rolling `HttpRequest`/`Http` boilerplate at each call site, so timeout handling, JSON serialization, and error handling stay consistent across the org.

## Contents

- `force-app/main/default/classes/HttpCalloutService.cls` — the service itself.
- `force-app/main/default/classes/HttpCalloutServiceTest.cls` — its test class, 100% code coverage.

## Quick reference

### GET

```apex
HttpResponse response = HttpCalloutService.doGet('callout:My_Named_Credential/v1/accounts', null, null);
HttpCalloutService.validateResponse(response, 'Failed to fetch accounts');
```

### POST with a raw body

```apex
HttpResponse response = HttpCalloutService.doPost(
    'callout:My_Named_Credential/v1/accounts',
    '{"name":"Acme"}',
    null,
    null
);
```

### POST with a JSON object (Content-Type is set for you)

```apex
HttpResponse response = HttpCalloutService.doPostJson(
    'callout:My_Named_Credential/v1/accounts',
    new Map<String, Object>{ 'name' => 'Acme' },
    null,
    null
);
```

`doPutJson` and `doPatchJson` work the same way. `doPut`, `doPatch`, and `doDelete` (named `doDelete` — `delete` is a reserved word in Apex) round out the rest of the verbs.

### Custom headers and timeout

Every verb method takes `headers` (`Map<String, String>`, or `null`) and `timeoutMs` (`Integer`, or `null` to use the 30-second default) as its last two arguments:

```apex
HttpResponse response = HttpCalloutService.doGet(
    'callout:My_Named_Credential/v1/accounts',
    new Map<String, String>{ 'X-Request-Id' => requestId },
    5000
);
```

### Validating and parsing the response

```apex
HttpResponse response = HttpCalloutService.doGet('callout:My_Named_Credential/v1/accounts/001xx', null, null);
HttpCalloutService.validateResponse(response, 'Failed to fetch account'); // throws HttpCalloutService.HttpCalloutException if not 2xx

AccountWrapper result = (AccountWrapper) HttpCalloutService.parseResponse(response, AccountWrapper.class);
```

`parseResponse` is a separate step on purpose — call `isResponseSuccessful`/`validateResponse` first, since an error response's body usually won't match the shape you're trying to parse into.

### Checking the callout limit

```apex
if (HttpCalloutService.remainingCallouts() > 0) {
    HttpCalloutService.doGet(...);
}
```

## Complete examples

The snippets above show one call at a time. These two show every method working together in something closer to real integration code. They're illustrative — classes like `AccountSyncService`, `ExternalAccountResponse`, `Legacy_System_Credential__mdt`, and `Logger` aren't part of this repo; only `HttpCalloutService` itself is.

### Example 1 — upsert pattern (GET to check, then POST or PATCH)

Checks the callout budget up front, looks up whether the record already exists remotely, creates it if not, updates only the changed fields if it does, then parses the external ID back onto the Salesforce record.

```apex
public class ExternalAccountResponse {
    public String id;
    public String name;
}

public class AccountSyncService {

    public class CalloutLimitException extends Exception {}

    public static void syncAccount(Account acc, String externalId) {
        // remainingCallouts() — bail out early instead of risking a LimitException mid-sync.
        if (HttpCalloutService.remainingCallouts() < 2) {
            throw new CalloutLimitException('Not enough callouts remaining in this transaction to sync ' + acc.Id);
        }

        String baseEndpoint = 'callout:My_Named_Credential/v1/accounts';

        // doGet() — check whether the record already exists remotely.
        HttpResponse existing = HttpCalloutService.doGet(baseEndpoint + '/' + externalId, null, null);

        HttpResponse response;
        if (HttpCalloutService.isResponseSuccessful(existing)) {
            // doPatchJson() — it exists, send only the fields that changed.
            response = HttpCalloutService.doPatchJson(
                baseEndpoint + '/' + externalId,
                new Map<String, Object>{ 'name' => acc.Name },
                null,
                null
            );
        } else {
            // doPostJson() — doesn't exist yet, create it.
            response = HttpCalloutService.doPostJson(
                baseEndpoint,
                new Map<String, Object>{ 'name' => acc.Name, 'salesforceId' => acc.Id },
                null,
                null
            );
        }

        // validateResponse() — throws HttpCalloutService.HttpCalloutException if not 2xx.
        HttpCalloutService.validateResponse(response, 'Failed to sync Account ' + acc.Id);

        // parseResponse() — only called once we know the response is a success.
        ExternalAccountResponse result = (ExternalAccountResponse) HttpCalloutService.parseResponse(response, ExternalAccountResponse.class);
        acc.External_Id__c = result.id;
    }
}
```

### Example 2 — raw bodies, custom headers/timeout, and a soft-delete check

A legacy system that speaks XML instead of JSON, needs a custom API-key header on every call, a longer timeout for a slow archive endpoint, and treats "already gone" as success on delete instead of throwing.

```apex
public class LegacyRecordCleanupService {

    public static void archiveAndRemove(String legacyId, String payloadXml) {
        String endpoint = 'callout:Legacy_System/v1/records/' + legacyId;
        Map<String, String> authHeaders = new Map<String, String>{
            'X-Api-Key' => Legacy_System_Credential__mdt.getInstance('Default').Api_Key__c
        };

        // doPost() with a raw XML body and a custom Content-Type + longer timeout for a slow endpoint.
        HttpResponse archiveResponse = HttpCalloutService.doPost(
            endpoint + '/archive',
            payloadXml,
            new Map<String, String>{ 'Content-Type' => 'application/xml' },
            15000
        );
        HttpCalloutService.validateResponse(archiveResponse, 'Failed to archive legacy record ' + legacyId);

        // doPut() — full replace of the record's status.
        HttpCalloutService.doPut(endpoint, '<record><status>ARCHIVED</status></record>', authHeaders, null);

        // doPatch() — a raw-body partial update.
        HttpCalloutService.doPatch(endpoint, '<record><locked>true</locked></record>', authHeaders, null);

        // doPutJson() — the same kind of full replace, for the parts of this system that do accept JSON.
        HttpCalloutService.doPutJson(endpoint + '/metadata', new Map<String, Object>{ 'archived' => true }, authHeaders, null);

        // doDelete() with isResponseSuccessful() instead of validateResponse() — treat "already gone" (404) as success.
        HttpResponse deleteResponse = HttpCalloutService.doDelete(endpoint, authHeaders, null);
        if (!HttpCalloutService.isResponseSuccessful(deleteResponse) && deleteResponse.getStatusCode() != 404) {
            HttpCalloutService.validateResponse(deleteResponse, 'Failed to delete legacy record ' + legacyId);
        }
    }
}
```

Between the two examples, every method on `HttpCalloutService` is used: `doGet`, `doPost`, `doPostJson`, `doPut`, `doPutJson`, `doPatch`, `doPatchJson`, `doDelete`, `validateResponse`, `isResponseSuccessful`, `parseResponse`, and `remainingCallouts`.

## Error handling

Every failure — network-level (timeout, unauthorized endpoint) or a non-2xx status via `validateResponse` — surfaces as a single `HttpCalloutService.HttpCalloutException`, so callers only need one `catch` block regardless of what went wrong:

```apex
try {
    AccountSyncService.syncAccount(acc, externalId);
} catch (HttpCalloutService.HttpCalloutException ex) {
    // Same catch block whether the callout timed out, the endpoint was unreachable,
    // or the external system returned a 4xx/5xx.
    Logger.log(ex.getMessage());
}
```

## Testing

`HttpCalloutServiceTest` deploys and runs at **100% code coverage** with a single inner mock (`CalloutMock`) that records every request it receives and can be configured to return a fixed status/body or simulate a network failure. No separate mock classes are needed to test this service.
