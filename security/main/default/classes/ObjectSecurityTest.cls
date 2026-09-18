@IsTest(isParallel=true)
private class ObjectSecurityTest {
	/**
	 * A field no user can ever write, in any org, whatever their profile says - Salesforce maintains
	 * it. That makes it a dependable stand-in for "a field this user has no create or update access
	 * to", without needing a restricted user and a permission set to produce one.
	 */
	private static final Schema.SObjectField UNWRITABLE_FIELD = Account.IsDeleted;

	/**
	 * An object no user can ever create, update, or delete through DML - the platform writes it.
	 * Same idea as `UNWRITABLE_FIELD`, one level up.
	 */
	private static final Schema.SObjectType UNWRITABLE_OBJECT = AsyncApexJob.SObjectType;

	@IsTest
	private static void getInstanceShouldReturnTheSameInstanceEveryTime() {
		System.Assert.areEqual(
			ObjectSecurity.getInstance(),
			ObjectSecurity.getInstance(),
			'getInstance should hand back one shared instance'
		);
	}

	@IsTest
	private static void getInstanceShouldReturnWhateverWasInstalledInItsPlace() {
		// This is the seam `Mock.of(ObjectSecurity.class)` uses. Asserting it with a plain instance
		// keeps this package free of any dependency on the test-mocks package.
		ObjectSecurity replacement = new ObjectSecurity();
		ObjectSecurity.instance = replacement;

		System.Assert.areEqual(
			replacement,
			ObjectSecurity.getInstance(),
			'A test should be able to put its own instance in place of the shared one'
		);
	}

	@IsTest
	private static void objectChecksShouldPassForAnObjectTheUserFullyControls() {
		ObjectSecurity security = ObjectSecurity.getInstance();

		System.Assert.isTrue(
			security.canCreate(Account.SObjectType),
			'The user running these tests should be able to create Accounts'
		);
		System.Assert.isTrue(
			security.canRead(Account.SObjectType),
			'The user running these tests should be able to read Accounts'
		);
		System.Assert.isTrue(
			security.canUpdate(Account.SObjectType),
			'The user running these tests should be able to update Accounts'
		);
		System.Assert.isTrue(
			security.canDelete(Account.SObjectType),
			'The user running these tests should be able to delete Accounts'
		);
	}

	@IsTest
	private static void objectChecksShouldFailForAnObjectNobodyCanWrite() {
		ObjectSecurity security = ObjectSecurity.getInstance();

		System.Assert.isFalse(
			security.canCreate(UNWRITABLE_OBJECT),
			'No user can create ' + UNWRITABLE_OBJECT + ' records'
		);
		System.Assert.isFalse(
			security.canUpdate(UNWRITABLE_OBJECT),
			'No user can update ' + UNWRITABLE_OBJECT + ' records'
		);
		System.Assert.isFalse(
			security.canDelete(UNWRITABLE_OBJECT),
			'No user can delete ' + UNWRITABLE_OBJECT + ' records'
		);
	}

	@IsTest
	private static void fieldChecksShouldPassForFieldsTheUserCanWrite() {
		System.Assert.isTrue(
			ObjectSecurity.getInstance()
				.canCreate(
					Account.SObjectType,
					new List<Schema.SObjectField>{ Account.Name, Account.Industry }
				),
			'The user running these tests should be able to populate Name and Industry'
		);
	}

	@IsTest
	private static void fieldChecksShouldFailForAFieldTheUserCannotWrite() {
		ObjectSecurity security = ObjectSecurity.getInstance();
		List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
			Account.Name,
			UNWRITABLE_FIELD
		};

