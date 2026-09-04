@IsTest(isParallel=true)
private class UnitOfWorkTest {
	/**
	 * Bypasses TriggerBase-based automation on Account and Contact for the calling test method.
	 * UnitOfWork has no knowledge of triggers and is meant to work in any org - including ones with
	 * real automation configured on these objects, as this repo's own `example` package
	 * demonstrates. A static bypass set in @TestSetup does not survive into @IsTest methods (Apex
	 * resets static state between them), so this has to be called from inside each test method
	 * that performs DML on these objects, not from a shared setup method.
	 */
	private static void bypassAmbientTriggers() {
		TriggerBase.bypass('Account');
		TriggerBase.bypass('Contact');
	}

	@IsTest
	private static void registerNewShouldInsertRecords() {
		bypassAmbientTriggers();
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
		bypassAmbientTriggers();
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
	private static void registerDirtyCalledTwiceForSameRecordShouldMergeBothFields() {
		bypassAmbientTriggers();
		Account account = new Account(Name = 'Acme', Industry = 'Technology');
		insert account;
		UnitOfWork uow = new UnitOfWork();
		uow.registerDirty(new Account(Id = account.Id, Rating = 'Hot'));
		uow.registerDirty(new Account(Id = account.Id, Description = 'Follow up'));

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		Account updated = [
			SELECT Rating, Description
			FROM Account
			WHERE Id = :account.Id
		];
		System.Assert.areEqual(
			'Hot',
			updated.Rating,
			'The first registerDirty call\'s field should have been applied'
		);
		System.Assert.areEqual(
			'Follow up',
			updated.Description,
			'The second registerDirty call\'s field should also have been applied'
		);
	}

	@IsTest
	private static void registerDirtyCalledTwiceForSameFieldShouldUseTheLastValue() {
		bypassAmbientTriggers();
		Account account = new Account(Name = 'Acme');
		insert account;
		UnitOfWork uow = new UnitOfWork();
		uow.registerDirty(new Account(Id = account.Id, Rating = 'Warm'));
		uow.registerDirty(new Account(Id = account.Id, Rating = 'Hot'));

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			'Hot',
			[SELECT Rating FROM Account WHERE Id = :account.Id].Rating,
			'The most recently registered value for a field should win'
		);
	}

	@IsTest
	private static void registerDirtyWithoutAnIdShouldThrow() {
		UnitOfWork uow = new UnitOfWork();

		Test.startTest();
		Exception caught;
		try {
			uow.registerDirty(new Account(Name = 'Acme'));
		} catch (UnitOfWork.UnitOfWorkException e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(
			caught,
			'registerDirty should require the record to already have an Id'
		);
	}

	@IsTest
	private static void registerDeletedWithoutAnIdShouldThrow() {
		UnitOfWork uow = new UnitOfWork();

		Test.startTest();
		Exception caught;
		try {
			uow.registerDeleted(new Account(Name = 'Acme'));
		} catch (UnitOfWork.UnitOfWorkException e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(
			caught,
			'registerDeleted should require the record to already have an Id'
		);
	}

	@IsTest
	private static void registerDeletedCalledTwiceForSameRecordShouldNotThrow() {
		bypassAmbientTriggers();
		Account account = new Account(Name = 'Acme');
		insert account;
		UnitOfWork uow = new UnitOfWork();
		uow.registerDeleted(account);
		uow.registerDeleted(account);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Account WHERE Id = :account.Id],
			'The Account should have been deleted exactly once, without a duplicate-id error'
		);
	}

	@IsTest
	private static void registerDeletedShouldDeleteRecords() {
		bypassAmbientTriggers();
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
		bypassAmbientTriggers();
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
		bypassAmbientTriggers();
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
		bypassAmbientTriggers();
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
		bypassAmbientTriggers();
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

	@IsTest
	private static void registerNewShouldBulkInsertRecords() {
		bypassAmbientTriggers();
		List<Account> accounts = new List<Account>();
		for (Integer i = 0; i < 200; i++) {
			accounts.add(new Account(Name = 'Bulk Acme ' + i));
		}
		UnitOfWork uow = new UnitOfWork();
		uow.registerNew(accounts);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			200,
			[SELECT COUNT() FROM Account WHERE Name LIKE 'Bulk Acme %'],
			'All 200 registered Accounts should have been inserted'
		);
	}

