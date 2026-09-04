/**
 * @description Example `before insert` Trigger Action: gives new Accounts a default Rating when one
 * wasn't supplied.
 *
 * This is the simpler half of the example, and it exists to make one point: **a `before` context
 * needs no DML and no Unit of Work.** The records in `triggerNew` are the ones about to be written,
 * so setting a field on them is the entire operation. Registering them for update would be wrong -
 * it would write the same records a second time.
 *
 * Reach for the Unit of Work when you need to touch *other* records; see `CreateOnboardingRecords`
 * for that half.
 *
 * Wired up by the `Account_Set_Default_Rating` `Trigger_Action__mdt` record.
 */
public with sharing class SetDefaultAccountRating implements TriggerAction.BeforeInsert {
	@TestVisible
	private static final String DEFAULT_RATING = 'Warm';

	/**
	 * @description Sets `Rating` on every Account that doesn't already have one.
	 * @param triggerNew The Accounts about to be inserted.
	 */
	public void beforeInsert(List<SObject> triggerNew) {
		Integer defaultedCount = 0;
		for (Account account : (List<Account>) triggerNew) {
			if (String.isBlank(account.Rating)) {
				account.Rating = DEFAULT_RATING;
				defaultedCount++;
			}
		}
		Logger.fine(
			'SetDefaultAccountRating defaulted ' +
				defaultedCount +
				' of ' +
				triggerNew.size() +
				' Account(s) to ' +
				DEFAULT_RATING
		);
	}
}
