@IsTest(isParallel=true)
private class RecordSecurityTest {
	/**
	 * Bypasses TriggerBase-based automation on Account and Contact for the calling test method, so
	 * that these tests behave the same in an org that has its own automation on those objects - as
	 * this repo's own `example` package installs. A static bypass set in @TestSetup does not survive
	 * into @IsTest methods, so this has to be called from inside each method that performs DML.
	 */
	private static void bypassAmbientTriggers() {
		TriggerBase.bypass('Account');
		TriggerBase.bypass('Contact');
	}

	/**
	 * Builds a well-formed Account Id that no record has, which the platform reports no access row
	 * for. That is the same answer it gives for a record the user genuinely cannot see, so it is a
	 * dependable "no access" case that needs no second user and no sharing rules.
	 * @param suffix Makes each generated Id distinct.
	 * @return An Account Id that matches no record.
	 */
	private static Id unreachableRecordId(Integer suffix) {
		return Id.valueOf(
			Account.SObjectType.getDescribe().getKeyPrefix() + String.valueOf(suffix).leftPad(12, '0')
		);
	}

	@IsTest
	private static void getInstanceShouldReturnTheSameInstanceEveryTime() {
		System.Assert.areEqual(
			RecordSecurity.getInstance(),
			RecordSecurity.getInstance(),
			'getInstance should hand back one shared instance'
		);
	}

	@IsTest
	private static void getInstanceShouldReturnWhateverWasInstalledInItsPlace() {
		// This is the seam `Mock.of(RecordSecurity.class)` uses. Asserting it with a plain instance
		// keeps this package free of any dependency on the test-mocks package.
		RecordSecurity replacement = new RecordSecurity();
		RecordSecurity.instance = replacement;

		System.Assert.areEqual(
			replacement,
			RecordSecurity.getInstance(),
			'A test should be able to put its own instance in place of the shared one'
		);
	}

	@IsTest
	private static void everyKindOfAccessShouldBeAllowedForARecordTheUserOwns() {
		bypassAmbientTriggers();
		Account account = new Account(Name = 'Acme');
		insert account;
		RecordSecurity security = RecordSecurity.getInstance();

		Test.startTest();
		Boolean canRead = security.canRead(account.Id);
		Boolean canEdit = security.canEdit(account.Id);
		Boolean canDelete = security.canDelete(account.Id);
		Boolean canTransfer = security.canTransfer(account.Id);
		Test.stopTest();

		System.Assert.isTrue(canRead, 'The owner should be able to see their own record');
		System.Assert.isTrue(canEdit, 'The owner should be able to edit their own record');
		System.Assert.isTrue(canDelete, 'The owner should be able to delete their own record');
		System.Assert.isTrue(canTransfer, 'The owner should be able to transfer their own record');
	}

	@IsTest
	private static void everyKindOfAccessShouldBeDeniedForAnUnreachableRecord() {
		Id unreachableId = unreachableRecordId(1);
		RecordSecurity security = RecordSecurity.getInstance();

		Test.startTest();
		Boolean canRead = security.canRead(unreachableId);
		Boolean canEdit = security.canEdit(unreachableId);
		Boolean canDelete = security.canDelete(unreachableId);
		Boolean canTransfer = security.canTransfer(unreachableId);
		Test.stopTest();

		System.Assert.isFalse(canRead, 'A record with no access row should not be readable');
		System.Assert.isFalse(canEdit, 'A record with no access row should not be editable');
		System.Assert.isFalse(canDelete, 'A record with no access row should not be deletable');
		System.Assert.isFalse(canTransfer, 'A record with no access row should not be transferable');
	}

	@IsTest
	private static void bulkMethodsShouldReturnOnlyTheRecordsTheUserCanTouch() {
		bypassAmbientTriggers();
		Account account = new Account(Name = 'Acme');
		insert account;
		Set<Id> recordIds = new Set<Id>{ account.Id, unreachableRecordId(1) };
		RecordSecurity security = RecordSecurity.getInstance();

		Test.startTest();
		Set<Id> readable = security.readableIds(recordIds);
		Set<Id> editable = security.editableIds(recordIds);
		Set<Id> deletable = security.deletableIds(recordIds);
		Set<Id> transferable = security.transferableIds(recordIds);
		Test.stopTest();

		System.Assert.areEqual(
			new Set<Id>{ account.Id },
			readable,
			'Only the record that exists should come back as readable'
		);
		System.Assert.areEqual(new Set<Id>{ account.Id }, editable, 'Same for editable');
		System.Assert.areEqual(new Set<Id>{ account.Id }, deletable, 'Same for deletable');
		System.Assert.areEqual(new Set<Id>{ account.Id }, transferable, 'Same for transferable');
	}

