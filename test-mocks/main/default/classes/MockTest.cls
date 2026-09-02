@IsTest(isParallel=true)
private class MockTest {
	@IsTest
	private static void instanceShouldBeUsableAsTheMockedType() {
		Mock mock = Mock.of(UnitOfWork.class);

		Object instance = mock.instance();

		System.Assert.isInstanceOfType(
			instance,
			UnitOfWork.class,
			'The stand-in should be usable anywhere the real class is'
		);
	}

	@IsTest
	private static void shouldRecordThatAMethodWasCalled() {
		Mock mock = Mock.of(UnitOfWork.class);
		UnitOfWork mockedUnitOfWork = (UnitOfWork) mock.instance();

		mockedUnitOfWork.registerNew(new Account(Name = 'Acme'));

		System.Assert.isTrue(mock.wasCalled('registerNew'), 'registerNew should have been recorded');
		System.Assert.areEqual(1, mock.callCount('registerNew'), 'registerNew was called once');
	}

	@IsTest
	private static void shouldMatchMethodNamesCaseInsensitively() {
		Mock mock = Mock.of(UnitOfWork.class);
		UnitOfWork mockedUnitOfWork = (UnitOfWork) mock.instance();

		mockedUnitOfWork.registerNew(new Account(Name = 'Acme'));

		System.Assert.isTrue(
			mock.wasCalled('REGISTERNEW'),
			'Method names should match regardless of casing, as they do in Apex itself'
		);
	}

	@IsTest
	private static void shouldRecordOverloadsOfTheSameMethodTogether() {
		Mock mock = Mock.of(UnitOfWork.class);
		UnitOfWork mockedUnitOfWork = (UnitOfWork) mock.instance();

		mockedUnitOfWork.registerNew(new Account(Name = 'Acme'));
		mockedUnitOfWork.registerNew(new List<SObject>{ new Contact(LastName = 'Coyote') });

		System.Assert.areEqual(
			2,
			mock.callCount('registerNew'),
			'Both overloads of registerNew should be counted together'
		);
	}

	@IsTest
	private static void shouldCaptureTheArgumentsOfTheFirstCall() {
		Mock mock = Mock.of(UnitOfWork.class);
		UnitOfWork mockedUnitOfWork = (UnitOfWork) mock.instance();
		Account account = new Account(Name = 'Acme');

		mockedUnitOfWork.registerNew(account);

		List<Object> arguments = mock.argumentsOf('registerNew');
		System.Assert.areEqual(1, arguments.size(), 'registerNew takes a single argument');
		System.Assert.areEqual(account, arguments[0], 'The registered record should be captured');
	}

	@IsTest
	private static void shouldCaptureTheArgumentsOfEveryCall() {
		Mock mock = Mock.of(UnitOfWork.class);
		UnitOfWork mockedUnitOfWork = (UnitOfWork) mock.instance();

		mockedUnitOfWork.registerNew(new Account(Name = 'First'));
		mockedUnitOfWork.registerNew(new Account(Name = 'Second'));

		List<List<Object>> everyCall = mock.allArgumentsOf('registerNew');
		System.Assert.areEqual(2, everyCall.size(), 'Both calls should have been recorded');
		System.Assert.areEqual(
			'First',
			((Account) everyCall[0][0]).Name,
			'Calls should be recorded in the order they were made'
		);
		System.Assert.areEqual(
			'Second',
			((Account) everyCall[1][0]).Name,
			'Calls should be recorded in the order they were made'
		);
	}

	@IsTest
	private static void argumentsOfAMethodThatWasNeverCalledShouldBeEmpty() {
		Mock mock = Mock.of(UnitOfWork.class);

		System.Assert.isTrue(
			mock.argumentsOf('registerNew').isEmpty(),
			'A method that was never called has no arguments to report'
		);
		System.Assert.areEqual(0, mock.callCount('registerNew'), 'Nothing was called');
		System.Assert.isFalse(mock.wasCalled('registerNew'), 'Nothing was called');
	}

	@IsTest
	private static void shouldReturnTheConfiguredValue() {
		Mock mock = Mock.of(UnitOfWork.class);
		mock.returns('commitWork', 'a configured value');

		Object returnedValue = mock.handleMethodCall(
			mock.instance(),
			'commitWork',
			String.class,
			new List<Type>(),
			new List<String>(),
			new List<Object>()
		);

		System.Assert.areEqual(
			'a configured value',
			returnedValue,
			'The value configured through returns should be handed back to the caller'
		);
	}

	@IsTest
	private static void shouldReturnNullWhenNoValueIsConfigured() {
		Mock mock = Mock.of(UnitOfWork.class);

		Object returnedValue = mock.handleMethodCall(
			mock.instance(),
			'commitWork',
			String.class,
			new List<Type>(),
			new List<String>(),
			new List<Object>()
		);

		System.Assert.isNull(returnedValue, 'An unconfigured method returns null');
	}

	@IsTest
	private static void shouldRecordCallsMadeWithNoArguments() {
		Mock mock = Mock.of(UnitOfWork.class);
		UnitOfWork mockedUnitOfWork = (UnitOfWork) mock.instance();

		mockedUnitOfWork.commitWork();

		System.Assert.isTrue(mock.wasCalled('commitWork'), 'commitWork should have been recorded');
		System.Assert.isTrue(
			mock.argumentsOf('commitWork').isEmpty(),
			'commitWork takes no arguments'
		);
	}

	@IsTest
	private static void mockedMethodsShouldNotRunTheRealBody() {
		Mock mock = Mock.of(UnitOfWork.class);
		UnitOfWork mockedUnitOfWork = (UnitOfWork) mock.instance();

		mockedUnitOfWork.registerNew(new Account(Name = 'Acme'));
		mockedUnitOfWork.commitWork();

		System.Assert.areEqual(
			0,
			[SELECT COUNT() FROM Account],
			'A mocked UnitOfWork should never perform real DML'
		);
	}

	@IsTest
	private static void theAssertionHelpersShouldPassWhenTheCallsMatch() {
		Mock mock = Mock.of(UnitOfWork.class);
		UnitOfWork mockedUnitOfWork = (UnitOfWork) mock.instance();

		mockedUnitOfWork.registerNew(new Account(Name = 'Acme'));

		mock.assertCalledOnce('registerNew');
		mock.assertCalledTimes('registerNew', 1);
		mock.assertNeverCalled('registerDirty');
	}

	// The failing side of the assertion helpers isn't covered here on purpose: Apex's
	// System.AssertException can't be caught, so a test can't observe a failed assertion without
	// failing itself.
	@IsTest
	private static void theAssertionHelpersShouldPassOnAMockThatWasNeverUsed() {
		Mock mock = Mock.of(UnitOfWork.class);

		mock.assertNeverCalled('registerNew');
		mock.assertCalledTimes('registerNew', 0);
	}
}
