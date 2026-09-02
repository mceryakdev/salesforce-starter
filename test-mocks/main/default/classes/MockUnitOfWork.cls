/**
 * @description A `UnitOfWork` stand-in for tests, so that code which registers work can be tested
 * without any DML actually running.
 *
 * Most Trigger Actions reach the Unit of Work through `UnitOfWork.getCurrent()`. `install()` puts
 * a mock in place as that ambient instance, so the code under test picks it up with no changes:
 *
 * ```
 * MockUnitOfWork mockUow = MockUnitOfWork.install();
 *
 * new CreateFollowUpTask().afterInsert(accounts);
 *
 * System.Assert.areEqual(1, mockUow.registeredNew().size());
 * ```
 *
 * Use `create()` instead when the code under test takes a `UnitOfWork` directly, and hand it
 * `instance()`.
 *
 * This is a thin, typed wrapper over `Mock` - it exists so that tests read in terms of the Unit of
 * Work (`registeredNew()`) rather than in terms of method-name strings. For anything it doesn't
 * cover, `calls()` returns the underlying `Mock`.
 */
@IsTest
public class MockUnitOfWork {
	private final Mock callRecorder;

	private MockUnitOfWork() {
		this.callRecorder = Mock.of(UnitOfWork.class);
	}

	/**
	 * @description Creates a mock `UnitOfWork` without installing it anywhere. Hand `instance()`
	 * to the code under test.
	 * @return The new `MockUnitOfWork`.
	 */
	public static MockUnitOfWork create() {
		return new MockUnitOfWork();
	}

	/**
	 * @description Creates a mock `UnitOfWork` and installs it as the ambient instance, so that
	 * `UnitOfWork.getCurrent()` returns it for the rest of the test.
	 * @return The new `MockUnitOfWork`.
	 */
	public static MockUnitOfWork install() {
		MockUnitOfWork mockUnitOfWork = new MockUnitOfWork();
		UnitOfWork.current = mockUnitOfWork.instance();
		return mockUnitOfWork;
	}

	/**
	 * @description The stand-in `UnitOfWork` to hand to the code under test.
	 * @return The mocked `UnitOfWork`.
	 */
	public UnitOfWork instance() {
		return (UnitOfWork) this.callRecorder.instance();
	}

	/**
	 * @description Every record passed to `registerNew`, across all calls and both overloads.
	 * @return The records registered for insert.
	 */
	public List<SObject> registeredNew() {
		return this.recordsPassedTo('registerNew');
	}

	/**
	 * @description Every record passed to `registerDirty`, across all calls and both overloads.
	 * @return The records registered for update.
	 */
	public List<SObject> registeredDirty() {
		return this.recordsPassedTo('registerDirty');
	}

	/**
	 * @description Every record passed to `registerDeleted`, across all calls and both overloads.
	 * @return The records registered for delete.
	 */
	public List<SObject> registeredDeleted() {
		return this.recordsPassedTo('registerDeleted');
	}

	/**
	 * @description Whether the work was committed - by `commitWork()` directly, or by
	 * `UnitOfWork.commitCurrent()`.
	 * @return True if the work was committed.
	 */
	public Boolean wasCommitted() {
		return this.callRecorder.wasCalled('commitWork');
	}

	/**
	 * @description The underlying generic mock, for anything this wrapper doesn't cover - call
	 * counts, `registerRelationship` arguments, and so on.
	 * @return The `Mock` recording calls to this `UnitOfWork`.
	 */
	public Mock calls() {
		return this.callRecorder;
	}

	private List<SObject> recordsPassedTo(String methodName) {
		List<SObject> records = new List<SObject>();
		for (List<Object> arguments : this.callRecorder.allArgumentsOf(methodName)) {
			Object firstArgument = arguments[0];
			// The list check has to come first: in Apex, a List<SObject> is also `instanceof
			// SObject`, so checking for the single-record overload first would match both.
			if (firstArgument instanceof List<SObject>) {
				records.addAll((List<SObject>) firstArgument);
			} else {
				records.add((SObject) firstArgument);
			}
		}
		return records;
	}
}
