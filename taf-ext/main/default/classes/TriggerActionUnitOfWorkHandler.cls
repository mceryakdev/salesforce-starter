/**
 * @description A drop-in replacement for `MetadataTriggerHandler` that commits the current
 * `UnitOfWork` (see `UnitOfWork.getCurrent()`/`commitCurrent()`) at the true end of each trigger
 * run - after every before/after context has fired, including any recursive re-entry caused by
 * the same top-level DML statement - and before any `DmlFinalizer`s run.
 *
 * `MetadataTriggerHandler` itself cannot be subclassed, so this class implements the Trigger
 * Action interfaces directly and forwards every call to a `MetadataTriggerHandler` instance -
 * none of its metadata-driven dispatch, bypass, or permission behavior changes.
 *
 * Use this in place of `MetadataTriggerHandler` in your triggers to get Unit of Work support:
 *
 * ```
 * trigger AccountTrigger on Account (
 *     before insert, after insert, before update, after update,
 *     before delete, after delete, after undelete
 * ) {
 *     new TriggerActionUnitOfWorkHandler().run();
 * }
 * ```
 *
 * Trigger Actions can then call `UnitOfWork.getCurrent()` to register work instead of performing
 * DML directly.
 */
public inherited sharing class TriggerActionUnitOfWorkHandler extends TriggerBase implements TriggerAction.BeforeInsert, TriggerAction.AfterInsert, TriggerAction.BeforeUpdate, TriggerAction.AfterUpdate, TriggerAction.BeforeDelete, TriggerAction.AfterDelete, TriggerAction.AfterUndelete {
	@TestVisible
	private static MetadataTriggerHandler metadataTriggerHandler = new MetadataTriggerHandler();
	@TestVisible
	private static FinalizerHandler finalizerHandler = new FinalizerHandler();

	/**
	 * @description Forwards to `MetadataTriggerHandler.beforeInsert`.
	 * @param triggerNew The list of new records that are being inserted.
	 */
	public void beforeInsert(List<SObject> triggerNew) {
		metadataTriggerHandler.beforeInsert(triggerNew);
	}

	/**
	 * @description Forwards to `MetadataTriggerHandler.afterInsert`.
	 * @param triggerNew The list of new records that were inserted.
	 */
	public void afterInsert(List<SObject> triggerNew) {
		metadataTriggerHandler.afterInsert(triggerNew);
	}

	/**
	 * @description Forwards to `MetadataTriggerHandler.beforeUpdate`.
	 * @param triggerNew The list of new records that are being updated.
	 * @param triggerOld The list of old records that are being updated.
	 */
	public void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
		metadataTriggerHandler.beforeUpdate(triggerNew, triggerOld);
	}

	/**
	 * @description Forwards to `MetadataTriggerHandler.afterUpdate`.
	 * @param triggerNew The list of new records that were updated.
	 * @param triggerOld The list of old records before the update.
	 */
	public void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld) {
		metadataTriggerHandler.afterUpdate(triggerNew, triggerOld);
	}

	/**
	 * @description Forwards to `MetadataTriggerHandler.beforeDelete`.
	 * @param triggerOld The list of records that are being deleted.
	 */
	public void beforeDelete(List<SObject> triggerOld) {
		metadataTriggerHandler.beforeDelete(triggerOld);
	}

	/**
	 * @description Forwards to `MetadataTriggerHandler.afterDelete`.
	 * @param triggerOld The list of records that were deleted.
	 */
	public void afterDelete(List<SObject> triggerOld) {
		metadataTriggerHandler.afterDelete(triggerOld);
	}

	/**
	 * @description Forwards to `MetadataTriggerHandler.afterUndelete`.
	 * @param triggerNew The list of records that were undeleted.
	 */
	public void afterUndelete(List<SObject> triggerNew) {
		metadataTriggerHandler.afterUndelete(triggerNew);
	}

	/**
	 * @description Commits the current `UnitOfWork`, then runs any configured `DmlFinalizer`s -
	 * this is called automatically, once, at the true end of the trigger run.
	 */
	@TestVisible
	protected override void finalizeDmlOperation() {
		UnitOfWork.commitCurrent();
		finalizerHandler.handleDynamicFinalizers();
	}
}
