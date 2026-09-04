/**
 * @description Unit tests for `CreateOnboardingRecords`, using a mocked Unit of Work.
 *
 * Every test here runs with **no DML and no SOQL**: the Accounts are built in memory with fake Ids,
 * and the Unit of Work is a recording stand-in. That's the payoff of registering work instead of
 * performing it - the action's decisions can be checked directly, and a failure points at this
 * action rather than at the database.
 *
 * `AccountTriggerTest` covers the other side: one real end-to-end insert proving the wiring works.
 */
@IsTest(isParallel=true)
private class CreateOnboardingRecordsTest {
	@IsTest
	private static void shouldRegisterAContactAndACaseForEachAccount() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();
		List<Account> accounts = new List<Account>{
			new Account(Id = fakeAccountId(1), Name = 'Acme'),
			new Account(Id = fakeAccountId(2), Name = 'Initech')
		};

		new CreateOnboardingRecords().afterInsert(accounts);

		List<SObject> registered = mockUow.registeredNew();
		System.Assert.areEqual(
			4,
			registered.size(),
			'Each Account should produce one Contact and one Case'
		);
	}

	@IsTest
	private static void shouldPointTheContactAtItsAccount() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();
		Id accountId = fakeAccountId(1);

		new CreateOnboardingRecords()
			.afterInsert(new List<Account>{ new Account(Id = accountId, Name = 'Acme') });

		Contact registeredContact = (Contact) mockUow.registeredNew()[0];
		System.Assert.areEqual(
			accountId,
			registeredContact.AccountId,
			'In an after-insert context the Account Id already exists, so it is set directly'
		);
		System.Assert.areEqual(
			CreateOnboardingRecords.PRIMARY_CONTACT_LAST_NAME,
			registeredContact.LastName,
			'The placeholder Contact should be named consistently'
		);
	}

	@IsTest
	private static void shouldTitleTheCaseAfterTheAccount() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();

		new CreateOnboardingRecords()
			.afterInsert(new List<Account>{ new Account(Id = fakeAccountId(1), Name = 'Acme') });

		Case registeredCase = (Case) mockUow.registeredNew()[1];
		System.Assert.areEqual(
			CreateOnboardingRecords.ONBOARDING_CASE_SUBJECT + ' - Acme',
			registeredCase.Subject,
			'The Case subject should name the Account it belongs to'
		);
	}

	@IsTest
	private static void shouldRegisterTheCaseToContactRelationshipRatherThanSettingIt() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();

		new CreateOnboardingRecords()
			.afterInsert(new List<Account>{ new Account(Id = fakeAccountId(1), Name = 'Acme') });

		Contact registeredContact = (Contact) mockUow.registeredNew()[0];
		Case registeredCase = (Case) mockUow.registeredNew()[1];
		System.Assert.isNull(
			registeredCase.ContactId,
			'ContactId cannot be set yet - the Contact has no Id at registration time'
		);

		mockUow.calls().assertCalledOnce('registerRelationship');
		List<Object> arguments = mockUow.calls().argumentsOf('registerRelationship');
		System.Assert.areEqual(
			registeredCase,
			arguments[0],
			'The Case is the record whose lookup gets populated'
		);
		System.Assert.areEqual(
			Case.ContactId,
			arguments[1],
			'ContactId is the field to populate'
		);
		System.Assert.areEqual(
			registeredContact,
			arguments[2],
			'The Contact is the record whose Id will be copied in'
		);
	}

	@IsTest
	private static void shouldRegisterNothingForAnEmptyList() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();

		new CreateOnboardingRecords().afterInsert(new List<Account>());

		System.Assert.isTrue(
			mockUow.registeredNew().isEmpty(),
			'No Accounts means nothing to register'
		);
		mockUow.calls().assertNeverCalled('registerRelationship');
	}

	@IsTest
	private static void shouldRegisterWorkInBulkWithoutPerRecordDml() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();
		List<Account> accounts = new List<Account>();
		for (Integer i = 1; i <= 200; i++) {
			accounts.add(new Account(Id = fakeAccountId(i), Name = 'Bulk Acme ' + i));
		}

		Test.startTest();
		new CreateOnboardingRecords().afterInsert(accounts);
		Test.stopTest();

		System.Assert.areEqual(
			400,
			mockUow.registeredNew().size(),
			'200 Accounts should register 200 Contacts and 200 Cases'
		);
		System.Assert.areEqual(
			200,
			mockUow.calls().callCount('registerRelationship'),
			'Each Case should be related to its own Contact'
		);
		System.Assert.areEqual(
			0,
			Limits.getDmlStatements(),
			'Registering work should not perform any DML of its own'
		);
	}

	@IsTest
	private static void shouldNotCommitTheUnitOfWorkItself() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();

		new CreateOnboardingRecords()
			.afterInsert(new List<Account>{ new Account(Id = fakeAccountId(1), Name = 'Acme') });

		System.Assert.isFalse(
			mockUow.wasCommitted(),
			'Committing is the handler\'s job at the end of the run, not an individual action\'s'
		);
	}

	/**
	 * @description Builds a syntactically valid Account Id without touching the database, so these
	 * tests can run against an `after insert` context with no DML at all.
	 * @param uniqueNumber A number that makes this Id distinct from the others in the test.
	 * @return A fake Account Id.
	 */
	private static Id fakeAccountId(Integer uniqueNumber) {
		return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() +
			String.valueOf(uniqueNumber).leftPad(12, '0');
	}
}
