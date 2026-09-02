@IsTest(isParallel=true)
private class TriggerActionUnitOfWorkHandlerTest {
	@IsTest
	private static void finalizeDmlOperationShouldCommitTheCurrentUnitOfWork() {
		UnitOfWork.getCurrent().registerNew(new Account(Name = 'Acme'));
		TriggerActionUnitOfWorkHandler handler = new TriggerActionUnitOfWorkHandler();

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
		TriggerActionUnitOfWorkHandler handler = new TriggerActionUnitOfWorkHandler();

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
		TriggerActionUnitOfWorkHandler.metadataTriggerHandler.triggerNew = new List<SObject>{
			fakeAccount
		};
		TriggerActionUnitOfWorkHandler handler = new TriggerActionUnitOfWorkHandler();

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
}
