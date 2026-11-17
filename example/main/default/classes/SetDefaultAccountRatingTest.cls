/**
 * @description Unit tests for `SetDefaultAccountRating`.
 *
 * A `before insert` action mutates the records it is handed, so most of these tests just build a
 * list, call the method, and check the list. If one needs a mocked Unit of Work, the action is
 * probably doing work that belongs in an `after` context.
 *
 * The parent Accounts are the one thing that comes from the database, and those tests replace
 * `AccountSelector` with a mock that returns parents built in memory. So even the inheritance rules
 * are tested with no DML and no SOQL, and without inserting a parent/child hierarchy to test
 * against. `AccountSelectorTest` covers the query itself.
 */
@IsTest(isParallel=true)
private class SetDefaultAccountRatingTest {
	@IsTest
	private static void shouldInheritTheParentsRating() {
		Account parent = new Account(Id = fakeAccountId(1), Name = 'Parent', Rating = 'Hot');
		mockSelectorReturning(new List<Account>{ parent });
		List<Account> accounts = new List<Account>{
			new Account(Name = 'Subsidiary', ParentId = parent.Id)
		};

		new SetDefaultAccountRating().beforeInsert(accounts);

		System.Assert.areEqual(
			'Hot',
			accounts[0].Rating,
			'An unrated Account should take its parent\'s Rating'
		);
	}

	@IsTest
	private static void shouldFallBackToTheDefaultWhenTheParentHasNoRating() {
		Account parent = new Account(Id = fakeAccountId(1), Name = 'Parent');
		mockSelectorReturning(new List<Account>{ parent });
		List<Account> accounts = new List<Account>{
			new Account(Name = 'Subsidiary', ParentId = parent.Id)
		};

		new SetDefaultAccountRating().beforeInsert(accounts);

		System.Assert.areEqual(
			SetDefaultAccountRating.DEFAULT_RATING,
			accounts[0].Rating,
			'A parent with no Rating has nothing to pass on'
		);
	}

	@IsTest
	private static void shouldFallBackToTheDefaultWhenTheParentIsNotReturned() {
		mockSelectorReturning(new List<Account>());
		List<Account> accounts = new List<Account>{
			new Account(Name = 'Subsidiary', ParentId = fakeAccountId(1))
		};

		new SetDefaultAccountRating().beforeInsert(accounts);

		System.Assert.areEqual(
			SetDefaultAccountRating.DEFAULT_RATING,
			accounts[0].Rating,
			'A parent the selector does not return - one the user cannot see, say - should be treated as no parent'
		);
	}

	@IsTest
	private static void shouldOnlyAskForTheParentsOfUnratedAccounts() {
		Mock mockSelector = mockSelectorReturning(new List<Account>());
		Id unratedAccountsParentId = fakeAccountId(1);
		List<Account> accounts = new List<Account>{
			new Account(Name = 'Unrated', ParentId = unratedAccountsParentId),
			new Account(Name = 'Rated', Rating = 'Cold', ParentId = fakeAccountId(2)),
			new Account(Name = 'No parent')
		};

		new SetDefaultAccountRating().beforeInsert(accounts);

		mockSelector.assertCalledOnce('selectById');
		System.Assert.areEqual(
			new Set<Id>{ unratedAccountsParentId },
			mockSelector.argumentsOf('selectById')[0],
			'Only the parent of the Account that needs a Rating is worth selecting'
		);
	}

	@IsTest
	private static void shouldDefaultTheRatingWhenItIsBlank() {
		List<Account> accounts = new List<Account>{ new Account(Name = 'Acme') };

		new SetDefaultAccountRating().beforeInsert(accounts);

		System.Assert.areEqual(
			SetDefaultAccountRating.DEFAULT_RATING,
			accounts[0].Rating,
			'An Account with no Rating should be given the default'
		);
	}

	@IsTest
	private static void shouldLeaveAnExplicitRatingAlone() {
		List<Account> accounts = new List<Account>{ new Account(Name = 'Acme', Rating = 'Hot') };

		new SetDefaultAccountRating().beforeInsert(accounts);

		System.Assert.areEqual(
			'Hot',
			accounts[0].Rating,
			'A Rating that was supplied explicitly should not be overwritten'
		);
	}

	@IsTest
	private static void shouldHandleAMixOfRatedAndUnratedAccounts() {
		List<Account> accounts = new List<Account>{
			new Account(Name = 'Rated', Rating = 'Cold'),
			new Account(Name = 'Unrated')
		};

		new SetDefaultAccountRating().beforeInsert(accounts);

		System.Assert.areEqual('Cold', accounts[0].Rating, 'The rated Account should be untouched');
		System.Assert.areEqual(
			SetDefaultAccountRating.DEFAULT_RATING,
			accounts[1].Rating,
			'The unrated Account should be defaulted'
		);
	}

	@IsTest
	private static void shouldHandleAnEmptyList() {
		List<Account> accounts = new List<Account>();

		new SetDefaultAccountRating().beforeInsert(accounts);

		System.Assert.isTrue(accounts.isEmpty(), 'An empty list should be handled without throwing');
	}

	@IsTest
	private static void shouldDefaultInBulkWithoutDml() {
		List<Account> accounts = new List<Account>();
		for (Integer i = 0; i < 200; i++) {
			accounts.add(new Account(Name = 'Bulk Acme ' + i));
		}

		Test.startTest();
		new SetDefaultAccountRating().beforeInsert(accounts);
		Test.stopTest();

		for (Account account : accounts) {
			System.Assert.areEqual(
				SetDefaultAccountRating.DEFAULT_RATING,
				account.Rating,
				'Every Account in the batch should have been defaulted'
			);
		}
		System.Assert.areEqual(
			0,
			Limits.getDmlStatements(),
			'A before-insert action changes records in place and should never perform DML'
		);
		System.Assert.areEqual(
			0,
			Limits.getQueries(),
			'With no parents to look up, the action should not run a query'
		);
	}

	/**
	 * @description Puts a mock in place of `AccountSelector`, so that the action gets the parents a
	 * test hands it instead of querying for them.
	 * @param parents The Accounts `selectById` should return, whatever it's asked for.
	 * @return The mock, for asserting on what the action asked for.
	 */
	private static Mock mockSelectorReturning(List<Account> parents) {
		Mock mockSelector = Mock.of(AccountSelector.class).returns('selectById', parents);
		AccountSelector.instance = (AccountSelector) mockSelector.instance();
		return mockSelector;
	}

	/**
	 * @description Builds a syntactically valid Account Id without touching the database, to stand in
	 * for a parent Account that already exists.
	 * @param uniqueNumber A number that makes this Id distinct from the others in the test.
	 * @return A fake Account Id.
	 */
	private static Id fakeAccountId(Integer uniqueNumber) {
		return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() +
			String.valueOf(uniqueNumber).leftPad(12, '0');
	}
}