	@IsTest
	private static void anEmptySetShouldReturnAnEmptyResultWithoutQuerying() {
		Integer queriesBefore = Limits.getQueries();

		Set<Id> readable = RecordSecurity.getInstance().readableIds(new Set<Id>());

		System.Assert.isTrue(readable.isEmpty(), 'Nothing was asked about, so nothing is allowed');
		System.Assert.areEqual(
			queriesBefore,
			Limits.getQueries(),
			'Asking about no records should not cost a query'
		);
	}

	@IsTest
	private static void aNullSetShouldReturnAnEmptyResultWithoutQuerying() {
		Integer queriesBefore = Limits.getQueries();

		Set<Id> readable = RecordSecurity.getInstance().readableIds(null);

		System.Assert.isTrue(readable.isEmpty(), 'A null set should be treated as no records');
		System.Assert.areEqual(
			queriesBefore,
			Limits.getQueries(),
			'Asking about no records should not cost a query'
		);
	}

	@IsTest
	private static void moreRecordsThanOneQueryAllowsShouldBeSplitAcrossQueries() {
		Set<Id> recordIds = new Set<Id>();
		for (Integer i = 1; i <= RecordSecurity.MAX_IDS_PER_QUERY + 50; i++) {
			recordIds.add(unreachableRecordId(i));
		}
		// Deliberately no Test.startTest()/stopTest() here: they reset the governor counters and then
		// restore them, which would leave this delta reading zero however many queries actually ran.
		Integer queriesBefore = Limits.getQueries();

		Set<Id> readable = RecordSecurity.getInstance().readableIds(recordIds);

		System.Assert.isTrue(readable.isEmpty(), 'None of these records exist');
		System.Assert.areEqual(
			2,
			Limits.getQueries() - queriesBefore,
			'250 records should be answered in two queries, since UserRecordAccess answers for at most 200 at a time'
		);
	}

	@IsTest
	private static void checkMethodsShouldNotThrowWhenAccessIsAllowed() {
		bypassAmbientTriggers();
		Account account = new Account(Name = 'Acme');
		insert account;
		RecordSecurity security = RecordSecurity.getInstance();

		Test.startTest();
		security.checkRead(account.Id);
		security.checkEdit(account.Id);
		security.checkDelete(account.Id);
		security.checkTransfer(account.Id);
		security.checkRead(new Set<Id>{ account.Id });
		security.checkEdit(new Set<Id>{ account.Id });
		security.checkDelete(new Set<Id>{ account.Id });
		security.checkTransfer(new Set<Id>{ account.Id });
		Test.stopTest();

		System.Assert.isTrue(true, 'Allowed access should pass silently');
	}

	@IsTest
	private static void checkShouldThrowAndNameTheRecordThatFailed() {
		Id unreachableId = unreachableRecordId(1);

		Test.startTest();
		Exception caught;
		try {
			RecordSecurity.getInstance().checkRead(unreachableId);
		} catch (RecordSecurity.RecordSecurityException e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(caught, 'Missing record access should throw');
		System.Assert.isTrue(
			caught.getMessage().contains(String.valueOf(unreachableId)),
			'The message should name the record that failed: ' + caught.getMessage()
		);
	}

	@IsTest
	private static void everyCheckMethodShouldThrowWhenAccessIsMissing() {
		Set<Id> unreachableIds = new Set<Id>{ unreachableRecordId(1) };
		RecordSecurity security = RecordSecurity.getInstance();
		Integer thrownCount = 0;

		Test.startTest();
		try {
			security.checkEdit(unreachableIds);
		} catch (RecordSecurity.RecordSecurityException e) {
			thrownCount++;
		}
		try {
			security.checkDelete(unreachableIds);
		} catch (RecordSecurity.RecordSecurityException e) {
			thrownCount++;
		}
		try {
			security.checkTransfer(unreachableIds);
		} catch (RecordSecurity.RecordSecurityException e) {
			thrownCount++;
		}
		Test.stopTest();

		System.Assert.areEqual(
			3,
			thrownCount,
			'Edit, delete, and transfer should each throw when the record is unreachable'
		);
	}

	@IsTest
	private static void checkingNoRecordsShouldNotThrow() {
		RecordSecurity security = RecordSecurity.getInstance();

		Test.startTest();
		security.checkRead(new Set<Id>());
		security.checkRead((Set<Id>) null);
		Test.stopTest();

		System.Assert.isTrue(true, 'Asking about no records should pass rather than throw');
	}
}
