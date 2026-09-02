# HttpCalloutService

A centralized entry point for outbound HTTP callouts. Every integration builds and sends its request through this class instead of hand-rolling `HttpRequest`/`Http` boilerplate at each call site, so timeout handling, JSON serialization, and error handling stay consistent across the org.

## Contents

- `force-app/main/default/classes/HttpCalloutService.cls` — the service itself.
- `force-app/main/default/classes/HttpCalloutServiceTest.cls` — its test class, 100% code coverage.

## Usage

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

## Error handling

Every failure — network-level (timeout, unauthorized endpoint) or a non-2xx status via `validateResponse` — surfaces as a single `HttpCalloutService.HttpCalloutException`, so callers only need one `catch` block regardless of what went wrong.

## Testing

`HttpCalloutServiceTest` deploys and runs at **100% code coverage** with a single inner mock (`CalloutMock`) that records every request it receives and can be configured to return a fixed status/body or simulate a network failure. No separate mock classes are needed to test this service.
