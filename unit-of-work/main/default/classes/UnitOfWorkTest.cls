@IsTest(isParallel=true)
private class UnitOfWorkTest {
	@IsTest
	private static void registerNewShouldInsertRecords() {
		UnitOfWork uow = new UnitOfWork();
		uow.registerNew(new Account(Name = 'Acme'));

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			1,
			[SELECT COUNT() FROM Account WHERE Name = 'Acme'],
			'The registered Account should have been inserted'
		);
	}

	@IsTest
	private static void registerDirtyShouldUpdateRecords() {
		Account account = new Account(Name = 'Acme');
		insert account;
		account.Name = 'Acme Updated';
		UnitOfWork uow = new UnitOfWork();
		uow.registerDirty(account);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			'Acme Updated',
			[SELECT Name FROM Account WHERE Id = :account.Id].Name,
			'The registered Account should have been updated'
		);
	}

	@IsTest
	private static void registerDeletedShouldDeleteRecords() {
		Account account = new Account(Name = 'Acme');
		insert account;
		UnitOfWork uow = new UnitOfWork();
		uow.registerDeleted(account);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Account WHERE Id = :account.Id],
			'The registered Account should have been deleted'
		);
	}

	@IsTest
	private static void registerRelationshipShouldPopulateLookupAfterParentIsInserted() {
		Account account = new Account(Name = 'Acme');
		Contact newContact = new Contact(LastName = 'Coyote');
		UnitOfWork uow = new UnitOfWork();
		uow.registerNew(account);
		uow.registerNew(newContact);
		uow.registerRelationship(newContact, Contact.AccountId, account);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			account.Id,
			[SELECT AccountId FROM Contact WHERE Id = :newContact.Id].AccountId,
			'The Contact should be related to the newly inserted Account'
		);
	}

	@IsTest
	private static void deleteOrderShouldBeTheReverseOfRegistrationOrder() {
		Account account = new Account(Name = 'Acme');
		insert account;
		Contact contact = new Contact(LastName = 'Coyote', AccountId = account.Id);
		insert contact;
		UnitOfWork uow = new UnitOfWork();
		uow.registerDeleted(account);
		uow.registerDeleted(contact);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			new List<Schema.SObjectType>{
				Schema.Account.SObjectType,
				Schema.Contact.SObjectType
			},
			uow.sObjectTypeOrder,
			'Types should be tracked in registration order, so deletes commit in reverse'
		);
		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Contact WHERE Id = :contact.Id],
			'The Contact should have been deleted'
		);
	}

	@IsTest
	private static void commitWorkShouldRollBackEverythingOnFailure() {
		UnitOfWork uow = new UnitOfWork();
		uow.registerNew(new Contact(LastName = 'Coyote'));
		uow.registerNew(new Account());

		Test.startTest();
		Boolean threw = false;
		try {
			uow.commitWork();
		} catch (DmlException e) {
			threw = true;
		}
		Test.stopTest();

		System.Assert.isTrue(
			threw,
			'commitWork should surface the DmlException from the invalid Account'
		);
		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Contact WHERE LastName = 'Coyote'],
			'The successful Contact insert should have been rolled back'
		);
	}

	@IsTest
	private static void commitWorkCalledTwiceShouldThrow() {
		UnitOfWork uow = new UnitOfWork();
		uow.commitWork();

		Test.startTest();
		Exception caught;
		try {
			uow.commitWork();
		} catch (UnitOfWork.UnitOfWorkException e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(
			caught,
			'Committing a second time should throw'
		);
		System.Assert.areEqual(
			UnitOfWork.ALREADY_COMMITTED_MESSAGE,
			caught.getMessage(),
			'The exception message should explain that this instance is spent'
		);
	}

	@IsTest
	private static void registeringWorkAfterCommitShouldThrow() {
		UnitOfWork uow = new UnitOfWork();
		uow.commitWork();

		Test.startTest();
		Exception caught;
		try {
			uow.registerNew(new Account(Name = 'Acme'));
		} catch (UnitOfWork.UnitOfWorkException e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(
			caught,
			'Registering work on an already-committed instance should throw'
		);
	}

	@IsTest
	private static void commitWorkWithNoRegisteredWorkShouldDoNothing() {
		UnitOfWork uow = new UnitOfWork();

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.isTrue(true, 'commitWork should not throw when nothing is registered');
	}

	@IsTest
	private static void getCurrentShouldReturnTheSameInstanceUntilCommitted() {
		UnitOfWork first = UnitOfWork.getCurrent();
		UnitOfWork second = UnitOfWork.getCurrent();

		System.Assert.areEqual(
			first,
			second,
			'getCurrent should return the same instance until it is committed'
		);
	}

	@IsTest
	private static void commitCurrentShouldCommitRegisteredWorkAndClearTheInstance() {
		UnitOfWork.getCurrent().registerNew(new Account(Name = 'Acme'));

		Test.startTest();
		UnitOfWork.commitCurrent();
		Test.stopTest();

		System.Assert.areEqual(
			1,
			[SELECT COUNT() FROM Account WHERE Name = 'Acme'],
			'The work registered on the current UnitOfWork should have been committed'
		);
		System.Assert.isNull(
			UnitOfWork.current,
			'The current instance should be cleared after committing'
		);
	}

	@IsTest
	private static void getCurrentShouldReturnANewInstanceAfterCommitting() {
		UnitOfWork beforeCommit = UnitOfWork.getCurrent();
		UnitOfWork.commitCurrent();

		UnitOfWork afterCommit = UnitOfWork.getCurrent();

		System.Assert.areNotEqual(
			beforeCommit,
			afterCommit,
			'A fresh UnitOfWork should be created after the previous one was committed'
		);
	}

	@IsTest
	private static void commitCurrentWithNoInstanceShouldDoNothing() {
		Test.startTest();
		UnitOfWork.commitCurrent();
		Test.stopTest();

		System.Assert.isTrue(
			true,
			'commitCurrent should not throw when getCurrent was never called'
		);
	}
}