		System.Assert.isFalse(
			security.canCreate(Account.SObjectType, fields),
			'One unwritable field should fail the whole create check'
		);
		System.Assert.isFalse(
			security.canUpdate(Account.SObjectType, fields),
			'One unwritable field should fail the whole update check'
		);
	}

	@IsTest
	private static void readingAFieldShouldBeAllowedEvenWhenWritingItIsNot() {
		System.Assert.isTrue(
			ObjectSecurity.getInstance()
				.canRead(Account.SObjectType, new List<Schema.SObjectField>{ UNWRITABLE_FIELD }),
			'A field that cannot be written can still be readable - the operations are checked separately'
		);
	}

	@IsTest
	private static void anEmptyFieldListShouldCheckOnlyTheObject() {
		ObjectSecurity security = ObjectSecurity.getInstance();

		System.Assert.isTrue(
			security.canCreate(Account.SObjectType, new List<Schema.SObjectField>()),
			'With no fields to check, the object permission is the whole answer'
		);
		System.Assert.isFalse(
			security.canCreate(UNWRITABLE_OBJECT, new List<Schema.SObjectField>()),
			'With no fields to check, a failing object permission is still the whole answer'
		);
	}

	@IsTest
	private static void fieldApiNamesShouldBeCheckedLikeFieldTokens() {
		ObjectSecurity security = ObjectSecurity.getInstance();

		System.Assert.isTrue(
			security.canCreate(Account.SObjectType, new List<String>{ 'Name', 'Industry' }),
			'API names should resolve to the same answer as the matching tokens'
		);
		System.Assert.isFalse(
			security.canCreate(Account.SObjectType, new List<String>{ String.valueOf(UNWRITABLE_FIELD) }),
			'An unwritable field should fail whether it is named or passed as a token'
		);
		System.Assert.isTrue(
			security.canUpdate(Account.SObjectType, new List<String>{ 'Industry' }),
			'Updating should accept API names the same way creating does'
		);
		System.Assert.isFalse(
			security.canUpdate(Account.SObjectType, new List<String>{ String.valueOf(UNWRITABLE_FIELD) }),
			'An unwritable field named by API name should fail the update check too'
		);
	}

	@IsTest
	private static void fieldApiNamesShouldBeMatchedCaseInsensitively() {
		System.Assert.isTrue(
			ObjectSecurity.getInstance()
				.canRead(Account.SObjectType, new List<String>{ 'nAmE', 'INDUSTRY' }),
			'Field names should match however configuration happens to have cased them'
		);
	}

	@IsTest
	private static void anUnknownFieldApiNameShouldThrow() {
		Test.startTest();
		Exception caught;
		try {
			ObjectSecurity.getInstance()
				.canRead(Account.SObjectType, new List<String>{ 'NotARealField__c' });
		} catch (ObjectSecurity.ObjectSecurityException e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(
			caught,
			'A misspelled field name should fail loudly rather than look like a passing check'
		);
		System.Assert.isTrue(
			caught.getMessage().contains('NotARealField__c'),
			'The message should name the field that could not be found: ' + caught.getMessage()
		);
	}

	@IsTest
	private static void checkMethodsShouldNotThrowWhenAccessIsAllowed() {
		ObjectSecurity security = ObjectSecurity.getInstance();

		Test.startTest();
		security.checkCreate(Account.SObjectType);
		security.checkRead(Account.SObjectType);
		security.checkUpdate(Account.SObjectType);
		security.checkDelete(Account.SObjectType);
		security.checkCreate(Account.SObjectType, new List<Schema.SObjectField>{ Account.Name });
		security.checkRead(Account.SObjectType, new List<String>{ 'Name' });
		security.checkUpdate(Account.SObjectType, new List<Schema.SObjectField>{ Account.Name });
		security.checkCreate(Account.SObjectType, new List<String>{ 'Name' });
		security.checkRead(Account.SObjectType, new List<Schema.SObjectField>{ Account.Name });
		security.checkUpdate(Account.SObjectType, new List<String>{ 'Name' });
		Test.stopTest();

		System.Assert.isTrue(true, 'Allowed access should pass silently');
	}

	@IsTest
	private static void checkShouldThrowAndNameTheObjectWhenTheObjectFails() {
		Test.startTest();
		Exception caught;
		try {
			ObjectSecurity.getInstance().checkCreate(UNWRITABLE_OBJECT);
		} catch (ObjectSecurity.ObjectSecurityException e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(caught, 'Missing object permission should throw');
		System.Assert.isTrue(
			caught.getMessage().contains(String.valueOf(UNWRITABLE_OBJECT)) &&
			caught.getMessage().contains('create'),
			'The message should name the object and the operation: ' + caught.getMessage()
		);
	}

	@IsTest
	private static void checkShouldThrowAndNameTheFieldWhenAFieldFails() {
		Test.startTest();
		Exception caught;
		try {
			ObjectSecurity.getInstance()
				.checkUpdate(
					Account.SObjectType,
					new List<Schema.SObjectField>{ Account.Name, UNWRITABLE_FIELD }
				);
		} catch (ObjectSecurity.ObjectSecurityException e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(caught, 'Missing field-level security should throw');
		System.Assert.isTrue(
			caught.getMessage().contains(String.valueOf(UNWRITABLE_FIELD)),
			'The message should name the field that failed, not just the object: ' + caught.getMessage()
		);
	}

	@IsTest
	private static void checkDeleteShouldThrowForAnObjectNobodyCanDelete() {
		Test.startTest();
		Exception caught;
		try {
			ObjectSecurity.getInstance().checkDelete(UNWRITABLE_OBJECT);
		} catch (ObjectSecurity.ObjectSecurityException e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(caught, 'Missing delete permission should throw');
		System.Assert.isTrue(
			caught.getMessage().contains('delete'),
			'The message should name the operation: ' + caught.getMessage()
		);
	}
}
