/**
 * @description Tests that `AccountTrigger` runs the correct handler - nothing about what any
 * individual Trigger Action decides to do.
 *
 * That's a narrower job than it sounds. `UOWMetadataTriggerHandler`'s one distinguishing behavior,
 * versus the framework's stock `MetadataTriggerHandler`, is committing the Unit of Work at the true
 * end of the run - so `UnitOfWork.commitCurrent()` firing is proof that *this* handler is the one
 * wired into the trigger, regardless of which Trigger Actions are configured for Account or what
 * they do. `MockUnitOfWork.wasCommitted()` reads that signal directly, with no DML beyond the one
 * `insert` needed to fire the trigger in the first place, and no need to inspect any record the
 * configured actions might have touched.
 *
 * What actually happens inside `SetDefaultAccountRating` and `CreateOnboardingRecords` - including
 * proving that inserting an Account creates the records `CreateOnboardingRecords` registers - is
 * covered by their own mocked unit tests (`SetDefaultAccountRatingTest`,
 * `CreateOnboardingRecordsTest`). Testing it again here would just make it unclear which test to
 * fix when something breaks.
 */
@IsTest(isParallel=true)
private class AccountTriggerTest {
	@IsTest
	private static void insertShouldRunTheHandlerThatCommitsTheUnitOfWork() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();

		Test.startTest();
		insert new Account(Name = 'Acme');
		Test.stopTest();

		System.Assert.isTrue(
			mockUow.wasCommitted(),
			'AccountTrigger should run UOWMetadataTriggerHandler, which commits the Unit of Work at the end of the run'
		);
	}

	@IsTest
	private static void bypassingTheObjectShouldPreventTheHandlerFromRunningAtAll() {
		MockUnitOfWork mockUow = MockUnitOfWork.install();
		TriggerBase.bypass('Account');

		Test.startTest();
		insert new Account(Name = 'Acme');
		Test.stopTest();
		TriggerBase.clearBypass('Account');

		System.Assert.isFalse(
			mockUow.wasCommitted(),
			'A bypassed object should never reach finalizeDmlOperation, so the Unit of Work should never be committed'
		);
	}
}
