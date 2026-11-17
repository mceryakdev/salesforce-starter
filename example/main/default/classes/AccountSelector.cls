/**
 * @description Example selector: the one place Account queries live, with each query's results
 * cached for the rest of the trigger context.
 *
 * Any number of classes can ask for the same Accounts, and only the first one runs a query. Nobody
 * passes the results around, and there's no "load everything up front" step that would need to know
 * what every Trigger Action is going to want:
 *
 * ```
 * List<Account> parents = AccountSelector.getInstance().selectById(parentIds);
 * ```
 *
 * Each method is one query *shape* - one set of fields, parents, and child subqueries - with its own
 * `QueryCache`. A new need that fits an existing shape reuses that method, adding a field if it has
 * to. A genuinely different shape gets a new method with its own cache. Every method follows the same
 * three steps as `selectById`, below. See `QueryCache` for why, and for when cached results are
 * cleared.
 *
 * This class is `with sharing` rather than `inherited sharing` on purpose. Results are shared
 * between callers, so they have to be queried under one fixed set of sharing rules, not whichever
 * rules the first caller happened to run under.
 *
 * The method is an instance method reached through `getInstance()`, so a test can put a mock in
 * its place and hand the code under test whatever Accounts it needs, with no data set up at all:
 *
 * ```
 * AccountSelector.instance = (AccountSelector) Mock.of(AccountSelector.class)
 *     .returns('selectById', new List<Account>{ parent })
 *     .instance();
 * ```
 */
public with sharing class AccountSelector {
	@TestVisible
	private static AccountSelector instance;

	private final QueryCache selectByIdCache = new QueryCache();

	/**
	 * @description Returns the shared `AccountSelector`, creating it if it doesn't exist yet. Always
	 * reach for this rather than `new AccountSelector()`, so that every caller shares one set of
	 * caches, and so that a test can put a mock in its place.
	 * @return The shared `AccountSelector`.
	 */
	public static AccountSelector getInstance() {
		if (AccountSelector.instance == null) {
			AccountSelector.instance = new AccountSelector();
		}
		return AccountSelector.instance;
	}

	/**
	 * @description The Accounts with the given Ids, with their `Name` and `Rating`. Null Ids are
	 * ignored, so a set of lookup values collected straight from records can be passed as it is. Ids
	 * that match no Account the user can see are left out of the result.
	 *
	 * The returned records are shared with every other caller: read them, but don't change them.
	 * @param accountIds The Accounts to select.
	 * @return The selected Accounts, in no particular order.
	 */
	public List<Account> selectById(Set<Id> accountIds) {
		Set<Id> idsToQuery = this.selectByIdCache.notYetQueried(accountIds);
		if (!idsToQuery.isEmpty()) {
			this.selectByIdCache.store(
				idsToQuery,
				[SELECT Id, Name, Rating FROM Account WHERE Id IN :idsToQuery]
			);
		}
		return (List<Account>) this.selectByIdCache.get(accountIds);
	}
}
