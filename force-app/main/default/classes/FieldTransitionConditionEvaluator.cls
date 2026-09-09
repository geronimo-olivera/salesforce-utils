/**
 * File Name   :	FieldTransitionConditionEvaluator.cls
 * Description :	Evaluates Transition_Condition__mdt records against a record's in-memory state.
 *                  Shared by FieldTransitionValidator (blocks a save) and FieldTransitionRequirementService
 *                  (reports pending requirements without blocking anything). Child-object lookups
 *                  (Child Record Exists, All Matching Children Satisfy) are bulkified through BulkContext
 *                  so a batch of many records costs one query per distinct condition, not one per record.
 **/
public inherited sharing class FieldTransitionConditionEvaluator {

    public static final String CONDITION_TYPE_CHILD_RECORD_EXISTS = 'Child Record Exists';
    public static final String CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY = 'All Matching Children Satisfy';
    public static final String CONDITION_TYPE_PARENT_FIELD_CRITERIA = 'Parent Field Criteria';
    public static final String CONDITION_TYPE_PARENT_CRITERIA_IF_CHILD_EXISTS = 'Parent Criteria If Child Exists';

    private static final String OPERATOR_IN = 'IN';
    private static final String OPERATOR_NOT_IN = 'NOT IN';
    private static final String OPERATOR_LIKE = 'LIKE';
    private static final String OPERATOR_INCLUDES = 'INCLUDES';
    private static final String OPERATOR_EXCLUDES = 'EXCLUDES';

    private static final Pattern PARENT_CRITERIA_PATTERN = Pattern.compile('(?i)^\\s*(\\S+)\\s*(NOT\\s+IN|INCLUDES|EXCLUDES|IN|LIKE|!=|>=|<=|=|>|<)\\s*(.+?)\\s*$');
    private static final Pattern DATE_LITERAL_N_PATTERN = Pattern.compile('^(LAST_N_DAYS|NEXT_N_DAYS|N_DAYS_AGO|LAST_N_WEEKS|NEXT_N_WEEKS|N_WEEKS_AGO|LAST_N_MONTHS|NEXT_N_MONTHS|N_MONTHS_AGO|LAST_N_QUARTERS|NEXT_N_QUARTERS|N_QUARTERS_AGO|LAST_N_YEARS|NEXT_N_YEARS|N_YEARS_AGO):(\\d+)$');

    /**
     * Runs every child-object query a batch of conditions will need, once per condition instead of once
     * per (condition, record) pair. Call this before evaluating any condition in CONDITION_TYPE_CHILD_RECORD_EXISTS,
     * CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY, or CONDITION_TYPE_PARENT_CRITERIA_IF_CHILD_EXISTS for more
     * than one record. A condition whose query fails (e.g. a stale Child_Object_API_Name__c) is recorded as
     * failed rather than thrown, so one bad condition can't block every record in the batch.
     * @param conditions The conditions to prefetch child data for.
     * @param parentIdsByConditionId For each condition's Id, the parent record Ids that need it evaluated.
     * @return a BulkContext ready to pass into evaluate.
     */
    public static BulkContext prefetch(List<Transition_Condition__mdt> conditions, Map<Id, Set<Id>> parentIdsByConditionId) {
        BulkContext context = new BulkContext();
        for (Transition_Condition__mdt condition : conditions) {
            Set<Id> parentIds = parentIdsByConditionId.get(condition.Id);
            if (parentIds == null || parentIds.isEmpty()) { continue; }
            try {
                if (condition.Condition_Type__c == CONDITION_TYPE_CHILD_RECORD_EXISTS || condition.Condition_Type__c == CONDITION_TYPE_PARENT_CRITERIA_IF_CHILD_EXISTS) {
                    context.childMatchesByConditionId.put(condition.Id, queryChildMatches(condition, parentIds));
                }
                if (condition.Condition_Type__c == CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY) {
                    context.violatingParentsByConditionId.put(condition.Id, queryViolatingParents(condition, parentIds));
                }
            } catch (Exception ex) {
                context.failedConditionIds.add(condition.Id);
                System.debug(LoggingLevel.ERROR, 'Transition_Condition__mdt "' + condition.DeveloperName + '" could not be evaluated and is being treated as not satisfied: ' + ex.getMessage());
            }
        }
        return context;
    }

    /**
     * Dispatches to the right evaluation for condition.Condition_Type__c, using data already fetched
     * into context by prefetch. Uses if/else rather than a switch because Apex switch "when" clauses
     * only accept literals, not the constants defined above.
     * @param condition The condition to evaluate.
     * @param record The record's current (possibly in-memory, not-yet-saved) state.
     * @param context Child-object data prefetched by prefetch. A condition missing from it is treated as not satisfied.
     * @return true if the condition is satisfied.
     */
    public static Boolean evaluate(Transition_Condition__mdt condition, SObject record, BulkContext context) {
        if (context.failedConditionIds.contains(condition.Id)) { return false; }
        if (condition.Condition_Type__c == CONDITION_TYPE_CHILD_RECORD_EXISTS) {
            return childMatches(context, condition, record.Id);
        }
        if (condition.Condition_Type__c == CONDITION_TYPE_ALL_MATCHING_CHILDREN_SATISFY) {
            return !violatingParents(context, condition, record.Id);
        }
        if (condition.Condition_Type__c == CONDITION_TYPE_PARENT_FIELD_CRITERIA) {
            return parentMatchesCriteria(record, condition.Parent_Filter_Criteria__c);
        }
        if (condition.Condition_Type__c == CONDITION_TYPE_PARENT_CRITERIA_IF_CHILD_EXISTS) {
            return !childMatches(context, condition, record.Id) || parentMatchesCriteria(record, condition.Parent_Filter_Criteria__c);
        }
        System.debug(LoggingLevel.WARN, 'Unknown Condition_Type__c: ' + condition.Condition_Type__c + ' — condition ignored.');
        return true;
    }

    /**
     * Single-record convenience overload. Prefetches just for this one record, so callers evaluating one
     * record at a time (e.g. the requirement checklist) don't need to build a BulkContext themselves.
     * Callers evaluating many records should build one BulkContext with prefetch and reuse it instead.
     * @param condition The condition to evaluate.
     * @param record The record's current state.
     * @return true if the condition is satisfied.
     */
    public static Boolean evaluate(Transition_Condition__mdt condition, SObject record) {
        BulkContext context = prefetch(new List<Transition_Condition__mdt>{ condition }, new Map<Id, Set<Id>>{ condition.Id => new Set<Id>{ record.Id } });
        return evaluate(condition, record, context);
    }

    /**
     * Extracts the parent field API name referenced by a Parent_Filter_Criteria__c string, so callers
     * that need to query the parent record (rather than read it from trigger context) know which field
     * to include in their SELECT.
     * @param criteria A Parent_Filter_Criteria__c value. Blank returns null.
     * @return the field API name, or null if criteria is blank or doesn't match the expected format.
     */
    public static String extractParentCriteriaFieldName(String criteria) {
        if (String.isBlank(criteria)) { return null; }
        Matcher matcher = PARENT_CRITERIA_PATTERN.matcher(criteria);
        return matcher.matches() ? matcher.group(1) : null;
    }

    /**
     * @param context The prefetched child data.
     * @param condition The condition being evaluated.
     * @param parentId The parent record's Id.
     * @return true if a matching child record exists for parentId.
     */
    private static Boolean childMatches(BulkContext context, Transition_Condition__mdt condition, Id parentId) {
        Set<Id> matches = context.childMatchesByConditionId.get(condition.Id);
        return matches != null && matches.contains(parentId);
    }

    /**
     * @param context The prefetched child data.
     * @param condition The condition being evaluated.
     * @param parentId The parent record's Id.
     * @return true if parentId has at least one selected child that fails Child_Required_Criteria__c.
     */
    private static Boolean violatingParents(BulkContext context, Transition_Condition__mdt condition, Id parentId) {
        Set<Id> violating = context.violatingParentsByConditionId.get(condition.Id);
        return violating != null && violating.contains(parentId);
    }

    /**
     * Bulk query backing "Child Record Exists" and "Parent Criteria If Child Exists": which of parentIds
     * have at least one child matching Child_Filter_Criteria__c.
     * @param condition Supplies Child_Object_API_Name__c, Child_Relationship_Field__c, Child_Filter_Criteria__c.
     * @param parentIds The parent record Ids to check.
     * @return the subset of parentIds with a matching child.
     */
    private static Set<Id> queryChildMatches(Transition_Condition__mdt condition, Set<Id> parentIds) {
        String query = 'SELECT ' + condition.Child_Relationship_Field__c + ' FROM ' + condition.Child_Object_API_Name__c +
            ' WHERE ' + condition.Child_Relationship_Field__c + ' IN :parentIds';
        if (String.isNotBlank(condition.Child_Filter_Criteria__c)) {
            query += ' AND (' + condition.Child_Filter_Criteria__c + ')';
        }
        Set<Id> matches = new Set<Id>();
        for (SObject child : Database.query(query)) {
            matches.add((Id) child.get(condition.Child_Relationship_Field__c));
        }
        return matches;
    }

    /**
     * Bulk query backing "All Matching Children Satisfy": which of parentIds have at least one child,
     * among those selected by Child_Filter_Criteria__c, that fails Child_Required_Criteria__c.
     * @param condition Supplies Child_Object_API_Name__c, Child_Relationship_Field__c,
     * Child_Filter_Criteria__c, Child_Required_Criteria__c.
     * @param parentIds The parent record Ids to check.
     * @return the subset of parentIds with at least one violating child.
     */
    private static Set<Id> queryViolatingParents(Transition_Condition__mdt condition, Set<Id> parentIds) {
        String query = 'SELECT ' + condition.Child_Relationship_Field__c + ' FROM ' + condition.Child_Object_API_Name__c +
            ' WHERE ' + condition.Child_Relationship_Field__c + ' IN :parentIds';
        if (String.isNotBlank(condition.Child_Filter_Criteria__c)) {
            query += ' AND (' + condition.Child_Filter_Criteria__c + ')';
        }
        if (String.isNotBlank(condition.Child_Required_Criteria__c)) {
            query += ' AND (NOT (' + condition.Child_Required_Criteria__c + '))';
        }
        Set<Id> violating = new Set<Id>();
        for (SObject child : Database.query(query)) {
            violating.add((Id) child.get(condition.Child_Relationship_Field__c));
        }
        return violating;
    }

    /**
     * "Parent Field Criteria" — parses and evaluates a single SOQL-style comparison (field, operator,
     * value) directly against the record's in-memory (not-yet-saved) state. A SOQL query can't be used
     * here since it would only see the last-committed values, not the ones being saved now. Every
     * operator except "= null"/"!= null" treats a null field as not satisfying the comparison — the
     * same convention IN/NOT IN and INCLUDES/EXCLUDES fall back to for a non-multi-select field.
     * @param record The record's current state.
     * @param criteria A single comparison, e.g. Amount = null, CloseDate > 2026-01-01, Status__c IN
     * ('A', 'B'), or Name LIKE 'Acme%'. Blank always passes.
     * @return true if the record matches criteria, or criteria is blank.
     */
    private static Boolean parentMatchesCriteria(SObject record, String criteria) {
        if (String.isBlank(criteria)) { return true; }
        try {
            Matcher matcher = PARENT_CRITERIA_PATTERN.matcher(criteria);
            if (!matcher.matches()) {
                throw new FieldTransitionValidatorException('Invalid Parent_Filter_Criteria__c "' + criteria + '". Expected format: FieldApiName OPERATOR Value.');
            }
            String fieldName = matcher.group(1);
            String operatorToken = matcher.group(2).trim().toUpperCase().replaceAll('\\s+', ' ');
            String valueToken = matcher.group(3);
            Object fieldValue = record.get(fieldName);
            Schema.DisplayType fieldType = getFieldDisplayType(record, fieldName);

            if (valueToken.equalsIgnoreCase('null')) {
                if (operatorToken == '=') { return fieldValue == null; }
                if (operatorToken == '!=') { return fieldValue != null; }
                throw new FieldTransitionValidatorException('Operator "' + operatorToken + '" cannot be used with null in "' + criteria + '".');
            }

            if (operatorToken == OPERATOR_IN || operatorToken == OPERATOR_NOT_IN) {
                if (fieldType != Schema.DisplayType.MULTIPICKLIST && fieldValue == null) { return false; }
                Boolean isMatch = evaluateInClause(fieldValue, fieldType, valueToken, criteria);
                return operatorToken == OPERATOR_IN ? isMatch : !isMatch;
            }
            if (operatorToken == OPERATOR_LIKE) {
                return evaluateLike(fieldValue, valueToken, criteria);
            }
            if (operatorToken == OPERATOR_INCLUDES || operatorToken == OPERATOR_EXCLUDES) {
                if (fieldType != Schema.DisplayType.MULTIPICKLIST) {
                    throw new FieldTransitionValidatorException(operatorToken + ' can only be used on multi-select picklist fields, in "' + criteria + '".');
                }
                Boolean isMatch = evaluateIncludesClause((String) fieldValue, valueToken, criteria);
                return operatorToken == OPERATOR_INCLUDES ? isMatch : !isMatch;
            }
            if (fieldValue == null) { return false; }

            if (fieldType == Schema.DisplayType.DATE || fieldType == Schema.DisplayType.DATETIME) {
                return evaluateDateComparison(fieldValue, fieldType, operatorToken, valueToken, criteria);
            }

            if (fieldType == Schema.DisplayType.MULTIPICKLIST) {
                if (!isQuoted(valueToken)) {
                    throw new FieldTransitionValidatorException('Multi-select picklist values must be quoted, in "' + criteria + '".');
                }
                Boolean includesValue = multiPicklistIncludes((String) fieldValue, unquote(valueToken));
                if (operatorToken == '=') { return includesValue; }
                if (operatorToken == '!=') { return !includesValue; }
                throw new FieldTransitionValidatorException('Operator "' + operatorToken + '" is not supported for multi-select picklists in "' + criteria + '". Use =, !=, IN, NOT IN, INCLUDES, or EXCLUDES.');
            }

            if (isQuoted(valueToken)) {
                String textValue = unquote(valueToken);
                String fieldText = String.valueOf(fieldValue);
                if (operatorToken == '=') { return fieldText == textValue; }
                if (operatorToken == '!=') { return fieldText != textValue; }
                throw new FieldTransitionValidatorException('Operator "' + operatorToken + '" only supports = or != for text values, in "' + criteria + '".');
            }

            if (valueToken.equalsIgnoreCase('true') || valueToken.equalsIgnoreCase('false')) {
                Boolean boolValue = Boolean.valueOf(valueToken);
                Boolean fieldBool = (Boolean) fieldValue;
                if (operatorToken == '=') { return fieldBool == boolValue; }
                if (operatorToken == '!=') { return fieldBool != boolValue; }
                throw new FieldTransitionValidatorException('Operator "' + operatorToken + '" only supports = or != for boolean values, in "' + criteria + '".');
            }

            Decimal numericValue = Decimal.valueOf(valueToken);
            Decimal fieldNumber = (Decimal) fieldValue;
            if (operatorToken == '=') { return fieldNumber == numericValue; }
            if (operatorToken == '!=') { return fieldNumber != numericValue; }
            if (operatorToken == '>') { return fieldNumber > numericValue; }
            if (operatorToken == '>=') { return fieldNumber >= numericValue; }
            if (operatorToken == '<') { return fieldNumber < numericValue; }
            return fieldNumber <= numericValue;
        } catch (FieldTransitionValidatorException ex) {
            throw ex;
        } catch (Exception ex) {
            FieldTransitionValidatorException wrapped = new FieldTransitionValidatorException('Failed to evaluate parent criteria "' + criteria + '": ' + ex.getMessage());
            wrapped.initCause(ex);
            throw wrapped;
        }
    }

    /**
     * Looks up a field's real data type, so parentMatchesCriteria can parse its comparison value correctly.
     * @param record The record whose SObject type defines the field.
     * @param fieldName API name of the field to look up.
     * @return the field's Schema.DisplayType.
     */
    private static Schema.DisplayType getFieldDisplayType(SObject record, String fieldName) {
        Schema.SObjectField field = record.getSObjectType().getDescribe().fields.getMap().get(fieldName);
        if (field == null) {
            throw new FieldTransitionValidatorException('Field "' + fieldName + '" does not exist on ' + record.getSObjectType().getDescribe().getName() + '.');
        }
        return field.getDescribe().getType();
    }

    /**
     * Evaluates an IN-style value list against a field. For multi-select picklists, matches if the
     * field includes any listed value; otherwise matches if the field equals any listed value.
     * @param fieldValue The field's current value.
     * @param fieldType The field's data type.
     * @param valueToken The parenthesized value list, e.g. ('A', 'B').
     * @param criteria The full criteria string, for error messages.
     * @return true if fieldValue matches at least one value in the list.
     */
    private static Boolean evaluateInClause(Object fieldValue, Schema.DisplayType fieldType, String valueToken, String criteria) {
        if (!valueToken.startsWith('(') || !valueToken.endsWith(')')) {
            throw new FieldTransitionValidatorException('IN/NOT IN requires a parenthesized list, e.g. (\'A\', \'B\'), in "' + criteria + '".');
        }
        List<String> rawValues = splitList(valueToken.substring(1, valueToken.length() - 1));

        if (fieldType == Schema.DisplayType.MULTIPICKLIST) {
            String fieldText = fieldValue == null ? '' : (String) fieldValue;
            for (String rawValue : rawValues) {
                if (multiPicklistIncludes(fieldText, unquote(rawValue.trim()))) { return true; }
            }
            return false;
        }

        for (String rawValue : rawValues) {
            String trimmed = rawValue.trim();
            if (isQuoted(trimmed)) {
                if (String.valueOf(fieldValue) == unquote(trimmed)) { return true; }
            } else {
                if (((Decimal) fieldValue) == Decimal.valueOf(trimmed)) { return true; }
            }
        }
        return false;
    }

    /**
     * Evaluates an INCLUDES-style value list against a multi-select picklist. A semicolon inside one
     * quoted group means the field must include every value in that group (AND); separate comma-
     * delimited groups mean the field must satisfy at least one of them (OR) — matching SOQL's
     * INCLUDES('A;B', 'C') semantics.
     * @param fieldValue The multi-select picklist's raw stored value.
     * @param valueToken The parenthesized value list, e.g. ('A;B', 'C').
     * @param criteria The full criteria string, for error messages.
     * @return true if fieldValue satisfies at least one group.
     */
    private static Boolean evaluateIncludesClause(String fieldValue, String valueToken, String criteria) {
        if (!valueToken.startsWith('(') || !valueToken.endsWith(')')) {
            throw new FieldTransitionValidatorException('INCLUDES/EXCLUDES requires a parenthesized list, e.g. (\'A;B\', \'C\'), in "' + criteria + '".');
        }
        String fieldText = fieldValue == null ? '' : fieldValue;
        for (String rawGroup : splitList(valueToken.substring(1, valueToken.length() - 1))) {
            String trimmedGroup = rawGroup.trim();
            if (!isQuoted(trimmedGroup)) {
                throw new FieldTransitionValidatorException('INCLUDES/EXCLUDES values must be quoted, in "' + criteria + '".');
            }
            Boolean groupSatisfied = true;
            for (String requiredValue : unquote(trimmedGroup).split(';')) {
                if (!multiPicklistIncludes(fieldText, requiredValue.trim())) {
                    groupSatisfied = false;
                    break;
                }
            }
            if (groupSatisfied) { return true; }
        }
        return false;
    }

    /**
     * Evaluates a SOQL-style LIKE pattern (% for any sequence, _ for any single character) against a field.
     * @param fieldValue The field's current value.
     * @param valueToken The quoted LIKE pattern, e.g. 'Acme%'.
     * @param criteria The full criteria string, for error messages.
     * @return true if fieldValue's text matches the pattern, case-insensitively.
     */
    private static Boolean evaluateLike(Object fieldValue, String valueToken, String criteria) {
        if (!isQuoted(valueToken)) {
            throw new FieldTransitionValidatorException('LIKE requires a quoted pattern, e.g. Name LIKE \'Acme%\', in "' + criteria + '".');
        }
        if (fieldValue == null) { return false; }
        String regex = '(?i)^' + likePatternToRegexBody(unquote(valueToken)) + '$';
        return Pattern.matches(regex, String.valueOf(fieldValue));
    }

    /**
     * Converts a SOQL LIKE pattern into the body of a regular expression, escaping literal characters
     * and translating % to .* and _ to . .
     * @param likePattern The LIKE pattern to convert.
     * @return the equivalent regex body (not yet anchored).
     */
    private static String likePatternToRegexBody(String likePattern) {
        String specialChars = '\\.^$|?*+()[]{}';
        String result = '';
        for (Integer i = 0; i < likePattern.length(); i++) {
            String ch = likePattern.substring(i, i + 1);
            if (ch == '%') {
                result += '.*';
            } else if (ch == '_') {
                result += '.';
            } else if (specialChars.contains(ch)) {
                result += '\\' + ch;
            } else {
                result += ch;
            }
        }
        return result;
    }

    /**
     * Evaluates a Date/Datetime comparison. The value token can be a literal date/datetime (parsed so
     * ordering operators work correctly, unlike a plain string comparison), or a SOQL date literal
     * (TODAY, THIS_WEEK, LAST_N_DAYS:30, etc — see resolveDateLiteral for the supported set). A literal
     * datetime with a trailing Z (e.g. 2026-01-01T09:00:00Z) is parsed as an explicit UTC instant;
     * without it, the value is interpreted in the timezone of whoever is saving the record, same as
     * Datetime.valueOf — two users in different timezones can get different results from the same
     * criteria string, so a trailing Z is the only way to pin an exact moment.
     * @param fieldValue The field's current value (a Date or Datetime).
     * @param fieldType Whether the field is DATE or DATETIME.
     * @param operatorToken The comparison operator.
     * @param valueToken The date/datetime value or SOQL date literal, quoted or not, e.g. 2026-01-01 or TODAY.
     * @param criteria The full criteria string, for error messages.
     * @return true if fieldValue satisfies the comparison.
     */
    private static Boolean evaluateDateComparison(Object fieldValue, Schema.DisplayType fieldType, String operatorToken, String valueToken, String criteria) {
        String rawValue = isQuoted(valueToken) ? unquote(valueToken) : valueToken;
        DateLiteralRange literalRange = resolveDateLiteral(rawValue.toUpperCase());
        if (literalRange != null) {
            return evaluateDateLiteralRange(fieldValue, fieldType, operatorToken, literalRange, criteria);
        }

        if (fieldType == Schema.DisplayType.DATE) {
            Date fieldDate = (Date) fieldValue;
            Date compareDate = Date.valueOf(rawValue);
            if (operatorToken == '=') { return fieldDate == compareDate; }
            if (operatorToken == '!=') { return fieldDate != compareDate; }
            if (operatorToken == '>') { return fieldDate > compareDate; }
            if (operatorToken == '>=') { return fieldDate >= compareDate; }
            if (operatorToken == '<') { return fieldDate < compareDate; }
            if (operatorToken == '<=') { return fieldDate <= compareDate; }
            throw new FieldTransitionValidatorException('Unsupported operator "' + operatorToken + '" in "' + criteria + '".');
        }
        Datetime compareDatetime = parseDatetimeLiteral(rawValue);
        Datetime fieldDatetime = (Datetime) fieldValue;
        if (operatorToken == '=') { return fieldDatetime == compareDatetime; }
        if (operatorToken == '!=') { return fieldDatetime != compareDatetime; }
        if (operatorToken == '>') { return fieldDatetime > compareDatetime; }
        if (operatorToken == '>=') { return fieldDatetime >= compareDatetime; }
        if (operatorToken == '<') { return fieldDatetime < compareDatetime; }
        if (operatorToken == '<=') { return fieldDatetime <= compareDatetime; }
        throw new FieldTransitionValidatorException('Unsupported operator "' + operatorToken + '" in "' + criteria + '".');
    }

    /**
     * Parses a literal datetime value into an exact instant. A trailing Z is treated as explicit UTC
     * (via Datetime.newInstanceGmt); otherwise the value is handed to Datetime.valueOf, which Apex
     * interprets in the timezone of whoever is running this code.
     * @param rawValue The datetime literal, unquoted, e.g. 2026-01-01T09:00:00Z or 2026-01-01 09:00:00.
     * @return the resolved Datetime instant.
     */
    private static Datetime parseDatetimeLiteral(String rawValue) {
        String normalized = rawValue.replace('T', ' ');
        Boolean isUtc = normalized.endsWithIgnoreCase('z');
        if (isUtc) { normalized = normalized.substring(0, normalized.length() - 1).trim(); }
        if (!normalized.contains(':')) {
            Date d = Date.valueOf(normalized);
            return isUtc ? Datetime.newInstanceGmt(d, Time.newInstance(0, 0, 0, 0)) : Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        }
        if (!isUtc) { return Datetime.valueOf(normalized); }
        List<String> dateAndTime = normalized.split(' ');
        List<String> dateParts = dateAndTime[0].split('-');
        List<String> timeParts = dateAndTime[1].split(':');
        return Datetime.newInstanceGmt(
            Integer.valueOf(dateParts[0]), Integer.valueOf(dateParts[1]), Integer.valueOf(dateParts[2]),
            Integer.valueOf(timeParts[0]), Integer.valueOf(timeParts[1]), Integer.valueOf(timeParts[2])
        );
    }

    /**
     * Compares a Date/Datetime field against a resolved SOQL date literal range. Single-day literals
     * (TODAY, N_DAYS_AGO:n) support all six operators; multi-day range literals (THIS_WEEK, LAST_MONTH)
     * only support = (falls within the range) and != (falls outside it).
     * @param fieldValue The field's current value (a Date or Datetime).
     * @param fieldType Whether the field is DATE or DATETIME.
     * @param operatorToken The comparison operator.
     * @param literalRange The resolved date literal range.
     * @param criteria The full criteria string, for error messages.
     * @return true if fieldValue satisfies the comparison.
     */
    private static Boolean evaluateDateLiteralRange(Object fieldValue, Schema.DisplayType fieldType, String operatorToken, DateLiteralRange literalRange, String criteria) {
        Date fieldDate = fieldType == Schema.DisplayType.DATE ? (Date) fieldValue : ((Datetime) fieldValue).date();
        if (literalRange.startDate == literalRange.endDate) {
            if (operatorToken == '=') { return fieldDate == literalRange.startDate; }
            if (operatorToken == '!=') { return fieldDate != literalRange.startDate; }
            if (operatorToken == '>') { return fieldDate > literalRange.startDate; }
            if (operatorToken == '>=') { return fieldDate >= literalRange.startDate; }
            if (operatorToken == '<') { return fieldDate < literalRange.startDate; }
            if (operatorToken == '<=') { return fieldDate <= literalRange.startDate; }
            throw new FieldTransitionValidatorException('Unsupported operator "' + operatorToken + '" in "' + criteria + '".');
        }
        Boolean withinRange = fieldDate >= literalRange.startDate && fieldDate <= literalRange.endDate;
        if (operatorToken == '=') { return withinRange; }
        if (operatorToken == '!=') { return !withinRange; }
        throw new FieldTransitionValidatorException('Operator "' + operatorToken + '" only supports = or != with range-based date literals like THIS_WEEK, in "' + criteria + '".');
    }

    /**
     * Resolves a SOQL date literal (TODAY, THIS_WEEK, LAST_N_DAYS:30, etc) into a concrete date range.
     * Weeks are treated as starting on Sunday. Quarters are calendar quarters. Fiscal-year literals
     * (THIS_FISCAL_YEAR and similar) aren't supported, since they depend on org fiscal year settings.
     * @param upperToken The literal, already uppercased.
     * @return the resolved range, or null if upperToken isn't a recognized date literal.
     */
    private static DateLiteralRange resolveDateLiteral(String upperToken) {
        Date today = Date.today();
        if (upperToken == 'TODAY') { return singleDay(today); }
        if (upperToken == 'YESTERDAY') { return singleDay(today.addDays(-1)); }
        if (upperToken == 'TOMORROW') { return singleDay(today.addDays(1)); }
        if (upperToken == 'THIS_WEEK') { return weekRange(today, 0); }
        if (upperToken == 'LAST_WEEK') { return weekRange(today, -1); }
        if (upperToken == 'NEXT_WEEK') { return weekRange(today, 1); }
        if (upperToken == 'THIS_MONTH') { return monthRange(today.year(), today.month()); }
        if (upperToken == 'LAST_MONTH') { Date d = today.addMonths(-1); return monthRange(d.year(), d.month()); }
        if (upperToken == 'NEXT_MONTH') { Date d = today.addMonths(1); return monthRange(d.year(), d.month()); }
        if (upperToken == 'THIS_QUARTER') { return quarterRange(today, 0); }
        if (upperToken == 'LAST_QUARTER') { return quarterRange(today, -1); }
        if (upperToken == 'NEXT_QUARTER') { return quarterRange(today, 1); }
        if (upperToken == 'THIS_YEAR') { return yearRange(today.year()); }
        if (upperToken == 'LAST_YEAR') { return yearRange(today.year() - 1); }
        if (upperToken == 'NEXT_YEAR') { return yearRange(today.year() + 1); }

        Matcher nMatcher = DATE_LITERAL_N_PATTERN.matcher(upperToken);
        if (!nMatcher.matches()) { return null; }
        String prefix = nMatcher.group(1);
        Integer n = Integer.valueOf(nMatcher.group(2));
        if (prefix == 'LAST_N_DAYS') { return new DateLiteralRange(today.addDays(-n), today); }
        if (prefix == 'NEXT_N_DAYS') { return new DateLiteralRange(today, today.addDays(n)); }
        if (prefix == 'N_DAYS_AGO') { return singleDay(today.addDays(-n)); }
        if (prefix == 'LAST_N_WEEKS') { return new DateLiteralRange(today.addDays(-7 * n), today); }
        if (prefix == 'NEXT_N_WEEKS') { return new DateLiteralRange(today, today.addDays(7 * n)); }
        if (prefix == 'N_WEEKS_AGO') { return weekRange(today.addDays(-7 * n), 0); }
        if (prefix == 'LAST_N_MONTHS') { return new DateLiteralRange(today.addMonths(-n), today); }
        if (prefix == 'NEXT_N_MONTHS') { return new DateLiteralRange(today, today.addMonths(n)); }
        if (prefix == 'N_MONTHS_AGO') { Date d = today.addMonths(-n); return monthRange(d.year(), d.month()); }
        if (prefix == 'LAST_N_QUARTERS') { return new DateLiteralRange(today.addMonths(-3 * n), today); }
        if (prefix == 'NEXT_N_QUARTERS') { return new DateLiteralRange(today, today.addMonths(3 * n)); }
        if (prefix == 'N_QUARTERS_AGO') { return quarterRange(today.addMonths(-3 * n), 0); }
        if (prefix == 'LAST_N_YEARS') { return new DateLiteralRange(today.addYears(-n), today); }
        if (prefix == 'NEXT_N_YEARS') { return new DateLiteralRange(today, today.addYears(n)); }
        if (prefix == 'N_YEARS_AGO') { return yearRange(today.year() - n); }
        return null;
    }

    /**
     * @param d The single day to represent.
     * @return a range whose start and end are both d.
     */
    private static DateLiteralRange singleDay(Date d) {
        return new DateLiteralRange(d, d);
    }

    /**
     * @param anchor Any date within the reference week.
     * @param weekOffset 0 for anchor's own week, -1 for the previous week, 1 for the next week.
     * @return the Sunday-to-Saturday range for that week.
     */
    private static DateLiteralRange weekRange(Date anchor, Integer weekOffset) {
        Datetime anchorDatetime = Datetime.newInstance(anchor, Time.newInstance(0, 0, 0, 0));
        Integer isoDayOfWeek = Integer.valueOf(anchorDatetime.format('u'));
        Integer daysSinceSunday = Math.mod(isoDayOfWeek, 7);
        Date sunday = anchor.addDays(-daysSinceSunday).addDays(7 * weekOffset);
        return new DateLiteralRange(sunday, sunday.addDays(6));
    }

    /**
     * @param year The calendar year of the month.
     * @param month The calendar month, 1-12.
     * @return the first-to-last day range for that month.
     */
    private static DateLiteralRange monthRange(Integer year, Integer month) {
        Date startDate = Date.newInstance(year, month, 1);
        return new DateLiteralRange(startDate, startDate.addMonths(1).addDays(-1));
    }

    /**
     * @param anchor Any date within the reference quarter.
     * @param quarterOffset 0 for anchor's own quarter, -1 for the previous quarter, 1 for the next.
     * @return the first-to-last day range for that calendar quarter.
     */
    private static DateLiteralRange quarterRange(Date anchor, Integer quarterOffset) {
        Integer quarterIndex = (anchor.month() - 1) / 3;
        Integer totalQuarters = anchor.year() * 4 + quarterIndex + quarterOffset;
        Integer targetYear = totalQuarters / 4;
        Integer targetQuarterIndex = Math.mod(totalQuarters, 4);
        Date startDate = Date.newInstance(targetYear, targetQuarterIndex * 3 + 1, 1);
        return new DateLiteralRange(startDate, startDate.addMonths(3).addDays(-1));
    }

    /**
     * @param year The calendar year.
     * @return the January 1 to December 31 range for that year.
     */
    private static DateLiteralRange yearRange(Integer year) {
        return new DateLiteralRange(Date.newInstance(year, 1, 1), Date.newInstance(year, 12, 31));
    }

    /**
     * Checks whether a multi-select picklist's semicolon-separated value includes a given option.
     * @param fieldValue The multi-select picklist's raw stored value, e.g. "A;B".
     * @param targetValue The option to look for.
     * @return true if targetValue is one of the selected options.
     */
    private static Boolean multiPicklistIncludes(String fieldValue, String targetValue) {
        if (String.isBlank(fieldValue)) { return false; }
        for (String selected : fieldValue.split(';')) {
            if (selected == targetValue) { return true; }
        }
        return false;
    }

    /**
     * Splits a comma-separated value list, ignoring commas inside quoted strings.
     * @param content The list content, without its surrounding parentheses.
     * @return the individual, untrimmed value tokens.
     */
    private static List<String> splitList(String content) {
        List<String> parts = new List<String>();
        Boolean inQuotes = false;
        String current = '';
        for (Integer i = 0; i < content.length(); i++) {
            String ch = content.substring(i, i + 1);
            if (ch == '\'' || ch == '"') { inQuotes = !inQuotes; }
            if (ch == ',' && !inQuotes) {
                parts.add(current);
                current = '';
            } else {
                current += ch;
            }
        }
        if (String.isNotBlank(current)) { parts.add(current); }
        return parts;
    }

    /**
     * @param token The token to check.
     * @return true if token is wrapped in matching single or double quotes.
     */
    private static Boolean isQuoted(String token) {
        return (token.startsWith('\'') && token.endsWith('\'')) || (token.startsWith('"') && token.endsWith('"'));
    }

    /**
     * @param token A quoted token, as confirmed by isQuoted.
     * @return the token with its surrounding quotes removed.
     */
    private static String unquote(String token) {
        return token.substring(1, token.length() - 1);
    }

    /**
     * Child-object data prefetched by prefetch, keyed by condition Id, plus the set of conditions whose
     * query failed (e.g. a stale Child_Object_API_Name__c) and are therefore treated as not satisfied.
     */
    public class BulkContext {
        private Map<Id, Set<Id>> childMatchesByConditionId = new Map<Id, Set<Id>>();
        private Map<Id, Set<Id>> violatingParentsByConditionId = new Map<Id, Set<Id>>();
        private Set<Id> failedConditionIds = new Set<Id>();
    }

    /**
     * A resolved SOQL date literal's date range. startDate equals endDate for single-day literals.
     */
    private class DateLiteralRange {
        Date startDate;
        Date endDate;

        DateLiteralRange(Date startDate, Date endDate) {
            this.startDate = startDate;
            this.endDate = endDate;
        }
    }

    /**
     * Exception thrown when a condition's criteria can't be evaluated (e.g. invalid syntax, unknown field).
     */
    public class FieldTransitionValidatorException extends Exception {}
}
