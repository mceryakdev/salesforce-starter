/**
 * @description Unit tests for `QueryCache`.
 *
 * Almost everything here runs with no SOQL and no DML: the "query results" are records built in
 * memory with fake Ids, because what's being tested is the bookkeeping, not the database. The one
 * exception, `theSelectorPatternShouldOnlyQueryOnceForRepeatedCalls`, runs the three-step selector
 * pattern against a real query - on `User`, so it needs no test data - to prove the part that
 * matters: a second caller doesn't cost a second query.
 */
@IsTest(isParallel=true)
private class QueryCacheTest {
	@IsTest
	private static void notYetQueriedShouldReturnEveryIdWhenNothingHasBeenStored() {
		QueryCache cache = new QueryCache();
		Set<Id> accountIds = new Set<Id>{ fakeAccountId(1), fakeAccountId(2) };

		System.Assert.areEqual(
			accountIds,
			cache.notYetQueried(accountIds),
			'An empty cache has queried nothing, so every Id still needs a query'
		);
	}

	@IsTest
	private static void notYetQueriedShouldLeaveOutIdsThatHaveBeenStored() {
		QueryCache cache = new QueryCache();
		cache.store(
			new Set<Id>{ fakeAccountId(1) },
			new List<Account>{ new Account(Id = fakeAccountId(1), Name = 'Acme') }
		);

		System.Assert.areEqual(
			new Set<Id>{ fakeAccountId(2) },
			cache.notYetQueried(new Set<Id>{ fakeAccountId(1), fakeAccountId(2) }),
			'Only the Id that has not been stored yet should need a query'
		);
	}

	@IsTest
	private static void notYetQueriedShouldIgnoreNullIds() {
		QueryCache cache = new QueryCache();

		System.Assert.areEqual(
			new Set<Id>{ fakeAccountId(1) },
			cache.notYetQueried(new Set<Id>{ fakeAccountId(1), null }),
			'A blank lookup collected from a record should not be passed on to the query'
		);
	}

	@IsTest
	private static void notYetQueriedShouldTreatNullAndEmptySetsAsNothingToQuery() {
		QueryCache cache = new QueryCache();

		System.Assert.isTrue(
			cache.notYetQueried(null).isEmpty(),
			'A null set asks for nothing, so there is nothing to query'
		);
		System.Assert.isTrue(
			cache.notYetQueried(new Set<Id>()).isEmpty(),
			'An empty set asks for nothing, so there is nothing to query'
		);
	}

	@IsTest
	private static void getShouldReturnOnlyTheRequestedRecords() {
		QueryCache cache = new QueryCache();
		cache.store(
			new Set<Id>{ fakeAccountId(1), fakeAccountId(2) },
			new List<Account>{
				new Account(Id = fakeAccountId(1), Name = 'Acme'),
				new Account(Id = fakeAccountId(2), Name = 'Initech')
			}
		);

		List<SObject> records = cache.get(new Set<Id>{ fakeAccountId(2) });

		System.Assert.areEqual(1, records.size(), 'Only the requested record should be returned');
		System.Assert.areEqual(
			fakeAccountId(2),
			records[0].Id,
			'The record returned should be the one that was asked for'
		);
	}

	@IsTest
	private static void getShouldReturnAListThatCanBeCastToTheQueriedType() {
		QueryCache cache = new QueryCache();
		cache.store(
			new Set<Id>{ fakeAccountId(1) },
			new List<Account>{ new Account(Id = fakeAccountId(1), Name = 'Acme') }
		);

		List<Account> accounts = (List<Account>) cache.get(new Set<Id>{ fakeAccountId(1) });

		System.Assert.areEqual(
			'Acme',
			accounts[0].Name,
			'A selector should be able to cast the result straight to the type it queried'
		);
	}

	@IsTest
	private static void anIdThatMatchedNoRecordShouldCountAsQueriedAndReturnNothing() {
		QueryCache cache = new QueryCache();
		Id deletedAccountId = fakeAccountId(1);
		cache.store(new Set<Id>{ deletedAccountId }, new List<Account>());

		System.Assert.isTrue(
			cache.notYetQueried(new Set<Id>{ deletedAccountId }).isEmpty(),
			'An Id the query found nothing for should not be queried again on every call'
		);
		System.Assert.isTrue(
			cache.get(new Set<Id>{ deletedAccountId }).isEmpty(),
			'An Id the query found nothing for should simply be left out of the result'
		);
	}

