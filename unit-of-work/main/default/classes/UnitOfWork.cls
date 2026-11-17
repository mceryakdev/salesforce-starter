/**
 * @description A lightweight Unit of Work for batching DML.
 *
 * Register the records you want inserted, updated, or deleted as your code runs, then call
 * `commitWork()` once at the end to perform all of the DML together, as a single all-or-nothing
 * operation - if any part fails, everything registered on this instance is rolled back. Failures
 * are logged via Nebula Logger (`Logger.exception`) before the original exception is rethrown
 * unchanged; because that log entry is published as a platform event, it survives the DML
 * rollback that just happened.
 *
 * New records are inserted in the order their sObject type was first registered, and deleted
 * records are deleted in the reverse of that order, so parent records exist before the children
 * that reference them, and are only removed after their children are gone. Register in "parent,
 * then children" order for both inserts and deletes - this class takes care of reversing it for
 * deletes.
 *
 * Use `registerRelationship` to point a not-yet-inserted record at another not-yet-inserted
 * record. The lookup field is populated automatically right before the referencing record is
 * inserted, once the related record has already been inserted and has an Id.
 *
 * This class has no knowledge of triggers - it can be used from anywhere in Apex. You can create
 * and commit your own instance directly:
 *
 * ```
 * UnitOfWork uow = new UnitOfWork();
 * Account acct = new Account(Name = 'Acme');
 * Contact con = new Contact(LastName = 'Coyote');
 * uow.registerNew(acct);
 * uow.registerNew(con);
 * uow.registerRelationship(con, Contact.AccountId, acct);
 * uow.commitWork();
 * ```
 *
 * Or, when several classes need to share one instance without passing it around, use `getCurrent()`
 * to get an ambient "current" instance, and `commitCurrent()` once, at whatever point in your code
 * represents "this piece of work is done," to commit it and clear it so the next caller starts
 * fresh:
 *
 * ```
 * UnitOfWork.getCurrent().registerNew(new Task(Subject = 'Follow up'));
 * // ... more code, possibly in other classes, registers more work on the same instance ...
 * UnitOfWork.commitCurrent();
 * ```
 *
 * By default the DML runs exactly the way a plain `insert`/`update`/`delete` statement written in
 * the calling class would: object permissions and field-level security are not enforced, and sharing
 * follows whatever context the calling code established. Pass an access level to change that, and
 * the platform enforces the current user's object permissions, field-level security, and sharing
 * rules on everything this instance commits:
 *
 * ```
 * UnitOfWork uow = new UnitOfWork(AccessLevel.USER_MODE);
 * ```
 *
 * That is usually a better way to enforce access on DML than checking permissions field by field
 * before registering, because the platform applies the same rules the rest of Salesforce does. What
 * it does not do is tell you *in advance* whether the user would be allowed - for that, see the
 * `security` package.
 *
 * Note that passing `AccessLevel.SYSTEM_MODE` is not the same as leaving the access level unset:
 * setting it explicitly also bypasses sharing rules, which the default leaves to the calling
 * context.
 *
 * Any commit that writes something also empties every `QueryCache`, so selectors query again rather
 * than hand out records from before the commit.
 */
