/**
 * @description A lightweight Unit of Work for batching DML.
 *
 * Register the records you want inserted, updated, or deleted as your code runs, then call
 * `commitWork()` once at the end to perform all of the DML together, as a single all-or-nothing
 * operation - if any part fails, everything registered on this instance is rolled back.
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
 */
public inherited sharing class UnitOfWork {
	@TestVisible
	private static final String ALREADY_COMMITTED_MESSAGE = 'This UnitOfWork has already been committed. Create a new instance to register more work.';
	@TestVisible
	private static final String MISSING_ID_MESSAGE = 'This record must have an Id to be registered as dirty or deleted. Use registerNew for records that have not been inserted yet.';

	@TestVisible
	private static UnitOfWork current;

	private Boolean committed = false;

	@TestVisible
	private List<Schema.SObjectType> sObjectTypeOrder = new List<Schema.SObjectType>();
	private Set<Schema.SObjectType> trackedTypes = new Set<Schema.SObjectType>();
	private Map<Schema.SObjectType, List<SObject>> newRecordsByType = new Map<Schema.SObjectType, List<SObject>>();
	private Map<Schema.SObjectType, Map<Id, SObject>> dirtyRecordsByType = new Map<Schema.SObjectType, Map<Id, SObject>>();
	private Map<Schema.SObjectType, Map<Id, SObject>> deletedRecordsByType = new Map<Schema.SObjectType, Map<Id, SObject>>();
	private Map<Schema.SObjectType, List<Relationship>> relationshipsByType = new Map<Schema.SObjectType, List<Relationship>>();

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
			this.recordsByIdFor(this.deletedRecordsByType, sObjectType)
				.put(record.Id, record);
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
	 */
	public void commitWork() {
		this.assertNotCommitted();
		this.committed = true;
		Savepoint savepoint = Database.setSavepoint();
		try {
			this.insertNewRecords();
			this.updateDirtyRecords();
			this.deleteRecordsInReverseOrder();
		} catch (Exception e) {
			Database.rollback(savepoint);
			throw e;
		}
	}

	private void insertNewRecords() {
		for (Schema.SObjectType sObjectType : this.sObjectTypeOrder) {
			List<SObject> records = this.newRecordsByType.get(sObjectType);
			if (records == null) {
				continue;
			}
			this.resolveRelationships(sObjectType);
			insert records;
		}
	}

	private void updateDirtyRecords() {
		for (Map<Id, SObject> recordsById : this.dirtyRecordsByType.values()) {
			update recordsById.values();
		}
	}

	private void deleteRecordsInReverseOrder() {
		for (Integer i = this.sObjectTypeOrder.size() - 1; i >= 0; i--) {
			Map<Id, SObject> recordsById = this.deletedRecordsByType.get(
				this.sObjectTypeOrder[i]
			);
			if (recordsById == null) {
				continue;
			}
			delete recordsById.values();
		}
	}

	private void resolveRelationships(Schema.SObjectType sObjectType) {
		List<Relationship> relationships = this.relationshipsByType.get(sObjectType);
		if (relationships == null) {
			return;
		}
		for (Relationship relationship : relationships) {
			relationship.resolve();
		}
	}

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

	private void trackType(Schema.SObjectType sObjectType) {
		if (this.trackedTypes.contains(sObjectType)) {
			return;
		}
		this.trackedTypes.add(sObjectType);
		this.sObjectTypeOrder.add(sObjectType);
	}

	private void assertNotCommitted() {
		if (this.committed) {
			throw new UnitOfWorkException(ALREADY_COMMITTED_MESSAGE);
		}
	}

	private void assertHasId(SObject record) {
		if (record.Id == null) {
			throw new UnitOfWorkException(MISSING_ID_MESSAGE);
		}
	}

	private class Relationship {
		private final SObject record;
		private final Schema.SObjectField relatedToField;
		private final SObject relatedTo;

		private Relationship(
			SObject record,
			Schema.SObjectField relatedToField,
			SObject relatedTo
		) {
			this.record = record;
			this.relatedToField = relatedToField;
			this.relatedTo = relatedTo;
		}

		private void resolve() {
			this.record.put(this.relatedToField, this.relatedTo.Id);
		}
	}

	/**
	 * @description Exception thrown for invalid usage of `UnitOfWork`.
	 */
	public class UnitOfWorkException extends Exception {
	}
}
