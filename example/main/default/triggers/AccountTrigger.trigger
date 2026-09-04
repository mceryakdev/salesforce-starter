/**
 * @description Example trigger. Every context is listed, and the body is one line - which is the
 * point. Nothing about *what* happens on Account lives here; that's configured as
 * `Trigger_Action__mdt` records, so actions can be added, reordered, or bypassed without touching
 * this file.
 *
 * `UOWMetadataTriggerHandler` is used in place of the framework's own `MetadataTriggerHandler` so
 * that work registered on the Unit of Work is committed once, at the true end of the run.
 */
trigger AccountTrigger on Account(
	before insert,
	after insert,
	before update,
	after update,
	before delete,
	after delete,
	after undelete
) {
	new UOWMetadataTriggerHandler().run();
}
