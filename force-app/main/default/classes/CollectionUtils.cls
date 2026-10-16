public inherited sharing class CollectionUtils {

    /**
     * Returns the Ids of the given records.
     * @param records The records. Can be null.
     * @return The records' Ids. Records without an Id yet (before insert) are skipped.
     */
    public static Set<Id> getIds(List<SObject> records) {
        Set<Id> ids = new Set<Id>();
        if (records == null) { return ids; }
        for (SObject record : records) {
            if (record != null && record.Id != null) { ids.add(record.Id); }
        }
        return ids;
    }

    /**
     * Returns the distinct Id values of a lookup (or any Id-valued) field, e.g. every AccountId on a list of Opportunities.
     * The field must have been queried, or Salesforce throws an SObjectException.
     * @param records The records. Can be null.
     * @param field The field to read, e.g. Opportunity.AccountId.
     * @return The distinct non-blank values. Records where the field is empty are skipped.
     * @throws StringException if the field holds text that isn't a valid Id.
     */
    public static Set<Id> getIds(List<SObject> records, SObjectField field) {
        Set<Id> ids = new Set<Id>();
        if (records == null) { return ids; }
        for (SObject record : records) {
            Id value = toId(read(record, field));
            if (value != null) { ids.add(value); }
        }
        return ids;
    }

    /**
     * Returns the distinct values of a field as Strings, e.g. every Industry on a list of Accounts. Non-text values
     * (numbers, picklists, dates) are converted with String.valueOf.
     * @param records The records. Can be null.
     * @param field The field to read.
     * @return The distinct non-blank values.
     */
    public static Set<String> getStrings(List<SObject> records, SObjectField field) {
        Set<String> values = new Set<String>();
        if (records == null) { return values; }
        for (SObject record : records) {
            Object value = read(record, field);
            if (!isBlank(value)) { values.add(String.valueOf(value)); }
        }
        return values;
    }

    /**
     * Returns the distinct values of a numeric field (Number, Currency, Percent), e.g. every Amount on a list of Opportunities.
     * @param records The records. Can be null.
     * @param field The numeric field to read.
     * @return The distinct non-null values.
     * @throws TypeException if the field isn't numeric.
     */
    public static Set<Decimal> getDecimals(List<SObject> records, SObjectField field) {
        Set<Decimal> values = new Set<Decimal>();
        if (records == null) { return values; }
        for (SObject record : records) {
            Object value = read(record, field);
            if (value != null) { values.add(toDecimal(value)); }
        }
        return values;
    }

    /**
     * Returns the distinct dates of a Date or Date/Time field, e.g. every CloseDate on a list of Opportunities. A
     * Date/Time value is reduced to its date, in the running user's time zone.
     * @param records The records. Can be null.
     * @param field The Date or Date/Time field to read.
     * @return The distinct non-null dates.
     * @throws TypeException if the field is neither a Date nor a Date/Time.
     */
    public static Set<Date> getDates(List<SObject> records, SObjectField field) {
        Set<Date> dates = new Set<Date>();
        if (records == null) { return dates; }
        for (SObject record : records) {
            Object value = read(record, field);
            if (value == null) { continue; }
            dates.add(value instanceof Datetime ? ((Datetime) value).date() : (Date) value);
        }
        return dates;
    }

    /**
     * Groups records by an Id-valued field, e.g. Opportunities by AccountId. Each list keeps the original order.
     * Cast a group back to its concrete type where you use it: (List<Opportunity>) grouped.get(accountId).
     * @param records The records. Can be null.
     * @param field The Id-valued field to group by.
     * @return A map from each distinct field value to its records. Records where the field is empty are left out.
     * @throws StringException if the field holds text that isn't a valid Id.
     */
    public static Map<Id, List<SObject>> groupById(List<SObject> records, SObjectField field) {
        Map<Id, List<SObject>> grouped = new Map<Id, List<SObject>>();
        if (records == null) { return grouped; }
        for (SObject record : records) {
            Id key = toId(read(record, field));
            if (key == null) { continue; }
            if (!grouped.containsKey(key)) { grouped.put(key, new List<SObject>()); }
            grouped.get(key).add(record);
        }
        return grouped;
    }

    /**
     * Groups records by a field's value as a String, e.g. Accounts by Industry. Keys are case-sensitive, as Map keys are in Apex.
     * Cast a group back to its concrete type where you use it: (List<Account>) grouped.get('Energy').
     * @param records The records. Can be null.
     * @param field The field to group by.
     * @return A map from each distinct value to its records, in original order. Records where the field is blank are left out.
     */
    public static Map<String, List<SObject>> groupByString(List<SObject> records, SObjectField field) {
        Map<String, List<SObject>> grouped = new Map<String, List<SObject>>();
        if (records == null) { return grouped; }
        for (SObject record : records) {
            Object value = read(record, field);
            if (isBlank(value)) { continue; }
            String key = String.valueOf(value);
            if (!grouped.containsKey(key)) { grouped.put(key, new List<SObject>()); }
            grouped.get(key).add(record);
        }
        return grouped;
    }

    /**
     * Reads one group out of a groupById result without a null check: a plain Map.get returns null for a key that has
     * no records, and iterating that throws. Cast the result where you use it: (List<Opportunity>) getGroup(grouped, accountId).
     * @param grouped The result of groupById. Can be null.
     * @param key The key to read. Can be null.
     * @return The key's records, or an empty list if there are none.
     */
    public static List<SObject> getGroup(Map<Id, List<SObject>> grouped, Id key) {
        List<SObject> members = grouped == null || key == null ? null : grouped.get(key);
        return members != null ? members : new List<SObject>();
    }

    /**
     * Reads one group out of a groupByString result without a null check. See the Id overload for why.
     * @param grouped The result of groupByString. Can be null.
     * @param key The key to read. Can be null.
     * @return The key's records, or an empty list if there are none.
     */
    public static List<SObject> getGroup(Map<String, List<SObject>> grouped, String key) {
        List<SObject> members = grouped == null || key == null ? null : grouped.get(key);
        return members != null ? members : new List<SObject>();
    }

    /**
     * Indexes records by an Id-valued field, for a lookup by that field instead of by the record's own Id.
     * If two records share a value, the last one wins; use groupById when that can happen.
     * @param records The records. Can be null.
     * @param field The Id-valued field to index by.
     * @return A map from field value to record. Records where the field is empty are left out.
     * @throws StringException if the field holds text that isn't a valid Id.
     */
    public static Map<Id, SObject> indexById(List<SObject> records, SObjectField field) {
        Map<Id, SObject> indexed = new Map<Id, SObject>();
        if (records == null) { return indexed; }
        for (SObject record : records) {
            Id key = toId(read(record, field));
            if (key != null) { indexed.put(key, record); }
        }
        return indexed;
    }

    /**
     * Indexes records by a field's value as a String, e.g. Contacts by Email or Accounts by an external Id.
     * If two records share a value, the last one wins; use groupByString when that can happen.
     * @param records The records. Can be null.
     * @param field The field to index by.
     * @return A map from field value to record. Records where the field is blank are left out.
     */
    public static Map<String, SObject> indexByString(List<SObject> records, SObjectField field) {
        Map<String, SObject> indexed = new Map<String, SObject>();
        if (records == null) { return indexed; }
        for (SObject record : records) {
            Object value = read(record, field);
            if (!isBlank(value)) { indexed.put(String.valueOf(value), record); }
        }
        return indexed;
    }

    /**
     * Keeps the records whose field equals a value. Strings compare case-sensitively.
     * @param records The records. Can be null; null entries are skipped.
     * @param field The field to test.
     * @param expected The value to match. Null matches records where the field is empty.
     * @return The matching records, in original order.
     */
    public static List<SObject> filterByValue(List<SObject> records, SObjectField field, Object expected) {
        List<SObject> matching = new List<SObject>();
        if (records == null) { return matching; }
        for (SObject record : records) {
            if (record != null && valuesEqual(read(record, field), expected)) { matching.add(record); }
        }
        return matching;
    }

    /**
     * Keeps the records whose field equals any of the given values, e.g. a Stage of 'Closed Won' or 'Closed Lost'.
     * @param records The records. Can be null; null entries are skipped.
     * @param field The field to test.
     * @param allowed The accepted values. Null or empty matches nothing.
     * @return The matching records, in original order.
     */
    public static List<SObject> filterByAnyValue(List<SObject> records, SObjectField field, List<Object> allowed) {
        List<SObject> matching = new List<SObject>();
        if (records == null || allowed == null || allowed.isEmpty()) { return matching; }
        for (SObject record : records) {
            if (record == null) { continue; }
            Object value = read(record, field);
            for (Object candidate : allowed) {
                if (valuesEqual(value, candidate)) {
                    matching.add(record);
                    break;
                }
            }
        }
        return matching;
    }

    /**
     * Keeps the records whose Id-valued field is in the given set, e.g. Contacts whose AccountId is one of these accounts.
     * @param records The records. Can be null.
     * @param field The Id-valued field to test.
     * @param ids The accepted Ids. Null or empty matches nothing.
     * @return The matching records, in original order.
     * @throws StringException if the field holds text that isn't a valid Id.
     */
    public static List<SObject> filterByIdIn(List<SObject> records, SObjectField field, Set<Id> ids) {
        List<SObject> matching = new List<SObject>();
        if (records == null || ids == null || ids.isEmpty()) { return matching; }
        for (SObject record : records) {
            Id value = toId(read(record, field));
            if (value != null && ids.contains(value)) { matching.add(record); }
        }
        return matching;
    }

    /**
     * Keeps the records where a field is populated (not null, and not blank for text).
     * @param records The records. Can be null.
     * @param field The field to test.
     * @return The records with a value, in original order.
     */
    public static List<SObject> filterWithValue(List<SObject> records, SObjectField field) {
        List<SObject> matching = new List<SObject>();
        if (records == null) { return matching; }
        for (SObject record : records) {
            if (!isBlank(read(record, field))) { matching.add(record); }
        }
        return matching;
    }

    /**
     * Keeps the records where a field is empty (null, or blank for text). The opposite of filterWithValue.
     * @param records The records. Can be null; null entries are skipped.
     * @param field The field to test.
     * @return The records without a value, in original order.
     */
    public static List<SObject> filterWithoutValue(List<SObject> records, SObjectField field) {
        List<SObject> matching = new List<SObject>();
        if (records == null) { return matching; }
        for (SObject record : records) {
            if (record != null && isBlank(read(record, field))) { matching.add(record); }
        }
        return matching;
    }

    /**
     * Tells whether a field's value differs between a record and its previous version. With no previous version
     * (an insert), the field counts as changed when it has a value. Strings compare case-sensitively, so a change
     * from 'acme' to 'ACME' counts.
     * @param newRecord The record as it is now, e.g. from Trigger.new.
     * @param oldRecord The record as it was, e.g. Trigger.oldMap.get(newRecord.Id). Null on insert.
     * @param field The field to compare.
     * @return True if the value changed. False if newRecord is null.
     */
    public static Boolean hasChanged(SObject newRecord, SObject oldRecord, SObjectField field) {
        if (newRecord == null) { return false; }
        Object newValue = read(newRecord, field);
        if (oldRecord == null) { return !isBlank(newValue); }
        return !valuesEqual(newValue, read(oldRecord, field));
    }

    /**
     * Keeps the records whose field changed, comparing each to its entry in the old map.
     * @param newRecords The records as they are now, e.g. Trigger.new.
     * @param oldMap The previous versions by Id, e.g. Trigger.oldMap. Null or empty on insert.
     * @param field The field to compare.
     * @return The records where the field changed, in original order.
     */
    public static List<SObject> getChanged(List<SObject> newRecords, Map<Id, SObject> oldMap, SObjectField field) {
        List<SObject> changed = new List<SObject>();
        if (newRecords == null) { return changed; }
        for (SObject record : newRecords) {
            if (hasChanged(record, previousVersion(record, oldMap), field)) { changed.add(record); }
        }
        return changed;
    }

    /**
     * Keeps the records whose field changed AND now equals a value, e.g. the Opportunities that just moved to 'Closed Won'.
     * A record already at that value before the update doesn't count.
     * @param newRecords The records as they are now, e.g. Trigger.new.
     * @param oldMap The previous versions by Id, e.g. Trigger.oldMap. Null or empty on insert.
     * @param field The field to compare.
     * @param newValue The value the field must have changed to.
     * @return The matching records, in original order.
     */
    public static List<SObject> getChangedTo(List<SObject> newRecords, Map<Id, SObject> oldMap, SObjectField field, Object newValue) {
        List<SObject> changed = new List<SObject>();
        if (newRecords == null) { return changed; }
        for (SObject record : newRecords) {
            if (valuesEqual(read(record, field), newValue) && hasChanged(record, previousVersion(record, oldMap), field)) {
                changed.add(record);
            }
        }
        return changed;
    }

    /**
     * Keeps the records where at least one of the given fields changed.
     * @param newRecords The records as they are now, e.g. Trigger.new.
     * @param oldMap The previous versions by Id, e.g. Trigger.oldMap. Null or empty on insert.
     * @param fields The fields to compare. Null or empty matches nothing.
     * @return The records where any field changed, each listed once, in original order.
     */
    public static List<SObject> getChangedAny(List<SObject> newRecords, Map<Id, SObject> oldMap, List<SObjectField> fields) {
        List<SObject> changed = new List<SObject>();
        if (newRecords == null || fields == null || fields.isEmpty()) { return changed; }
        for (SObject record : newRecords) {
            SObject previous = previousVersion(record, oldMap);
            for (SObjectField field : fields) {
                if (hasChanged(record, previous, field)) {
                    changed.add(record);
                    break;
                }
            }
        }
        return changed;
    }

    /**
     * Adds up a numeric field (Number, Currency, Percent), e.g. the total Amount of a list of Opportunities.
     * @param records The records. Can be null.
     * @param field The numeric field to add up.
     * @return The total. Records where the field is null count as zero, so the result is 0 for a null or empty list.
     * @throws TypeException if the field isn't numeric.
     */
    public static Decimal sum(List<SObject> records, SObjectField field) {
        Decimal total = 0;
        if (records == null) { return total; }
        for (SObject record : records) {
            Object value = read(record, field);
            if (value != null) { total += toDecimal(value); }
        }
        return total;
    }

    /**
     * Finds the smallest value of a numeric field.
     * @param records The records. Can be null.
     * @param field The numeric field to compare.
     * @return The smallest value, or null if no record has one.
     * @throws TypeException if the field isn't numeric.
     */
    public static Decimal min(List<SObject> records, SObjectField field) {
        Decimal smallest;
        if (records == null) { return smallest; }
        for (SObject record : records) {
            Object value = read(record, field);
            if (value == null) { continue; }
            Decimal candidate = toDecimal(value);
            if (smallest == null || candidate < smallest) { smallest = candidate; }
        }
        return smallest;
    }

    /**
     * Finds the largest value of a numeric field.
     * @param records The records. Can be null.
     * @param field The numeric field to compare.
     * @return The largest value, or null if no record has one.
     * @throws TypeException if the field isn't numeric.
     */
    public static Decimal max(List<SObject> records, SObjectField field) {
        Decimal largest;
        if (records == null) { return largest; }
        for (SObject record : records) {
            Object value = read(record, field);
            if (value == null) { continue; }
            Decimal candidate = toDecimal(value);
            if (largest == null || candidate > largest) { largest = candidate; }
        }
        return largest;
    }

    /**
     * Adds up a numeric field per parent, the usual shape of a rollup in a trigger, e.g. the total Amount of Opportunities
     * per AccountId. A parent whose records all have a null value still appears, with a total of 0.
     * @param records The records. Can be null.
     * @param groupField The Id-valued field to group by, e.g. Opportunity.AccountId.
     * @param valueField The numeric field to add up, e.g. Opportunity.Amount.
     * @return A map from each distinct groupField value to its total. Records where groupField is empty are left out.
     * @throws TypeException if valueField isn't numeric.
     * @throws StringException if groupField holds text that isn't a valid Id.
     */
    public static Map<Id, Decimal> sumGroupedById(List<SObject> records, SObjectField groupField, SObjectField valueField) {
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        if (records == null) { return totals; }
        for (SObject record : records) {
            Id key = toId(read(record, groupField));
            if (key == null) { continue; }
            Decimal current = totals.containsKey(key) ? totals.get(key) : 0;
            Object value = read(record, valueField);
            totals.put(key, value == null ? current : current + toDecimal(value));
        }
        return totals;
    }

    /**
     * Splits records into consecutive chunks of at most the given size, to stay under a limit per transaction, callout,
     * or enqueued job. Every chunk is full except possibly the last, and the original order is kept.
     * @param records The records. Can be null.
     * @param size The maximum size of each chunk. Must be at least 1.
     * @return The chunks. Empty for a null or empty list.
     * @throws CollectionUtilsException if size is null or less than 1.
     */
    public static List<List<SObject>> partition(List<SObject> records, Integer size) {
        requirePositiveSize(size);
        List<List<SObject>> chunks = new List<List<SObject>>();
        if (records == null) { return chunks; }
        List<SObject> current = new List<SObject>();
        for (SObject record : records) {
            current.add(record);
            if (current.size() == size) {
                chunks.add(current);
                current = new List<SObject>();
            }
        }
        if (!current.isEmpty()) { chunks.add(current); }
        return chunks;
    }

    /**
     * Splits Ids into consecutive chunks of at most the given size. Same behavior as the SObject overload.
     * @param ids The Ids. Can be null.
     * @param size The maximum size of each chunk. Must be at least 1.
     * @return The chunks. Empty for a null or empty list.
     * @throws CollectionUtilsException if size is null or less than 1.
     */
    public static List<List<Id>> partition(List<Id> ids, Integer size) {
        requirePositiveSize(size);
        List<List<Id>> chunks = new List<List<Id>>();
        if (ids == null) { return chunks; }
        List<Id> current = new List<Id>();
        for (Id value : ids) {
            current.add(value);
            if (current.size() == size) {
                chunks.add(current);
                current = new List<Id>();
            }
        }
        if (!current.isEmpty()) { chunks.add(current); }
        return chunks;
    }

    /**
     * Splits Strings into consecutive chunks of at most the given size. Same behavior as the SObject overload.
     * @param values The Strings. Can be null.
     * @param size The maximum size of each chunk. Must be at least 1.
     * @return The chunks. Empty for a null or empty list.
     * @throws CollectionUtilsException if size is null or less than 1.
     */
    public static List<List<String>> partition(List<String> values, Integer size) {
        requirePositiveSize(size);
        List<List<String>> chunks = new List<List<String>>();
        if (values == null) { return chunks; }
        List<String> current = new List<String>();
        for (String value : values) {
            current.add(value);
            if (current.size() == size) {
                chunks.add(current);
                current = new List<String>();
            }
        }
        if (!current.isEmpty()) { chunks.add(current); }
        return chunks;
    }

    /**
     * Reads a field from a record without failing on a null record.
     * @param record The record. Can be null.
     * @param field The field to read.
     * @return The field's value, or null if the record is null.
     */
    private static Object read(SObject record, SObjectField field) {
        return record == null ? null : record.get(field);
    }

    /**
     * Finds a record's previous version in a trigger-style old map.
     * @param record The record as it is now. Can be null.
     * @param oldMap The previous versions by Id. Can be null.
     * @return The previous version, or null for a new record, a null record, or a null map.
     */
    private static SObject previousVersion(SObject record, Map<Id, SObject> oldMap) {
        if (record == null || record.Id == null || oldMap == null) { return null; }
        return oldMap.get(record.Id);
    }

    /**
     * Tells whether a field value counts as empty: null, or a text value that is only whitespace.
     * @param value The value to test.
     * @return True if the value is empty.
     */
    private static Boolean isBlank(Object value) {
        return value == null || (value instanceof String && String.isBlank((String) value));
    }

    /**
     * Converts a field value to an Id.
     * @param value A value holding an Id, either as an Id or as a String.
     * @return The Id, or null if the value is empty.
     */
    private static Id toId(Object value) {
        return isBlank(value) ? null : Id.valueOf(String.valueOf(value));
    }

    /**
     * Converts a numeric field value to a Decimal, whatever numeric type Salesforce returned for the field.
     * @param value A numeric value. Must not be null.
     * @return The value as a Decimal.
     */
    private static Decimal toDecimal(Object value) {
        return value instanceof Decimal ? (Decimal) value : Decimal.valueOf(String.valueOf(value));
    }

    /**
     * Compares two field values for equality. Unlike the == operator on Strings, text is compared case-sensitively.
     * @param first The first value. Can be null.
     * @param second The second value. Can be null.
     * @return True if both are null, or both hold the same value.
     */
    private static Boolean valuesEqual(Object first, Object second) {
        if (first == null || second == null) { return first == second; }
        if (first instanceof String && second instanceof String) { return ((String) first).equals((String) second); }
        return first == second;
    }

    /**
     * Rejects a chunk size that would make partition loop forever or return nothing useful.
     * @param size The requested chunk size.
     * @throws CollectionUtilsException if size is null or less than 1.
     */
    private static void requirePositiveSize(Integer size) {
        if (size == null || size < 1) { throw new CollectionUtilsException('The chunk size must be at least 1, but was ' + size + '.'); }
    }

    /**
     * Exception thrown when a method is called with an argument it can't work with.
     */
    public class CollectionUtilsException extends Exception {}
}
