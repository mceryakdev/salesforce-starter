/**
 * @description Example `after insert` Trigger Action: for each new Account, registers a placeholder
 * primary Contact and an onboarding Case pointing at that Contact.
 *
 * This is the half of the example worth studying, because it shows the two ways a related record
 * gets its lookup populated:
 *
 * - **The Id already exists.** In an `after insert` context the Account has been written, so
 *   `AccountId` is just assigned directly.
 * - **The Id doesn't exist yet.** The Case needs to point at a Contact that hasn't been inserted,
 *   so `registerRelationship` records the intent, and the Unit of Work fills in `ContactId` after
 *   the Contact is inserted and before the Case is.
 *
 * Note what this class does *not* do: no `insert`, no savepoint, no ordering logic, and no
 * `commitWork()`. It registers intent and returns. `UOWMetadataTriggerHandler` commits once at the
 * true end of the trigger run, so this action costs the same two DML statements whether it runs for
 * one Account or two hundred.
 *
 * Wired up by the `Account_Create_Onboarding_Records` `Trigger_Action__mdt` record.
 */
public with sharing class CreateOnboardingRecords implements TriggerAction.AfterInsert {
	@TestVisible
	private static final String PRIMARY_CONTACT_LAST_NAME = 'Primary Contact';
	@TestVisible
	private static final String ONBOARDING_CASE_SUBJECT = 'Onboarding';

	/**
	 * @description Registers a primary Contact and an onboarding Case for each new Account.
	 * @param triggerNew The Accounts that were just inserted.
	 */
	public void afterInsert(List<SObject> triggerNew) {
		UnitOfWork unitOfWork = UnitOfWork.getCurrent();
		for (Account account : (List<Account>) triggerNew) {
			Contact primaryContact = new Contact(
				AccountId = account.Id,
				LastName = PRIMARY_CONTACT_LAST_NAME
			);
			Case onboardingCase = new Case(
				AccountId = account.Id,
				Subject = ONBOARDING_CASE_SUBJECT + ' - ' + account.Name
			);

			// Registration order is insert order, so the Contact's type is registered first.
			unitOfWork.registerNew(primaryContact);
			unitOfWork.registerNew(onboardingCase);

			// The Contact has no Id yet. This says "once it does, put it here" - the Unit of Work
			// populates ContactId after inserting the Contact and before inserting the Case.
			unitOfWork.registerRelationship(onboardingCase, Case.ContactId, primaryContact);
		}

		Logger.info('Registered onboarding records for ' + triggerNew.size() + ' Account(s)')
			.setRecord(triggerNew)
			.addTag('onboarding');
	}
}
