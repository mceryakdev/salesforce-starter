@IsTest(isParallel=true)
private class UOWMetadataTriggerHandlerTest {
	@IsTest
	private static void finalizeDmlOperationShouldCommitTheCurrentUnitOfWork() {
		UnitOfWork.getCurrent().registerNew(new Account(Name = 'Acme'));
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();

		Test.startTest();
		handler.finalizeDmlOperation();
		Test.stopTest();

		System.Assert.areEqual(
			1,
			[SELECT COUNT() FROM Account WHERE Name = 'Acme'],
			'finalizeDmlOperation should commit work registered on the current UnitOfWork'
		);
	}

	@IsTest
	private static void finalizeDmlOperationShouldNotThrowWhenNoWorkIsRegistered() {
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();

		Test.startTest();
		handler.finalizeDmlOperation();
		Test.stopTest();

		System.Assert.isTrue(
			true,
			'finalizeDmlOperation should not throw when nothing was registered'
		);
	}

	@IsTest
	private static void everyTriggerContextShouldDelegateToMetadataTriggerHandlerWithoutError() {
		Account fakeAccount = new Account(Name = 'Acme');
		UOWMetadataTriggerHandler.metadataTriggerHandler.triggerNew = new List<SObject>{
			fakeAccount
		};
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();

		Test.startTest();
		handler.beforeInsert(new List<SObject>{ fakeAccount });
		handler.afterInsert(new List<SObject>{ fakeAccount });
		handler.beforeUpdate(
			new List<SObject>{ fakeAccount },
			new List<SObject>{ fakeAccount }
		);
		handler.afterUpdate(
			new List<SObject>{ fakeAccount },
			new List<SObject>{ fakeAccount }
		);
		handler.beforeDelete(new List<SObject>{ fakeAccount });
		handler.afterDelete(new List<SObject>{ fakeAccount });
		handler.afterUndelete(new List<SObject>{ fakeAccount });
		Test.stopTest();

		System.Assert.isTrue(
			true,
			'Every Trigger Action context should delegate to MetadataTriggerHandler without throwing'
		);
	}

	@IsTest
	private static void finalizeDmlOperationShouldCommitALargeNumberOfRegisteredRecords() {
		for (Integer i = 0; i < 200; i++) {
			UnitOfWork.getCurrent().registerNew(new Account(Name = 'Bulk Acme ' + i));
		}
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();

		Test.startTest();
		handler.finalizeDmlOperation();
		Test.stopTest();

		System.Assert.areEqual(
			200,
			[SELECT COUNT() FROM Account WHERE Name LIKE 'Bulk Acme %'],
			'finalizeDmlOperation should commit all 200 records registered on the current UnitOfWork'
		);
	}

	@IsTest
	private static void finalizeDmlOperationShouldLogAndRethrowWhenAFinalizerFails() {
		UOWMetadataTriggerHandler.finalizerHandler = new ThrowingFinalizerHandler();
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();

		Test.startTest();
		Exception caught;
		try {
			handler.finalizeDmlOperation();
		} catch (Exception e) {
			caught = e;
		}
		Test.stopTest();

		System.Assert.isNotNull(
			caught,
			'finalizeDmlOperation should rethrow a failing finalizer\'s exception'
		);
		List<LogEntry__c> errorEntries = [
			SELECT Message__c
			FROM LogEntry__c
			WHERE LoggingLevel__c = 'ERROR'
		];
		System.Assert.areEqual(
			1,
			errorEntries.size(),
			'A failing finalizer should log exactly one ERROR entry'
		);
		System.Assert.isTrue(
			errorEntries[0].Message__c.startsWith('DmlFinalizer execution failed'),
			'The error entry should explain that a DmlFinalizer failed'
		);
	}

	@IsTest
	private static void finalizeDmlOperationShouldNotRunFinalizersWhenCommitFails() {
		UnitOfWork.getCurrent().registerNew(new Account());
		SpyFinalizerHandler spy = new SpyFinalizerHandler();
		UOWMetadataTriggerHandler.finalizerHandler = spy;
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();

		Test.startTest();
		try {
			handler.finalizeDmlOperation();
			System.Assert.fail('Expected a DmlException from the invalid Account');
		} catch (DmlException e) {
			// expected - assertion continues below
		}
		Test.stopTest();

		System.Assert.isFalse(
			spy.wasCalled,
			'Finalizers should not run when committing the UnitOfWork fails'
		);
	}

	@IsTest
	private static void describeTriggerContextShouldReturnPlaceholderOutsideOfTriggerContext() {
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();

		System.Assert.areEqual(
			'no trigger context',
			handler.describeTriggerContext(),
			'Outside of a trigger, there is no sObject or context to describe'
		);
	}

	@IsTest
	private static void describeTriggerContextShouldDescribeSObjectAndContextFromTriggerNew() {
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();
		handler.triggerNew = new List<SObject>{ new Account(Name = 'Acme') };
		handler.context = System.TriggerOperation.AFTER_INSERT;

		System.Assert.areEqual(
			'Account (AFTER_INSERT)',
			handler.describeTriggerContext(),
			'The description should include the sObject type and trigger operation from triggerNew'
		);
	}

	@IsTest
	private static void describeTriggerContextShouldDescribeSObjectAndContextFromTriggerOldWhenTriggerNewIsNull() {
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();
		handler.triggerOld = new List<SObject>{ new Account(Name = 'Acme') };
		handler.context = System.TriggerOperation.BEFORE_DELETE;

		System.Assert.areEqual(
			'Account (BEFORE_DELETE)',
			handler.describeTriggerContext(),
			'The description should fall back to triggerOld when triggerNew is null'
		);
	}

	@IsTest
	private static void describeTriggerContextShouldReturnPlaceholderWhenTriggerNewIsEmptyAndTriggerOldIsNull() {
		UOWMetadataTriggerHandler handler = new UOWMetadataTriggerHandler();
		handler.triggerNew = new List<SObject>();

		System.Assert.areEqual(
			'no trigger context',
			handler.describeTriggerContext(),
			'An empty triggerNew with a null triggerOld mirrors the same case sObjectType would fail on'
		);
	}

	private class ThrowingFinalizerHandler extends FinalizerHandler {
		public override void handleDynamicFinalizers() {
			throw new System.DmlException('Simulated finalizer failure');
		}
	}

	private class SpyFinalizerHandler extends FinalizerHandler {
		public Boolean wasCalled = false;
		public override void handleDynamicFinalizers() {
			this.wasCalled = true;
		}
	}
}