	@IsTest
	private static void registerDirtyShouldBulkUpdateRecords() {
		bypassAmbientTriggers();
		List<Account> accounts = new List<Account>();
		for (Integer i = 0; i < 200; i++) {
			accounts.add(new Account(Name = 'Bulk Acme ' + i));
		}
		insert accounts;

		List<Account> dirtyAccounts = new List<Account>();
		for (Account account : accounts) {
			dirtyAccounts.add(new Account(Id = account.Id, Rating = 'Hot'));
		}
		UnitOfWork uow = new UnitOfWork();
		uow.registerDirty(dirtyAccounts);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			200,
			[SELECT COUNT() FROM Account WHERE Name LIKE 'Bulk Acme %' AND Rating = 'Hot'],
			'All 200 registered Accounts should have been updated'
		);
	}

	@IsTest
	private static void registerDirtyWithDuplicateIdsInOneListShouldMergeFields() {
		bypassAmbientTriggers();
		Account account = new Account(Name = 'Acme', Industry = 'Technology');
		insert account;
		UnitOfWork uow = new UnitOfWork();
		uow.registerDirty(
			new List<SObject>{
				new Account(Id = account.Id, Rating = 'Hot'),
				new Account(Id = account.Id, Description = 'Follow up')
			}
		);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		Account updated = [SELECT Rating, Description FROM Account WHERE Id = :account.Id];
		System.Assert.areEqual(
			'Hot',
			updated.Rating,
			'The first list entry\'s field should have been applied'
		);
		System.Assert.areEqual(
			'Follow up',
			updated.Description,
			'The second list entry\'s field should also have been applied'
		);
	}

	@IsTest
	private static void registerDirtyShouldMergeDuplicateIdsAcrossABulkRegistration() {
		bypassAmbientTriggers();
		List<Account> accounts = new List<Account>();
		for (Integer i = 0; i < 200; i++) {
			accounts.add(new Account(Name = 'Bulk Acme ' + i));
		}
		insert accounts;

		List<SObject> dirtyRecords = new List<SObject>();
		for (Account account : accounts) {
			dirtyRecords.add(new Account(Id = account.Id, Rating = 'Warm'));
			dirtyRecords.add(new Account(Id = account.Id, Rating = 'Hot'));
		}
		UnitOfWork uow = new UnitOfWork();
		uow.registerDirty(dirtyRecords);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			200,
			[SELECT COUNT() FROM Account WHERE Name LIKE 'Bulk Acme %' AND Rating = 'Hot'],
			'Duplicate registrations for the same Id should merge into a single update, with the last value winning'
		);
	}

	@IsTest
	private static void registerDeletedShouldBulkDeleteRecords() {
		bypassAmbientTriggers();
		List<Account> accounts = new List<Account>();
		for (Integer i = 0; i < 200; i++) {
			accounts.add(new Account(Name = 'Bulk Acme ' + i));
		}
		insert accounts;
		UnitOfWork uow = new UnitOfWork();
		uow.registerDeleted(accounts);

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Account WHERE Name LIKE 'Bulk Acme %'],
			'All 200 registered Accounts should have been deleted'
		);
	}

	@IsTest
	private static void registerRelationshipShouldPopulateLookupsForManyRecords() {
		bypassAmbientTriggers();
		List<Account> accounts = new List<Account>();
		List<Contact> contacts = new List<Contact>();
		UnitOfWork uow = new UnitOfWork();
		for (Integer i = 0; i < 200; i++) {
			Account acct = new Account(Name = 'Bulk Acme ' + i);
			Contact con = new Contact(LastName = 'Bulk Coyote ' + i);
			accounts.add(acct);
			contacts.add(con);
			uow.registerNew(acct);
			uow.registerNew(con);
			uow.registerRelationship(con, Contact.AccountId, acct);
		}

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		Map<String, Id> accountIdByName = new Map<String, Id>();
		for (Account account : [SELECT Id, Name FROM Account WHERE Name LIKE 'Bulk Acme %']) {
			accountIdByName.put(account.Name, account.Id);
		}
		Integer verifiedCount = 0;
		for (Contact contact : [SELECT LastName, AccountId FROM Contact WHERE LastName LIKE 'Bulk Coyote %']) {
			String expectedAccountName = 'Bulk Acme ' + contact.LastName.substringAfter('Bulk Coyote ');
			System.Assert.areEqual(
				accountIdByName.get(expectedAccountName),
				contact.AccountId,
				'Each bulk Contact should be linked to its own paired Account'
			);
			verifiedCount++;
		}
		System.Assert.areEqual(
			200,
			verifiedCount,
			'All 200 bulk Contacts should have been verified'
		);
	}

	@IsTest
	private static void registerNewWithEmptyListShouldNotThrow() {
		UnitOfWork uow = new UnitOfWork();

		Test.startTest();
		uow.registerNew(new List<SObject>());
		uow.commitWork();
		Test.stopTest();

		System.Assert.isTrue(true, 'registerNew should not throw when given an empty list');
	}

	@IsTest
	private static void registerDirtyWithEmptyListShouldNotThrow() {
		UnitOfWork uow = new UnitOfWork();

		Test.startTest();
		uow.registerDirty(new List<SObject>());
		uow.commitWork();
		Test.stopTest();

		System.Assert.isTrue(true, 'registerDirty should not throw when given an empty list');
	}

	@IsTest
	private static void registerDeletedWithEmptyListShouldNotThrow() {
		UnitOfWork uow = new UnitOfWork();

		Test.startTest();
		uow.registerDeleted(new List<SObject>());
		uow.commitWork();
		Test.stopTest();

		System.Assert.isTrue(true, 'registerDeleted should not throw when given an empty list');
	}

	@IsTest
	private static void commitWorkWithNoRegisteredWorkShouldNotConsumeADmlStatement() {
		UnitOfWork uow = new UnitOfWork();
		Integer dmlStatementsBefore = Limits.getDmlStatements();

		Test.startTest();
		uow.commitWork();
		Test.stopTest();

		System.Assert.areEqual(
			dmlStatementsBefore,
			Limits.getDmlStatements(),
			'An empty commit should skip the savepoint, which would otherwise cost a DML statement'
		);
	}

	@IsTest
	private static void registerRelationshipShouldThrowWhenTheRelatedRecordHasNoId() {
		UnitOfWork uow = new UnitOfWork();
		Account neverRegisteredParent = new Account(Name = 'Acme');
		Contact child = new Contact(LastName = 'Coyote');
		uow.registerNew(child);
		uow.registerRelationship(child, Contact.AccountId, neverRegisteredParent);

		Test.startTest();
		Exception caught;
		try {
			uow.commitWork();
		} catch (Exception e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isInstanceOfType(
			caught,
			UnitOfWork.UnitOfWorkException.class,
			'An unresolvable relationship should fail loudly instead of silently leaving the lookup null'
		);
		System.Assert.isTrue(
			caught.getMessage().contains('AccountId'),
			'The message should name the field that could not be populated: ' + caught.getMessage()
		);
		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Contact WHERE LastName = 'Coyote'],
			'The failed commit should have rolled the Contact back'
		);
	}

	@IsTest
	private static void registerRelationshipShouldThrowWhenTheParentIsRegisteredAfterTheChild() {
		UnitOfWork uow = new UnitOfWork();
		Account parent = new Account(Name = 'Acme');
		Contact child = new Contact(LastName = 'Coyote');
		// Registration order decides insert order, so registering the child's type first means the
		// parent has no Id yet when the child is inserted.
		uow.registerNew(child);
		uow.registerNew(parent);
		uow.registerRelationship(child, Contact.AccountId, parent);

		Test.startTest();
		Exception caught;
		try {
			uow.commitWork();
		} catch (Exception e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isInstanceOfType(
			caught,
			UnitOfWork.UnitOfWorkException.class,
			'Registering the parent after the child should fail loudly, not write a null lookup'
		);
	}

	@IsTest
	private static void commitWorkShouldLogASummaryOfWhatWasCommitted() {
		bypassAmbientTriggers();
		insert new LoggerSettings__c(
			SetupOwnerId = UserInfo.getUserId(),
			IsEnabled__c = true,
			LoggingLevel__c = 'FINEST'
		);
		Account existing = new Account(Name = 'Acme');
		insert existing;
		UnitOfWork uow = new UnitOfWork();
		uow.registerNew(new Account(Name = 'New Acme'));
		uow.registerDirty(new Account(Id = existing.Id, Name = 'Updated Acme'));

		Test.startTest();
		uow.commitWork();
		Logger.saveLog();
		Test.stopTest();

		LogEntry__c entry = [
			SELECT Message__c
			FROM LogEntry__c
			WHERE LoggingLevel__c = 'FINE'
			ORDER BY CreatedDate DESC
			LIMIT 1
		];
		System.Assert.isTrue(
			entry.Message__c.contains('1 to insert') &&
			entry.Message__c.contains('1 to update') &&
			entry.Message__c.contains('0 to delete'),
			'The summary log should reflect what was registered: ' + entry.Message__c
		);
	}

	@IsTest
	private static void commitWorkShouldLogAndPersistAnErrorEntryOnFailure() {
		bypassAmbientTriggers();
		UnitOfWork uow = new UnitOfWork();
		uow.registerNew(new Contact(LastName = 'Coyote'));
		uow.registerNew(new Account());

		Test.startTest();
		try {
			uow.commitWork();
			System.Assert.fail('Expected a DmlException');
		} catch (DmlException e) {
			// expected - assertions continue below
		}
		Test.stopTest();

		List<LogEntry__c> errorEntries = [
			SELECT Message__c, ExceptionType__c
			FROM LogEntry__c
			WHERE LoggingLevel__c = 'ERROR'
		];
		System.Assert.areEqual(
			1,
			errorEntries.size(),
			'commitWork should log exactly one ERROR entry on failure'
		);
		System.Assert.isTrue(
			errorEntries[0].Message__c.startsWith('UnitOfWork.commitWork failed'),
			'The error entry should explain that the UnitOfWork commit failed'
		);
		System.Assert.areEqual(
			'System.DmlException',
			errorEntries[0].ExceptionType__c,
			'The error entry should capture the original exception type'
		);
	}
}
