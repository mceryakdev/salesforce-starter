/**
 * @description Remembers query results for the rest of the current trigger context, so that several
 * classes can ask a selector for the same records and only the first one pays for the query - with
 * nobody having to pass the results around.
 *
 * A selector method keeps one `QueryCache` as a field, and follows the same three steps every time:
 * ask which Ids haven't been queried yet, query just those with ordinary static SOQL, then return
 * the whole requested set from the cache:
 *
 * ```
 * public with sharing class AccountSelector {
 *     private final QueryCache byIdCache = new QueryCache();
 *
 *     public List<Account> selectById(Set<Id> accountIds) {
 *         Set<Id> idsToQuery = this.byIdCache.notYetQueried(accountIds);
 *         if (!idsToQuery.isEmpty()) {
 *             this.byIdCache.store(idsToQuery, [
 *                 SELECT Id, Name, Rating
 *                 FROM Account
 *                 WHERE Id IN :idsToQuery
 *             ]);
 *         }
 *         return (List<Account>) this.byIdCache.get(accountIds);
 *     }
 * }
 * ```
 *
 * The query stays a real SOQL literal, so the compiler still checks every field name and Salesforce
 * still knows the selector depends on those fields. The cache only decides *whether* it runs.
 *
 * Rules for selectors that use it:
 *
 * - **One cache per selector method.** Each method selects different fields. If two methods shared a
 *   cache, one would be handed records that are missing the fields it asked for, and reading one of
 *   those fields throws.
 * - **Only cache queries that look records up by Id.** For child records, use a subquery on the parent
 *   so they're cached under the parent's Id. A query that isn't by Id can be an ordinary selector
 *   method with no cache.
 * - **Treat the returned records as read-only.** Every caller gets the same instances, so a field one
 *   class changes is seen by the next. To update a record, register a new one with just the Id and
 *   the changed fields: `new Account(Id = account.Id, Rating = 'Hot')`.
 * - **Declare the selector `with sharing` or `without sharing`, never `inherited sharing`.** With a
 *   cache, whichever class calls first decides what every later caller sees, so the sharing rules
 *   have to belong to the query rather than to the caller.
 *
 * Cached records go stale as soon as anything writes to the database, so every cache is emptied:
 *
 * - at the start of every trigger context, by `UOWMetadataTriggerHandler`. A `before` context and its
 *   `after` context each run the query once, because the records change in between.
 * - after every `UnitOfWork` commit that wrote something, whether it succeeded or rolled back.
 *
 * DML that goes through neither - a plain `update` statement on an object with no trigger, or on one
 * whose trigger doesn't use `UOWMetadataTriggerHandler` - doesn't empty anything. If code does that
 * and then reads the same records through a selector, call `QueryCache.clearAll()` after the DML.
 */
public inherited sharing class QueryCache {
	private static final String NOT_QUERIED_MESSAGE = 'QueryCache.get was asked for {0} Id(s) that were never stored, including {1}. Call notYetQueried, query the Ids it returns, and pass the result to store before calling get.';

	private static final List<QueryCache> ALL_CACHES = new List<QueryCache>();

	private final Set<Id> queriedIds = new Set<Id>();
	private final Map<Id, SObject> recordsById = new Map<Id, SObject>();

	/**
	 * @description Creates an empty cache. Create one per selector method, as a field on the
	 * selector, so that the records it holds always have the fields that method queries.
	 */
	public QueryCache() {
		ALL_CACHES.add(this);
	}

	/**
	 * @description Empties every `QueryCache` in the transaction, so the next call to any selector
	 * queries again. `UOWMetadataTriggerHandler` and `UnitOfWork` already call this at the right
	 * moments; call it yourself only after DML that neither of them knows about, before reading the
	 * same records through a selector again.
	 */
	public static void clearAll() {
		for (QueryCache cache : ALL_CACHES) {
			cache.clear();
		}
	}

	/**
	 * @description The Ids, out of those given, that this cache hasn't queried yet - the ones the
	 * selector still needs to query. Null Ids are left out, so a set of lookup values collected
	 * straight from records (where some lookups are blank) can be passed as it is.
	 * @param recordIds The Ids the caller asked for. Null is treated as empty.
	 * @return The Ids to query. Empty when everything asked for is already cached.
	 */
	public Set<Id> notYetQueried(Set<Id> recordIds) {
		Set<Id> idsToQuery = new Set<Id>();
		if (recordIds == null) {
			return idsToQuery;
		}
		for (Id recordId : recordIds) {
			if (recordId != null && !this.queriedIds.contains(recordId)) {
				idsToQuery.add(recordId);
			}
		}
		return idsToQuery;
	}

	/**
	 * @description Stores a query's results, and remembers which Ids it was asked about. An Id that
	 * matched no record - because it was deleted, or isn't shared with the user - still counts as
	 * queried, so it isn't queried again on every call just because it came back empty.
	 * @param idsQueried The Ids the query was run for - what `notYetQueried` returned.
	 * @param records The records the query returned.
	 */
	public void store(Set<Id> idsQueried, List<SObject> records) {
		this.queriedIds.addAll(idsQueried);
		this.recordsById.putAll(records);
	}

	/**
	 * @description The cached records for the given Ids, in no particular order - like a query with
	 * no `ORDER BY`. Ids that matched no record are simply left out. Cast the result to the queried
	 * type, for example `(List<Account>)`.
	 *
	 * Throws if any of the Ids was never stored. That only happens when a selector method skips the
	 * query step, and returning the records it happened to have instead would hide the bug.
	 * @param recordIds The Ids the caller asked for. Null Ids are ignored, and a null set is treated as
	 * empty.
	 * @return The cached records for those Ids.
	 */
	public List<SObject> get(Set<Id> recordIds) {
		List<SObject> records = new List<SObject>();
		Set<Id> neverQueried = this.notYetQueried(recordIds);
		if (!neverQueried.isEmpty()) {
			throw new QueryCacheException(
				String.format(
					NOT_QUERIED_MESSAGE,
					new List<Object>{ neverQueried.size(), new List<Id>(neverQueried)[0] }
				)
			);
		}
		if (recordIds == null) {
			return records;
		}
		for (Id recordId : recordIds) {
			SObject record = this.recordsById.get(recordId);
			if (record != null) {
				records.add(record);
			}
		}
		return records;
	}

	/**
	 * @description Forgets everything this cache holds. Kept private so there's one way to empty
	 * caches - `clearAll()` - because a write that makes one cache stale can make any of them stale.
	 */
	private void clear() {
		this.queriedIds.clear();
		this.recordsById.clear();
	}

	/**
	 * @description Thrown when a `QueryCache` is used out of order - see `get`.
	 */
	public class QueryCacheException extends Exception {
	}
}
