/**
 * @description A small mocking utility for Apex tests, built on Salesforce's Stub API.
 *
 * A `Mock` stands in for a real class. It records every method call made against it and does none
 * of the real work - no DML, no queries, no callouts - so a test can check *what the code under
 * test asked for* instead of checking the database afterwards.
 *
 * ```
 * Mock mockUow = Mock.of(UnitOfWork.class);
 * UnitOfWork.current = (UnitOfWork) mockUow.instance();
 *
 * new MyTriggerAction().afterInsert(accounts);
 *
 * mockUow.assertCalledOnce('registerNew');
 * ```
 *
 * Two things worth knowing before you use it:
 *
 * - Method names are matched case-insensitively, and overloads are recorded together, so
 *   `registerNew(SObject)` and `registerNew(List<SObject>)` both count as `registerNew`.
 * - Because the stand-in replaces the whole object, a method that would normally call another
 *   method on itself doesn't - each call is intercepted on its own and the real body never runs.
 *
 * Salesforce's Stub API can't intercept `static` or `private` methods, so only public instance
 * methods are recorded. If you need to mock something reached through a static (such as
 * `UnitOfWork.getCurrent()`), assign the mock to whatever field that static reads from.
 */
@IsTest
public class Mock implements System.StubProvider {
	private final Object stubbedInstance;
	private final List<Invocation> invocations = new List<Invocation>();
	private final Map<String, Object> returnValueByMethodName = new Map<String, Object>();

	private Mock(Type typeToMock) {
		this.stubbedInstance = Test.createStub(typeToMock, this);
	}

	/**
	 * @description Creates a mock stand-in for the given class.
	 * @param typeToMock The class to mock, for example `UnitOfWork.class`.
	 * @return A `Mock` that records every call made against its `instance()`.
	 */
	public static Mock of(Type typeToMock) {
		return new Mock(typeToMock);
	}

	/**
	 * @description The stand-in object to hand to the code under test. Cast it to the mocked type.
	 * @return The stubbed instance.
	 */
	public Object instance() {
		return this.stubbedInstance;
	}

	/**
	 * @description Sets the value returned whenever the named method is called. Methods with no
	 * configured value return null - which is all a void method would do anyway.
	 * @param methodName The method to configure.
	 * @param valueToReturn The value that method should return.
	 * @return This `Mock`, so that calls can be chained.
	 */
	public Mock returns(String methodName, Object valueToReturn) {
		this.returnValueByMethodName.put(methodName.toLowerCase(), valueToReturn);
		return this;
	}

	/**
	 * @description How many times the named method was called.
	 * @param methodName The method to count calls for.
	 * @return The number of recorded calls.
	 */
	public Integer callCount(String methodName) {
		return this.allArgumentsOf(methodName).size();
	}

	/**
	 * @description Whether the named method was called at least once.
	 * @param methodName The method to look for.
	 * @return True if the method was called.
	 */
	public Boolean wasCalled(String methodName) {
		return this.callCount(methodName) > 0;
	}

	/**
	 * @description The arguments passed to the first call of the named method, in order.
	 * @param methodName The method whose arguments you want.
	 * @return The first call's arguments, or an empty list if it was never called.
	 */
	public List<Object> argumentsOf(String methodName) {
		List<List<Object>> everyCall = this.allArgumentsOf(methodName);
		return everyCall.isEmpty() ? new List<Object>() : everyCall[0];
	}

	/**
	 * @description The arguments passed to every call of the named method, one entry per call.
	 * @param methodName The method whose arguments you want.
	 * @return One list of arguments per recorded call, in the order they were called.
	 */
	public List<List<Object>> allArgumentsOf(String methodName) {
		List<List<Object>> matchingCalls = new List<List<Object>>();
		for (Invocation invocation : this.invocations) {
			if (invocation.matches(methodName)) {
				matchingCalls.add(invocation.arguments);
			}
		}
		return matchingCalls;
	}

	/**
	 * @description Asserts the named method was called exactly once.
	 * @param methodName The method that should have been called.
	 */
	public void assertCalledOnce(String methodName) {
		System.Assert.areEqual(
			1,
			this.callCount(methodName),
			methodName + ' should have been called exactly once. ' + this.describeCalls()
		);
	}

	/**
	 * @description Asserts the named method was called the expected number of times.
	 * @param methodName The method that should have been called.
	 * @param expectedCallCount How many times it should have been called.
	 */
	public void assertCalledTimes(String methodName, Integer expectedCallCount) {
		System.Assert.areEqual(
			expectedCallCount,
			this.callCount(methodName),
			methodName + ' was called the wrong number of times. ' + this.describeCalls()
		);
	}

	/**
	 * @description Asserts the named method was never called.
	 * @param methodName The method that should not have been called.
	 */
	public void assertNeverCalled(String methodName) {
		System.Assert.areEqual(
			0,
			this.callCount(methodName),
			methodName + ' should never have been called. ' + this.describeCalls()
		);
	}

	/**
	 * @description Called by the platform every time a method is called on `instance()`. This is
	 * the Stub API's entry point - tests never call it directly.
	 * @param stubbedObject The stand-in object the call was made against.
	 * @param stubbedMethodName The name of the method that was called.
	 * @param returnType The method's return type.
	 * @param listOfParamTypes The types of the method's parameters.
	 * @param listOfParamNames The names of the method's parameters.
	 * @param listOfArgs The arguments the method was called with.
	 * @return The value configured through `returns`, or null if none was configured.
	 */
	public Object handleMethodCall(
		Object stubbedObject,
		String stubbedMethodName,
		Type returnType,
		List<Type> listOfParamTypes,
		List<String> listOfParamNames,
		List<Object> listOfArgs
	) {
		this.invocations.add(new Invocation(stubbedMethodName, listOfArgs));
		return this.returnValueByMethodName.get(stubbedMethodName.toLowerCase());
	}

	private String describeCalls() {
		if (this.invocations.isEmpty()) {
			return 'No methods were called on this mock.';
		}
		List<String> calledMethodNames = new List<String>();
		for (Invocation invocation : this.invocations) {
			calledMethodNames.add(invocation.methodName);
		}
		return 'Calls recorded: ' + String.join(calledMethodNames, ', ');
	}

	private class Invocation {
		private final String methodName;
		private final List<Object> arguments;

		private Invocation(String methodName, List<Object> arguments) {
			this.methodName = methodName;
			this.arguments = arguments == null ? new List<Object>() : arguments;
		}

		private Boolean matches(String otherMethodName) {
			return this.methodName.equalsIgnoreCase(otherMethodName);
		}
	}
}
