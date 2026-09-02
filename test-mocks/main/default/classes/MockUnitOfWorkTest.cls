@IsTest(isParallel=true)
private class MockUnitOfWorkTest {
	@IsTest
	private static void installShouldMakeTheMockTheCurrentUnitOfWork() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();

		System.Assert.areEqual(
			mockUow.instance(),
			UnitOfWork.getCurrent(),
			'getCurrent should hand back the installed mock, so Trigger Actions pick it up'
		);
	}

	@IsTest
	private static void createShouldNotInstallTheMock() {
		MockUnitOfWork mockUow = MockUnitOfWork.create();

		System.Assert.areNotEqual(
			mockUow.instance(),
			UnitOfWork.getCurrent(),
			'create should leave the ambient UnitOfWork alone'
		);
	}

	@IsTest
	private static void registeredNewShouldCaptureRecordsFromBothOverloads() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();

		UnitOfWork.getCurrent().registerNew(new Account(Name = 'Acme'));
		UnitOfWork.getCurrent()
			.registerNew(
				new List<SObject>{ new Contact(LastName = 'Coyote'), new Contact(LastName = 'Road') }
			);

		List<SObject> registered = mockUow.registeredNew();
		System.Assert.areEqual(3, registered.size(), 'All three records should have been captured');
		System.Assert.areEqual(
			'Acme',
			((Account) registered[0]).Name,
			'The single-record overload should be captured first'
		);
	}

	@IsTest
	private static void registeredNewShouldCaptureAStronglyTypedList() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();
		List<Account> accounts = new List<Account>{
			new Account(Name = 'First'),
			new Account(Name = 'Second')
		};

		UnitOfWork.getCurrent().registerNew(accounts);

		System.Assert.areEqual(
			2,
			mockUow.registeredNew().size(),
			'A List<Account> should be captured just like a List<SObject>'
		);
	}

	@IsTest
	private static void registeredDirtyShouldCaptureRecords() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();
		Account account = new Account(Id = fakeAccountId(), Rating = 'Hot');

		UnitOfWork.getCurrent().registerDirty(account);

		System.Assert.areEqual(
			new List<SObject>{ account },
			mockUow.registeredDirty(),
			'The record registered as dirty should have been captured'
		);
	}

	@IsTest
	private static void registeredDeletedShouldCaptureRecords() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();
		Account account = new Account(Id = fakeAccountId());

		UnitOfWork.getCurrent().registerDeleted(account);

		System.Assert.areEqual(
			new List<SObject>{ account },
			mockUow.registeredDeleted(),
			'The record registered as deleted should have been captured'
		);
	}

	@IsTest
	private static void nothingRegisteredShouldReportEmptyLists() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();

		System.Assert.isTrue(mockUow.registeredNew().isEmpty(), 'Nothing was registered as new');
		System.Assert.isTrue(mockUow.registeredDirty().isEmpty(), 'Nothing was registered as dirty');
		System.Assert.isTrue(
			mockUow.registeredDeleted().isEmpty(),
			'Nothing was registered as deleted'
		);
		System.Assert.isFalse(mockUow.wasCommitted(), 'Nothing was committed');
	}

	@IsTest
	private static void wasCommittedShouldBeTrueAfterCommitCurrent() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();
		UnitOfWork.getCurrent().registerNew(new Account(Name = 'Acme'));

		UnitOfWork.commitCurrent();

		System.Assert.isTrue(
			mockUow.wasCommitted(),
			'commitCurrent should have committed the installed mock'
		);
	}

	@IsTest
	private static void aMockedUnitOfWorkShouldNotPerformDml() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();

		UnitOfWork.getCurrent().registerNew(new Account(Name = 'Acme'));
		UnitOfWork.commitCurrent();

		System.Assert.areEqual(
			1,
			mockUow.registeredNew().size(),
			'The registration should still have been recorded'
		);
		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Account],
			'No Account should actually have been inserted'
		);
	}

	@IsTest
	private static void callsShouldExposeTheUnderlyingMock() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();
		Account parent = new Account(Name = 'Acme');
		Contact child = new Contact(LastName = 'Coyote');

		UnitOfWork.getCurrent().registerRelationship(child, Contact.AccountId, parent);

		mockUow.calls().assertCalledOnce('registerRelationship');
		List<Object> arguments = mockUow.calls().argumentsOf('registerRelationship');
		System.Assert.areEqual(3, arguments.size(), 'registerRelationship takes three arguments');
		System.Assert.areEqual(child, arguments[0], 'The child record should be captured');
		System.Assert.areEqual(parent, arguments[2], 'The parent record should be captured');
	}

	private static Id fakeAccountId() {
		return Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() +
			'000000000001';
	}
}