public inherited sharing class UnitOfWork {
	@TestVisible
	private static final String ALREADY_COMMITTED_MESSAGE = 'This UnitOfWork has already been committed. Create a new instance to register more work.';
	@TestVisible
	private static final String MISSING_ID_MESSAGE = 'This record must have an Id to be registered as dirty or deleted. Use registerNew for records that have not been inserted yet.';
	@TestVisible
	private static final String UNRESOLVED_RELATIONSHIP_MESSAGE = 'Cannot populate {0}: the related record still has no Id when the record referencing it is about to be inserted. Register the related record with registerNew before registering the record that points at it - types are inserted in the order they were first registered.';

	@TestVisible
	private static UnitOfWork current;

	@TestVisible
	private final System.AccessLevel accessLevel;

	private Boolean committed = false;

	@TestVisible
	private List<Schema.SObjectType> sObjectTypeOrder = new List<Schema.SObjectType>();
	private Set<Schema.SObjectType> trackedTypes = new Set<Schema.SObjectType>();
	private Map<Schema.SObjectType, List<SObject>> newRecordsByType = new Map<Schema.SObjectType, List<SObject>>();
	private Map<Schema.SObjectType, Map<Id, SObject>> dirtyRecordsByType = new Map<Schema.SObjectType, Map<Id, SObject>>();
	private Map<Schema.SObjectType, Map<Id, SObject>> deletedRecordsByType = new Map<Schema.SObjectType, Map<Id, SObject>>();
	private Map<Schema.SObjectType, List<Relationship>> relationshipsByType = new Map<Schema.SObjectType, List<Relationship>>();

	/**
	 * @description Creates a `UnitOfWork` whose DML runs the way a plain DML statement written in the
	 * calling class would - object permissions and field-level security are not enforced, and sharing
	 * follows the calling code's context.
	 */
	public UnitOfWork() {
		this(null);
	}

	/**
	 * @description Creates a `UnitOfWork` that runs all of its DML at the given access level. Pass
	 * `AccessLevel.USER_MODE` to have the platform enforce the current user's object permissions,
	 * field-level security, and sharing rules when this instance commits.
	 *
	 * Passing `AccessLevel.SYSTEM_MODE` is not the same as using the no-argument constructor: it also
	 * bypasses sharing rules, where the default leaves sharing to the calling context.
	 * @param accessLevel The access level to run this instance's DML at, or null for the default.
	 */
	public UnitOfWork(System.AccessLevel accessLevel) {
		this.accessLevel = accessLevel;
	}

	/**
	 * @description Returns the current `UnitOfWork`, creating one if none exists yet. Use this
	 * when several classes need to share one instance without passing it around.
	 * @return The current `UnitOfWork`.
	 */
	public static UnitOfWork getCurrent() {
		if (UnitOfWork.current == null) {
			UnitOfWork.current = new UnitOfWork();
		}
		return UnitOfWork.current;
	}

	/**
	 * @description Returns the current `UnitOfWork`, creating one at the given access level if none
	 * exists yet. If a current instance already exists it is returned unchanged, because an
	 * instance's access level is fixed when it is created.
	 * @param accessLevel The access level to create the instance at, if one has to be created.
	 * @return The current `UnitOfWork`.
	 */
	public static UnitOfWork getCurrent(System.AccessLevel accessLevel) {
		if (UnitOfWork.current == null) {
			UnitOfWork.current = new UnitOfWork(accessLevel);
		}
		return UnitOfWork.current;
	}

	/**
	 * @description Commits the current `UnitOfWork`, if one exists, and clears it so that the next
	 * call to `getCurrent()` starts a new instance. Does nothing if `getCurrent()` was never called.
	 */
	public static void commitCurrent() {
		if (UnitOfWork.current == null) {
			return;
		}
		UnitOfWork unitOfWorkToCommit = UnitOfWork.current;
		UnitOfWork.current = null;
		unitOfWorkToCommit.commitWork();
	}

	/**
	 * @description Registers a record to be inserted when `commitWork` is called.
	 * @param record The record to insert.
	 */
	public void registerNew(SObject record) {
		this.registerNew(new List<SObject>{ record });
	}

	/**
	 * @description Registers a list of records to be inserted when `commitWork` is called.
	 * @param records The records to insert.
	 */
	public void registerNew(List<SObject> records) {
		this.assertNotCommitted();
		for (SObject record : records) {
			Schema.SObjectType sObjectType = record.getSObjectType();
			this.trackType(sObjectType);
			this.addToGroup(this.newRecordsByType, sObjectType, record);
		}
	}

	/**
	 * @description Registers a record to be updated when `commitWork` is called. The record must
	 * already have an Id. Registering the same Id more than once merges the populated fields from
	 * every call onto a single record, so unrelated fields set in separate calls are all included
	 * in one `update` - if the same field is set more than once, the last call wins.
	 * @param record The record to update.
	 */
	public void registerDirty(SObject record) {
		this.registerDirty(new List<SObject>{ record });
	}

	/**
	 * @description Registers a list of records to be updated when `commitWork` is called. See
	 * `registerDirty(SObject)` for how repeated registrations of the same Id are merged.
	 * @param records The records to update.
	 */
	public void registerDirty(List<SObject> records) {
		this.assertNotCommitted();
		for (SObject record : records) {
			this.assertHasId(record);
			this.mergeIntoDirty(record);
		}
	}

	/**
	 * @description Registers a record to be deleted when `commitWork` is called. The record must
	 * already have an Id. Registering the same Id more than once has no additional effect.
	 * @param record The record to delete.
	 */
	public void registerDeleted(SObject record) {
		this.registerDeleted(new List<SObject>{ record });
	}

	/**
	 * @description Registers a list of records to be deleted when `commitWork` is called. See
	 * `registerDeleted(SObject)` for how repeated registrations of the same Id are handled.
	 * @param records The records to delete.
	 */
	public void registerDeleted(List<SObject> records) {
		this.assertNotCommitted();
		for (SObject record : records) {
			this.assertHasId(record);
			Schema.SObjectType sObjectType = record.getSObjectType();
			this.trackType(sObjectType);
			this.recordsByIdFor(this.deletedRecordsByType, sObjectType).put(record.Id, record);
		}
	}

	/**
	 * @description Registers a lookup field to be populated with the Id of another registered
	 * record once that record has been inserted. Use this when a not-yet-inserted record needs to
	 * point at another not-yet-inserted record - register the parent with `registerNew` first,
	 * then register this relationship for the child before calling `commitWork`.
	 *
	 * @param record The record whose lookup field should be populated.
	 * @param relatedToField The lookup field on `record` to populate.
	 * @param relatedTo The record whose Id should be written into `relatedToField` once it exists.
	 */
	public void registerRelationship(
		SObject record,
		Schema.SObjectField relatedToField,
		SObject relatedTo
	) {
		this.assertNotCommitted();
		Schema.SObjectType sObjectType = record.getSObjectType();
		List<Relationship> relationships = this.relationshipsByType.get(sObjectType);
		if (relationships == null) {
			relationships = new List<Relationship>();
			this.relationshipsByType.put(sObjectType, relationships);
		}
		relationships.add(new Relationship(record, relatedToField, relatedTo));
	}

	/**
	 * @description Commits all of the work registered on this instance - inserts, then updates,
	 * then deletes - as a single all-or-nothing operation. If any DML fails, everything registered
	 * on this instance is rolled back and the exception is re-thrown. Once called, this instance
	 * cannot register or commit more work - create a new `UnitOfWork` for further work.
	 *
	 * Whether it succeeds or fails, a commit that writes anything empties every `QueryCache`. On
	 * success the cached records are out of date. On failure it matters just as much: the commit
	 * fires triggers while it runs, and their selectors may have cached records that the rollback
	 * has just undone.
	 */
	public void commitWork() {
		this.assertNotCommitted();
		this.committed = true;
		Integer recordsToInsert = this.countRecords(this.newRecordsByType);
		Integer recordsToUpdate = this.countRecords(this.dirtyRecordsByType);
		Integer recordsToDelete = this.countRecords(this.deletedRecordsByType);
		Logger.fine(
			'UnitOfWork.commitWork starting: ' +
				recordsToInsert +
				' to insert, ' +
				recordsToUpdate +
				' to update, ' +
				recordsToDelete +
				' to delete'
		);
		if (recordsToInsert + recordsToUpdate + recordsToDelete == 0) {
			// Nothing to do, and `Database.setSavepoint()` costs a DML statement against the same
			// governor limit as the DML itself - so an empty commit should stay genuinely free. It
			// also leaves the query caches alone: nothing was written, so nothing they hold is stale.
			return;
		}
		Savepoint savepoint = Database.setSavepoint();
		try {
			this.insertNewRecords();
			this.updateDirtyRecords();
			this.deleteRecordsInReverseOrder();
		} catch (Exception e) {
			Database.rollback(savepoint);
			Logger.exception('UnitOfWork.commitWork failed; all registered changes were rolled back', e);
		} finally {
			QueryCache.clearAll();
		}
	}

	/**
	 * @description Inserts each type's new records, in the order the types were first registered, so
	 * that a parent type registered before its children exists by the time they are inserted.
	 * Relationships are resolved per type immediately before that type's insert, which is the last
	 * moment at which the record being pointed at is guaranteed to have an Id.
	 */
	private void insertNewRecords() {
		for (Schema.SObjectType sObjectType : this.sObjectTypeOrder) {
			List<SObject> records = this.newRecordsByType.get(sObjectType);
			if (records == null) {
				continue;
			}
			this.resolveRelationships(sObjectType);
			this.insertRecords(records);
		}
	}

	/**
	 * @description Updates each type's dirty records. Order doesn't matter here the way it does for
	 * inserts and deletes: every record already exists, so nothing depends on anything else having
	 * been written first.
	 */
	private void updateDirtyRecords() {
		for (Map<Id, SObject> recordsById : this.dirtyRecordsByType.values()) {
			this.updateRecords(recordsById.values());
		}
	}

	/**
	 * @description Deletes each type's records in the reverse of the order the types were registered
	 * in. Deleting is the mirror image of inserting: children have to go before the parents they
	 * reference, so callers can register in "parent, then children" order for both and let this
	 * handle the reversal.
	 */
	private void deleteRecordsInReverseOrder() {
		for (Integer i = this.sObjectTypeOrder.size() - 1; i >= 0; i--) {
			Map<Id, SObject> recordsById = this.deletedRecordsByType.get(this.sObjectTypeOrder[i]);
			if (recordsById == null) {
				continue;
			}
			this.deleteRecords(recordsById.values());
		}
	}

	/**
	 * @description Inserts the records, enforcing this instance's access level if one was requested.
	 *
	 * When no access level was requested this runs a plain DML statement rather than passing
	 * `AccessLevel.SYSTEM_MODE`, because the two are not equivalent: passing system mode explicitly
	 * would also bypass sharing rules, where a plain statement leaves sharing to the calling
	 * context. Both paths are all-or-nothing, so a failure throws and the caller's savepoint rolls
	 * everything back.
	 * @param records The records to insert.
	 */
	private void insertRecords(List<SObject> records) {
		if (this.accessLevel == null) {
			insert records;
		} else {
			Database.insert(records, true, this.accessLevel);
		}
	}

	/**
	 * @description Updates the records, enforcing this instance's access level if one was requested.
	 * See `insertRecords` for why the default path is a plain DML statement.
	 * @param records The records to update.
	 */
	private void updateRecords(List<SObject> records) {
		if (this.accessLevel == null) {
			update records;
		} else {
			Database.update(records, true, this.accessLevel);
		}
	}

	/**
	 * @description Deletes the records, enforcing this instance's access level if one was requested.
	 * See `insertRecords` for why the default path is a plain DML statement.
	 * @param records The records to delete.
	 */
	private void deleteRecords(List<SObject> records) {
		if (this.accessLevel == null) {
			delete records;
		} else {
			Database.delete(records, true, this.accessLevel);
		}
	}

	/**
	 * @description Populates the lookup fields registered for this type, filling in Ids that did not
	 * exist when `registerRelationship` was called. Doing nothing when a type has no registered
	 * relationships is the common case, not an error.
	 * @param sObjectType The type whose relationships should be resolved.
	 */
	private void resolveRelationships(Schema.SObjectType sObjectType) {
		List<Relationship> relationships = this.relationshipsByType.get(sObjectType);
		if (relationships == null) {
			return;
		}
		for (Relationship relationship : relationships) {
			relationship.resolve();
		}
	}

	/**
	 * @description Adds a record to its type's list, creating the list on first use. New records are
	 * kept in a plain list rather than keyed by Id, because they don't have one yet - and because
	 * registering the same new record twice should genuinely insert it twice.
	 * @param recordsByType The grouping to add to.
	 * @param sObjectType The type the record belongs to.
	 * @param record The record to add.
	 */
	private void addToGroup(
		Map<Schema.SObjectType, List<SObject>> recordsByType,
		Schema.SObjectType sObjectType,
		SObject record
	) {
		List<SObject> records = recordsByType.get(sObjectType);
		if (records == null) {
			records = new List<SObject>();
			recordsByType.put(sObjectType, records);
		}
		records.add(record);
	}

	/**
	 * @description Folds a dirty record into whatever was already registered for that Id, so two
	 * classes can each set a different field on the same record and both changes survive into a
	 * single update. Only fields the caller actually populated are copied - copying every field would
	 * overwrite the other caller's work with nulls - which means the last call to set a given field
	 * wins, and fields nobody set are left alone.
	 * @param record The record whose populated fields should be merged in.
	 */
	private void mergeIntoDirty(SObject record) {
		Map<Id, SObject> recordsById = this.recordsByIdFor(
			this.dirtyRecordsByType,
			record.getSObjectType()
		);
		SObject existingRecord = recordsById.get(record.Id);
		if (existingRecord == null) {
			recordsById.put(record.Id, record);
			return;
		}
		for (String fieldName : record.getPopulatedFieldsAsMap().keySet()) {
			existingRecord.put(fieldName, record.get(fieldName));
		}
	}

	/**
	 * @description Returns the by-Id map for a type, creating it on first use. Dirty and deleted
	 * records are keyed by Id rather than listed, which is what makes registering the same record
	 * twice harmless for both.
	 * @param recordsByType The grouping to look in.
	 * @param sObjectType The type whose records are wanted.
	 * @return That type's records, keyed by Id.
	 */
	private Map<Id, SObject> recordsByIdFor(
		Map<Schema.SObjectType, Map<Id, SObject>> recordsByType,
		Schema.SObjectType sObjectType
	) {
		Map<Id, SObject> recordsById = recordsByType.get(sObjectType);
		if (recordsById == null) {
			recordsById = new Map<Id, SObject>();
			recordsByType.put(sObjectType, recordsById);
		}
		return recordsById;
	}

	/**
	 * @description Totals the records across every type in a listed grouping, for the summary logged
	 * before committing.
	 * @param recordsByType The grouping to count.
	 * @return The total number of records in it.
	 */
	private Integer countRecords(Map<Schema.SObjectType, List<SObject>> recordsByType) {
		Integer total = 0;
		for (List<SObject> records : recordsByType.values()) {
			total += records.size();
		}
		return total;
	}

	/**
	 * @description The by-Id counterpart of the other `countRecords`, for the dirty and deleted
	 * groupings.
	 * @param recordsByType The grouping to count.
	 * @return The total number of records in it.
	 */
	private Integer countRecords(Map<Schema.SObjectType, Map<Id, SObject>> recordsByType) {
		Integer total = 0;
		for (Map<Id, SObject> records : recordsByType.values()) {
			total += records.size();
		}
		return total;
	}

	/**
	 * @description Records the first time a type is registered, building the order that inserts
	 * follow and deletes reverse. Later registrations of the same type don't move it, so the order
	 * reflects when each type was first seen rather than most recently touched.
	 * @param sObjectType The type that was registered.
	 */
	private void trackType(Schema.SObjectType sObjectType) {
		if (this.trackedTypes.contains(sObjectType)) {
			return;
		}
		this.trackedTypes.add(sObjectType);
		this.sObjectTypeOrder.add(sObjectType);
	}

	/**
	 * @description Guards every method that registers or commits work. A committed instance has
	 * already run its DML and cleared nothing, so letting it accept more work would silently drop it.
	 */
	private void assertNotCommitted() {
		if (this.committed) {
			throw new UnitOfWorkException(ALREADY_COMMITTED_MESSAGE);
		}
	}

	/**
	 * @description Guards `registerDirty` and `registerDeleted`, both of which key records by Id. A
	 * record with no Id would otherwise be silently grouped under a null key and lost.
	 * @param record The record that must already exist.
	 */
	private void assertHasId(SObject record) {
		if (record.Id == null) {
			throw new UnitOfWorkException(MISSING_ID_MESSAGE);
		}
	}

	/**
	 * @description One deferred "point this record's lookup field at that record" instruction. It
	 * holds the two records themselves rather than an Id, because the whole point is that the Id does
	 * not exist yet when the relationship is registered.
	 */
	private class Relationship {
		private final SObject record;
		private final Schema.SObjectField relatedToField;
		private final SObject relatedTo;

		/**
		 * @description Records the intent to populate a lookup, to be acted on later.
		 * @param record The record whose lookup field should be populated.
		 * @param relatedToField The lookup field on `record` to populate.
		 * @param relatedTo The record whose Id should be written into `relatedToField`.
		 */
		private Relationship(SObject record, Schema.SObjectField relatedToField, SObject relatedTo) {
			this.record = record;
			this.relatedToField = relatedToField;
			this.relatedTo = relatedTo;
		}

		/**
		 * @description Writes the related record's Id into the lookup field, at the point just before
		 * the referencing record is inserted. A related record that still has no Id by now never will -
		 * it was either never registered, or registered after the record pointing at it - so this
		 * throws rather than writing a null lookup and leaving a silently orphaned record behind.
		 */
		private void resolve() {
			if (this.relatedTo.Id == null) {
				throw new UnitOfWorkException(
					String.format(
						UNRESOLVED_RELATIONSHIP_MESSAGE,
						new List<String>{ String.valueOf(this.relatedToField) }
					)
				);
			}
			this.record.put(this.relatedToField, this.relatedTo.Id);
		}
	}

	/**
	 * @description Exception thrown for invalid usage of `UnitOfWork`.
	 */
	public class UnitOfWorkException extends Exception {
	}
}
