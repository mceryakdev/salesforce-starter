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
}
