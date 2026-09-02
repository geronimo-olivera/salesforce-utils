public inherited sharing class HttpCalloutService {
    
    private static final String GET_METHOD = 'GET';
    private static final String POST_METHOD = 'POST';
    private static final String PUT_METHOD = 'PUT';
    private static final String PATCH_METHOD = 'PATCH';
    private static final String DELETE_METHOD = 'DELETE';

    private static final Integer DEFAULT_TIMEOUT_MS = 30000;

    /**
     * Sends a GET callout.
     * @param endpoint The callout endpoint.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds. Pass null to use DEFAULT_TIMEOUT_MS.
     * @return The HttpResponse returned by the endpoint.
     */
    public static HttpResponse doGet(String endpoint, Map<String, String> headers, Integer timeoutMs) {
        return send(buildRequest(endpoint, GET_METHOD, null, headers, timeoutMs));
    }

    /**
     * Sends a POST callout with a raw string body.
     * @param endpoint The callout endpoint.
     * @param body The request body. Can be null.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds. Pass null to use DEFAULT_TIMEOUT_MS.
     * @return The HttpResponse returned by the endpoint.
     */
    public static HttpResponse doPost(String endpoint, String body, Map<String, String> headers, Integer timeoutMs) {
        return send(buildRequest(endpoint, POST_METHOD, body, headers, timeoutMs));
    }

    /**
     * Sends a POST callout, serializing bodyObject as the JSON request body.
     * @param endpoint The callout endpoint.
     * @param bodyObject Any object to serialize as JSON. Can be null.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds. Pass null to use DEFAULT_TIMEOUT_MS.
     * @return The HttpResponse returned by the endpoint.
     */
    public static HttpResponse doPostJson(String endpoint, Object bodyObject, Map<String, String> headers, Integer timeoutMs) {
        return send(buildJsonRequest(endpoint, POST_METHOD, bodyObject, headers, timeoutMs));
    }

    /**
     * Sends a PUT callout with a raw string body.
     * @param endpoint The callout endpoint.
     * @param body The request body. Can be null.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds. Pass null to use DEFAULT_TIMEOUT_MS.
     * @return The HttpResponse returned by the endpoint.
     */
    public static HttpResponse doPut(String endpoint, String body, Map<String, String> headers, Integer timeoutMs) {
        return send(buildRequest(endpoint, PUT_METHOD, body, headers, timeoutMs));
    }

    /**
     * Sends a PUT callout, serializing bodyObject as the JSON request body.
     * @param endpoint The callout endpoint.
     * @param bodyObject Any object to serialize as JSON. Can be null.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds. Pass null to use DEFAULT_TIMEOUT_MS.
     * @return The HttpResponse returned by the endpoint.
     */
    public static HttpResponse doPutJson(String endpoint, Object bodyObject, Map<String, String> headers, Integer timeoutMs) {
        return send(buildJsonRequest(endpoint, PUT_METHOD, bodyObject, headers, timeoutMs));
    }

    /**
     * Sends a PATCH callout with a raw string body.
     * @param endpoint The callout endpoint.
     * @param body The request body. Can be null.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds. Pass null to use DEFAULT_TIMEOUT_MS.
     * @return The HttpResponse returned by the endpoint.
     */
    public static HttpResponse doPatch(String endpoint, String body, Map<String, String> headers, Integer timeoutMs) {
        return send(buildRequest(endpoint, PATCH_METHOD, body, headers, timeoutMs));
    }

    /**
     * Sends a PATCH callout, serializing bodyObject as the JSON request body.
     * @param endpoint The callout endpoint.
     * @param bodyObject Any object to serialize as JSON. Can be null.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds. Pass null to use DEFAULT_TIMEOUT_MS.
     * @return The HttpResponse returned by the endpoint.
     */
    public static HttpResponse doPatchJson(String endpoint, Object bodyObject, Map<String, String> headers, Integer timeoutMs) {
        return send(buildJsonRequest(endpoint, PATCH_METHOD, bodyObject, headers, timeoutMs));
    }

    /**
     * Sends a DELETE callout.
     * @param endpoint The callout endpoint.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds. Pass null to use DEFAULT_TIMEOUT_MS.
     * @return The HttpResponse returned by the endpoint.
     */
    public static HttpResponse doDelete(String endpoint, Map<String, String> headers, Integer timeoutMs) {
        return send(buildRequest(endpoint, DELETE_METHOD, null, headers, timeoutMs));
    }

    /**
     * Builds an HttpRequest with the provided endpoint, method, body and headers.
     * @param endpoint The callout endpoint.
     * @param method The HTTP method (GET, POST, PUT, PATCH, DELETE).
     * @param body The request body. Can be null.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds.
     * @return A configured HttpRequest instance.
     */
    private static HttpRequest buildRequest(
        String endpoint, 
        String method, 
        String body, 
        Map<String, String> headers, 
        Integer timeoutMs
    ) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod(method);
        Integer timeout = (timeoutMs != null) ? timeoutMs : DEFAULT_TIMEOUT_MS;
        request.setTimeout(timeout);
        if (body != null) { request.setBody(body); }
        if (headers != null) {
            for (String key : headers.keySet()) {
                request.setHeader(key, headers.get(key));
            }
        }
        return request;
    }

    /**
     * Builds an HttpRequest whose body is bodyObject serialized as JSON, with Content-Type set automatically.
     * @param endpoint The callout endpoint.
     * @param method The HTTP method (GET, POST, PUT, PATCH, DELETE).
     * @param bodyObject Any object to serialize as JSON. Can be null.
     * @param headers The request headers. Can be null.
     * @param timeoutMs The request timeout in milliseconds. Pass null to use DEFAULT_TIMEOUT_MS.
     * @return A configured HttpRequest instance.
     */
    private static HttpRequest buildJsonRequest(
        String endpoint,
        String method,
        Object bodyObject,
        Map<String, String> headers,
        Integer timeoutMs
    ) {
        Map<String, String> allHeaders = new Map<String, String>{ 'Content-Type' => 'application/json' };
        if (headers != null) { allHeaders.putAll(headers); }
        String body = bodyObject != null ? JSON.serialize(bodyObject) : null;
        return buildRequest(endpoint, method, body, allHeaders, timeoutMs);
    }

    /**
     * Sends the provided HttpRequest and returns the response.
     * @param request The HttpRequest to send.
     * @return The HttpResponse returned by the endpoint.
     */
    private static HttpResponse send(HttpRequest request) {
        try {
            Http http = new Http();
            return http.send(request);
        } catch (System.CalloutException ex) {
            HttpCalloutException wrapped = new HttpCalloutException('Callout to ' + request.getEndpoint() + ' failed: ' + ex.getMessage());
            wrapped.initCause(ex);
            throw wrapped;
        }
    }
    
    /**
     * Validates the HTTP response status code, throwing HttpCalloutException if it isn't 2xx.
     * @param response The HTTP response to validate.
     * @param errorMessage The error message to include if the validation fails.
     */
    public static void validateResponse(HttpResponse response, String errorMessage) {
        if (!isResponseSuccessful(response)) {
            throw new HttpCalloutException(errorMessage + '\nStatus: ' + response.getStatusCode() + ', Body: ' + response.getBody());
        }
    }

    /**
     * Checks whether the HTTP response status code is in the 2xx range.
     * @param response The HTTP response to check.
     * @return true if the status code is between 200 and 299, false otherwise.
     */
    public static Boolean isResponseSuccessful(HttpResponse response) {
        Integer statusCode = response.getStatusCode();
        return statusCode >= 200 && statusCode < 300;
    }

    /**
     * Deserializes a response body into the given Apex type. Call this after checking
     * isResponseSuccessful/validateResponse, since a non-2xx body may not match apexType's shape.
     * @param response The HTTP response whose body will be deserialized.
     * @param apexType The Apex class to deserialize into (e.g. MyWrapper.class).
     * @return The deserialized object, cast to apexType.
     */
    public static Object parseResponse(HttpResponse response, Type apexType) {
        return JSON.deserialize(response.getBody(), apexType);
    }

    /**
     * Checks how many callouts are still available in the current transaction.
     * @return the number of callouts still available (org limit is 100 per transaction).
     */
    public static Integer remainingCallouts() {
        return Limits.getLimitCallouts() - Limits.getCallouts();
    }

    /**
     * Exception thrown when an HTTP callout fails.
     */
    public class HttpCalloutException extends Exception {}
}