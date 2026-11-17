/**
 * @description Example `before insert` Trigger Action: gives new Accounts a Rating when one wasn't
 * supplied - their parent Account's Rating if they have a rated parent, otherwise a default.
 *
 * This is the simpler half of the example, and it exists to make two points.
 *
 * **A `before` context needs no DML and no Unit of Work.** The records in `triggerNew` are the ones
 * about to be written, so setting a field on them is the entire operation. Registering them for
 * update would be wrong - it would write the same records a second time.
 *
 * **In a `before` context, look related records up by the lookup Id on `triggerNew`.** A new Account
 * has no Id yet, so there's nothing to query it by, but its `ParentId` is right there on the record.
 * The same habit is right in `before update`: the database still holds the old values then, so
 * querying through the trigger record would find the parent it *used* to have. `AccountSelector` runs
 * the query, and any other Trigger Action in this context that asks for the same parents gets them
 * without a second one.
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
		List<Account> accounts = (List<Account>) triggerNew;
		Map<Id, Account> parentsById = new Map<Id, Account>(
			AccountSelector.getInstance().selectById(this.parentIdsOfUnratedAccounts(accounts))
		);
		Integer defaultedCount = 0;
		for (Account account : accounts) {
			if (String.isBlank(account.Rating)) {
				account.Rating = this.ratingInheritedFrom(parentsById.get(account.ParentId));
				defaultedCount++;
			}
		}
		Logger.fine(
			'SetDefaultAccountRating set a Rating on ' +
				defaultedCount +
				' of ' +
				triggerNew.size() +
				' Account(s)'
		);
	}

	/**
	 * @description The parents worth querying: only those of Accounts that still need a Rating. A
	 * batch where every Account arrives rated, or has no parent, costs no query at all.
	 * @param accounts The Accounts about to be inserted.
	 * @return The `ParentId`s of the unrated Accounts.
	 */
	private Set<Id> parentIdsOfUnratedAccounts(List<Account> accounts) {
		Set<Id> parentIds = new Set<Id>();
		for (Account account : accounts) {
			if (String.isBlank(account.Rating) && account.ParentId != null) {
				parentIds.add(account.ParentId);
			}
		}
		return parentIds;
	}

	/**
	 * @description The Rating an unrated Account should start with. A parent the user can't see comes
	 * back from the selector as no parent at all, so it gets the default too.
	 * @param parent The Account's parent, or null if it has none (or none the user can see).
	 * @return The parent's Rating if it has one, otherwise `DEFAULT_RATING`.
	 */
	private String ratingInheritedFrom(Account parent) {
		if (parent != null && String.isNotBlank(parent.Rating)) {
			return parent.Rating;
		}
		return DEFAULT_RATING;
	}
}
