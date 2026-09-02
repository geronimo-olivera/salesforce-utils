@IsTest
private class HttpCalloutServiceTest {

    @IsTest
    static void verbsSendCorrectRequestsAndReturnTheMockedResponse() {
        CalloutMock mock = new CalloutMock(200, '{"name":"Acme"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HttpResponse getResponse = HttpCalloutService.doGet('callout:Test/api/v1/test', new Map<String, String>{ 'X-Custom' => 'abc' }, null);
        HttpCalloutService.doPost('callout:Test/api/v1/test', '{"raw":"body"}', null, null);
        HttpCalloutService.doPostJson('callout:Test/api/v1/test', new Map<String, Object>{ 'name' => 'test' }, null, null);
        HttpCalloutService.doPut('callout:Test/api/v1/test', '{"raw":"body"}', null, null);
        HttpCalloutService.doPutJson('callout:Test/api/v1/test', new Map<String, Object>{ 'name' => 'test' }, null, null);
        HttpCalloutService.doPatch('callout:Test/api/v1/test', '{"raw":"body"}', null, null);
        HttpCalloutService.doPatchJson('callout:Test/api/v1/test', new Map<String, Object>{ 'name' => 'test' }, null, 5000);
        HttpCalloutService.doDelete('callout:Test/api/v1/test', null, null);
        Test.stopTest();

        Assert.areEqual(8, mock.capturedRequests.size(), 'All eight verb calls should have reached the mock.');

        Assert.areEqual('GET', mock.capturedRequests[0].getMethod());
        Assert.areEqual('abc', mock.capturedRequests[0].getHeader('X-Custom'), 'Caller-supplied headers must be preserved.');

        Assert.areEqual('POST', mock.capturedRequests[1].getMethod());
        Assert.areEqual('{"raw":"body"}', mock.capturedRequests[1].getBody());

        Assert.areEqual('POST', mock.capturedRequests[2].getMethod());
        Assert.areEqual('application/json', mock.capturedRequests[2].getHeader('Content-Type'), 'doPostJson must set Content-Type automatically.');
        Assert.areEqual('{"name":"test"}', mock.capturedRequests[2].getBody());

        Assert.areEqual('PUT', mock.capturedRequests[3].getMethod());
        Assert.areEqual('PUT', mock.capturedRequests[4].getMethod());
        Assert.areEqual('application/json', mock.capturedRequests[4].getHeader('Content-Type'));

        Assert.areEqual('PATCH', mock.capturedRequests[5].getMethod());
        Assert.areEqual('PATCH', mock.capturedRequests[6].getMethod());
        Assert.areEqual('application/json', mock.capturedRequests[6].getHeader('Content-Type'));

        Assert.areEqual('DELETE', mock.capturedRequests[7].getMethod());

        Assert.areEqual(200, getResponse.getStatusCode());
        Assert.areEqual('{"name":"Acme"}', getResponse.getBody());
    }

    @IsTest
    static void validateAndParseSucceedForA2xxResponse() {
        Test.setMock(HttpCalloutMock.class, new CalloutMock(200, '{"name":"Acme"}'));

        Test.startTest();
        HttpResponse response = HttpCalloutService.doGet('callout:Test/api/v1/test', null, null);
        HttpCalloutService.validateResponse(response, 'Should not fail');
        Map<String, String> parsed = (Map<String, String>) HttpCalloutService.parseResponse(response, Map<String, String>.class);
        Integer remaining = HttpCalloutService.remainingCallouts();
        Test.stopTest();

        Assert.isTrue(HttpCalloutService.isResponseSuccessful(response));
        Assert.areEqual('Acme', parsed.get('name'));
        Assert.isTrue(remaining >= 0, 'remainingCallouts should never be negative.');
    }

    @IsTest
    static void validateResponseThrowsForNonSuccessStatus() {
        Test.setMock(HttpCalloutMock.class, new CalloutMock(400, '{"error":"Bad Request"}'));

        Test.startTest();
        HttpResponse response = HttpCalloutService.doGet('callout:Test/api/v1/test', null, null);
        Assert.isFalse(HttpCalloutService.isResponseSuccessful(response));
        try {
            HttpCalloutService.validateResponse(response, 'Request failed');
            Assert.isTrue(false, 'Expected HttpCalloutException to be thrown.');
        } catch (HttpCalloutService.HttpCalloutException ex) {
            Assert.isTrue(ex.getMessage().contains('Request failed'));
            Assert.isTrue(ex.getMessage().contains('Status: 400'));
            Assert.isTrue(ex.getMessage().contains('Bad Request'));
        }
        Test.stopTest();
    }

    @IsTest
    static void sendWrapsCalloutExceptionAsHttpCalloutException() {
        CalloutMock mock = new CalloutMock(200, 'Success');
        mock.throwCalloutException = true;
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            HttpCalloutService.doGet('callout:Test/api/v1/test', null, null);
            Assert.isTrue(false, 'Expected HttpCalloutException to be thrown.');
        } catch (HttpCalloutService.HttpCalloutException ex) {
            Assert.isTrue(ex.getMessage().contains('Callout to'));
            Assert.isNotNull(ex.getCause(), 'The original CalloutException should be preserved as the cause.');
        }
        Test.stopTest();
    }

    private class CalloutMock implements HttpCalloutMock {
        List<HttpRequest> capturedRequests = new List<HttpRequest>();
        Integer statusCode;
        String responseBody;
        Boolean throwCalloutException = false;

        CalloutMock(Integer statusCode, String responseBody) {
            this.statusCode = statusCode;
            this.responseBody = responseBody;
        }

        public HttpResponse respond(HttpRequest request) {
            capturedRequests.add(request);
            if (throwCalloutException) {
                throw new System.CalloutException('Simulated network failure');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody(responseBody);
            return response;
        }
    }
}
