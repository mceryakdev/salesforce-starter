/**
 * @description Tests for `AccountSelector`, against real Accounts - a selector's whole job is the
 * query, so there's nothing to gain from mocking it here. (Code that *uses* the selector is a
 * different story; see `SetDefaultAccountRatingTest`.)
 *
 * Every test bypasses Account's Trigger Actions so that the example actions don't add records of
 * their own. `AccountTrigger` still fires, though, which `updatingAnAccountShouldMakeTheNextCallQueryAgain`
 * relies on.
 */
@IsTest(isParallel=true)
private class AccountSelectorTest {
	@TestSetup
	private static void insertAccounts() {
		TriggerBase.bypass('Account');
		insert new List<Account>{
			new Account(Name = 'Acme', Rating = 'Hot'),
			new Account(Name = 'Initech', Rating = 'Cold')
		};
		TriggerBase.clearBypass('Account');
	}

	@IsTest
	private static void selectByIdShouldReturnTheRequestedAccounts() {
		Account acme = accountNamed('Acme');

		Test.startTest();
		List<Account> selected = AccountSelector.getInstance().selectById(new Set<Id>{ acme.Id });
		Test.stopTest();

		System.Assert.areEqual(1, selected.size(), 'Only the requested Account should be returned');
		System.Assert.areEqual('Acme', selected[0].Name, 'Name should be selected');
		System.Assert.areEqual('Hot', selected[0].Rating, 'Rating should be selected');
	}

	@IsTest
	private static void repeatedCallsShouldOnlyQueryOnce() {
		Set<Id> accountIds = new Set<Id>{ accountNamed('Acme').Id };

		Test.startTest();
		AccountSelector.getInstance().selectById(accountIds);
		AccountSelector.getInstance().selectById(accountIds);
		AccountSelector.getInstance().selectById(accountIds);
		Integer queriesUsed = Limits.getQueries();
		Test.stopTest();

		System.Assert.areEqual(
			1,
			queriesUsed,
			'Three callers asking for the same Accounts should cost one query'
		);
	}

	@IsTest
	private static void aCallThatOverlapsAnEarlierOneShouldOnlyQueryTheNewIds() {
		Id acmeId = accountNamed('Acme').Id;
		Id initechId = accountNamed('Initech').Id;

		Test.startTest();
		AccountSelector.getInstance().selectById(new Set<Id>{ acmeId });
		List<Account> both = AccountSelector.getInstance().selectById(new Set<Id>{ acmeId, initechId });
		AccountSelector.getInstance().selectById(new Set<Id>{ acmeId, initechId });
		Integer queriesUsed = Limits.getQueries();
		Test.stopTest();

		System.Assert.areEqual(2, both.size(), 'Both Accounts should be returned');
		System.Assert.areEqual(
			2,
			queriesUsed,
			'The second call should query only Initech, and the third call nothing'
		);
	}

	@IsTest
	private static void updatingAnAccountShouldMakeTheNextCallQueryAgain() {
		Account acme = accountNamed('Acme');
		Set<Id> accountIds = new Set<Id>{ acme.Id };
		AccountSelector.getInstance().selectById(accountIds);
		TriggerBase.bypass('Account');

		Test.startTest();
		// AccountTrigger constructs a UOWMetadataTriggerHandler even while Account is bypassed, and
		// constructing one empties every QueryCache - so this update can't leave the old Rating cached.
		update new Account(Id = acme.Id, Rating = 'Warm');
		List<Account> selected = AccountSelector.getInstance().selectById(accountIds);
		Test.stopTest();
		TriggerBase.clearBypass('Account');

		System.Assert.areEqual(
			'Warm',
			selected[0].Rating,
			'The selector should have queried again after the update, rather than return the old Rating'
		);
	}

	@IsTest
	private static void anIdWithNoAccountShouldBeLeftOutAndNotQueriedAgain() {
		Id missingAccountId =
			Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() +
			'000000000001';

		Test.startTest();
		List<Account> firstCall = AccountSelector.getInstance()
			.selectById(new Set<Id>{ missingAccountId });
		AccountSelector.getInstance().selectById(new Set<Id>{ missingAccountId });
		Integer queriesUsed = Limits.getQueries();
		Test.stopTest();

		System.Assert.isTrue(firstCall.isEmpty(), 'An Id with no Account should return nothing');
		System.Assert.areEqual(
			1,
			queriesUsed,
			'An Id that matched nothing should not be queried again on every call'
		);
	}

	@IsTest
	private static void nullIdsShouldBeIgnoredWithoutQuerying() {
		Test.startTest();
		List<Account> selected = AccountSelector.getInstance().selectById(new Set<Id>{ null });
		Integer queriesUsed = Limits.getQueries();
		Test.stopTest();

		System.Assert.isTrue(selected.isEmpty(), 'A blank lookup should select nothing');
		System.Assert.areEqual(0, queriesUsed, 'Asking for nothing should not cost a query');
	}

	@IsTest
	private static void getInstanceShouldReturnTheSameInstanceEveryTime() {
		System.Assert.isTrue(
			AccountSelector.getInstance() === AccountSelector.getInstance(),
			'Every caller should share one selector, and so one set of caches'
		);
	}

	/**
	 * @description Looks up one of the Accounts inserted by `insertAccounts`. Called before
	 * `Test.startTest()` in every test, so that this query isn't counted against the selector's.
	 * @param name The Account's name.
	 * @return The Account.
	 */
	private static Account accountNamed(String name) {
		return [SELECT Id FROM Account WHERE Name = :name];
	}
}