	@IsTest
	private static void getShouldThrowWhenAskedForIdsThatWereNeverStored() {
		QueryCache cache = new QueryCache();
		Id neverQueriedId = fakeAccountId(1);

		Exception caught;
		try {
			cache.get(new Set<Id>{ neverQueriedId });
		} catch (QueryCache.QueryCacheException e) {
			caught = e;
		}

		System.Assert.isNotNull(
			caught,
			'A selector that skipped the query step should fail loudly, not return nothing'
		);
		System.Assert.isTrue(
			caught.getMessage().contains(neverQueriedId),
			'The message should name an Id that was never stored: ' + caught.getMessage()
		);
	}

	@IsTest
	private static void getShouldTreatNullAndEmptySetsAsAskingForNothing() {
		QueryCache cache = new QueryCache();

		System.Assert.isTrue(
			cache.get(null).isEmpty(),
			'A null set asks for nothing, so nothing should be returned'
		);
		System.Assert.isTrue(
			cache.get(new Set<Id>{ null }).isEmpty(),
			'A null Id asks for nothing, so nothing should be returned'
		);
	}

	@IsTest
	private static void everyCallerShouldGetTheSameRecordInstances() {
		QueryCache cache = new QueryCache();
		cache.store(
			new Set<Id>{ fakeAccountId(1) },
			new List<Account>{ new Account(Id = fakeAccountId(1), Name = 'Acme') }
		);

		Account firstCallersCopy = (Account) cache.get(new Set<Id>{ fakeAccountId(1) })[0];
		firstCallersCopy.Name = 'Changed by the first caller';
		Account secondCallersCopy = (Account) cache.get(new Set<Id>{ fakeAccountId(1) })[0];

		System.Assert.areEqual(
			'Changed by the first caller',
			secondCallersCopy.Name,
			'Records are shared, not copied - which is why callers must treat them as read-only'
		);
	}

	@IsTest
	private static void clearAllShouldEmptyEveryCache() {
		QueryCache firstCache = new QueryCache();
		QueryCache secondCache = new QueryCache();
		Set<Id> accountIds = new Set<Id>{ fakeAccountId(1) };
		firstCache.store(accountIds, new List<Account>());
		secondCache.store(accountIds, new List<Account>());

		QueryCache.clearAll();

		System.Assert.areEqual(
			accountIds,
			firstCache.notYetQueried(accountIds),
			'The first cache should have forgotten what it queried'
		);
		System.Assert.areEqual(
			accountIds,
			secondCache.notYetQueried(accountIds),
			'The second cache should have forgotten what it queried too'
		);
	}

	@IsTest
	private static void theSelectorPatternShouldOnlyQueryOnceForRepeatedCalls() {
		QueryCache cache = new QueryCache();
		Set<Id> userIds = new Set<Id>{ UserInfo.getUserId() };

		Test.startTest();
		List<User> firstCall = selectUsersById(cache, userIds);
		List<User> secondCall = selectUsersById(cache, userIds);
		Integer queriesUsed = Limits.getQueries();
		Test.stopTest();

		System.Assert.areEqual(1, queriesUsed, 'The second call should be answered from the cache');
		System.Assert.areEqual(1, firstCall.size(), 'The first call should return the queried user');
		System.Assert.areEqual(
			firstCall[0],
			secondCall[0],
			'The second call should return the same record the first call queried'
		);
	}

	/**
	 * @description A stand-in selector method, written exactly the way a real one is, so the test
	 * above exercises the documented three-step pattern rather than calling the cache in some other
	 * order a real selector never would.
	 * @param cache The cache this "method" owns.
	 * @param userIds The users to select.
	 * @return The selected users.
	 */
	private static List<User> selectUsersById(QueryCache cache, Set<Id> userIds) {
		Set<Id> idsToQuery = cache.notYetQueried(userIds);
		if (!idsToQuery.isEmpty()) {
			cache.store(idsToQuery, [SELECT Id, Name FROM User WHERE Id IN :idsToQuery]);
		}
		return (List<User>) cache.get(userIds);
	}

	/**
	 * @description Builds a syntactically valid Account Id without touching the database, so these
	 * tests can stand in for query results with records built in memory.
	 * @param uniqueNumber A number that makes this Id distinct from the others in the test.
	 * @return A fake Account Id.
	 */
	private static Id fakeAccountId(Integer uniqueNumber) {
		return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() +
			String.valueOf(uniqueNumber).leftPad(12, '0');
	}
}
