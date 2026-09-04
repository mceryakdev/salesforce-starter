/**
 * @description Unit tests for `SetDefaultAccountRating`.
 *
 * A `before insert` action mutates the records it is handed, so there's nothing to mock and nothing
 * to query - build a list, call the method, check the list. Tests for this kind of action should
 * stay this simple; if one needs a mocked Unit of Work, the action is probably doing work that
 * belongs in an `after` context.
 */
@IsTest(isParallel=true)
private class SetDefaultAccountRatingTest {
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
	}
}
