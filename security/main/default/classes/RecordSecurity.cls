/**
 * @description Checks what the current user is allowed to do to *specific records* - the row-level
 * access that comes from record ownership, the org-wide defaults, the role hierarchy, sharing rules,
 * and manual shares.
 *
 * This is the other half of the question `ObjectSecurity` answers. A user can have full Account
 * permissions on their profile and still not be able to see one particular Account, because
 * permissions decide *which objects and fields*, and sharing decides *which rows*. Both have to
 * pass, and they are checked separately.
 *
 * The answers come from the platform's `UserRecordAccess` object, which means every call runs a
 * query. Prefer the bulk methods, which answer for a whole set of Ids at once:
 *
 * ```
 * Set<Id> editable = RecordSecurity.getInstance().editableIds(new Map<Id, Account>(accounts).keySet());
 * for (Account account : accounts) {
 *     if (editable.contains(account.Id)) {
 *         // ...
 *     }
 * }
 * ```
 *
 * Calling the single-record methods inside a loop works, but costs one query per record and will run
 * into the query limit in any bulk context. The bulk methods cost one query per 200 records, which
 * is the most `UserRecordAccess` will answer for at a time.
 *
 * As with `ObjectSecurity`, each check comes in two forms: `readableIds`/`editableIds` and friends
 * return the subset the user is allowed to touch, while `checkRead`/`checkEdit` and friends throw a
 * `RecordSecurityException` naming the first record that failed.
 *
 * These are instance methods reached through `getInstance()` so that a test can replace the instance
 * with a mock, rather than having to build a second user and a sharing rule to produce a "no access"
 * case:
 *
 * ```
 * Mock mockSecurity = Mock.of(RecordSecurity.class).returns('editableIds', new Set<Id>());
 * RecordSecurity.instance = (RecordSecurity) mockSecurity.instance();
 * ```
 *
 * A record Id the platform returns no access row for - because it was deleted, or because the user
 * cannot see it at all - is reported as no access. Missing information is never read as permission.
 */
public inherited sharing class RecordSecurity {
  @TestVisible
  private static RecordSecurity instance;

  // `UserRecordAccess` answers for at most 200 records per query, so larger sets are split.
  @TestVisible
  private static final Integer MAX_IDS_PER_QUERY = 200;

  // `DELETE` is a reserved word in Apex, so the delete case is `DEL`.
  private enum Access {
    READ,
    EDIT,
    DEL,
    TRANSFER
  }

  private static final Map<Access, String> VERB_BY_ACCESS = new Map<Access, String>{
    Access.READ => 'read',
    Access.EDIT => 'edit',
    Access.DEL => 'delete',
    Access.TRANSFER => 'change the owner of'
  };

  /**
   * @description Returns the shared `RecordSecurity`, creating it if it doesn't exist yet. Reach
   * for this rather than `new RecordSecurity()` in code you intend to unit test, so that a test
   * can put a mock in its place.
   * @return The shared `RecordSecurity`.
   */
  public static RecordSecurity getInstance() {
    if (RecordSecurity.instance == null) {
      RecordSecurity.instance = new RecordSecurity();
    }
    return RecordSecurity.instance;
  }

  /**
   * @description Whether the current user can see this record.
   * @param recordId The record to check.
   * @return True if the user can see it.
   */
  public Boolean canRead(Id recordId) {
    return this.isAllowed(Access.READ, recordId);
  }

  /**
   * @description Whether the current user can edit this record.
   * @param recordId The record to check.
   * @return True if the user can edit it.
   */
  public Boolean canEdit(Id recordId) {
    return this.isAllowed(Access.EDIT, recordId);
  }

  /**
   * @description Whether the current user can delete this record.
   * @param recordId The record to check.
   * @return True if the user can delete it.
   */
  public Boolean canDelete(Id recordId) {
    return this.isAllowed(Access.DEL, recordId);
  }

  /**
   * @description Whether the current user can change this record's owner.
   * @param recordId The record to check.
   * @return True if the user can transfer it.
   */
  public Boolean canTransfer(Id recordId) {
    return this.isAllowed(Access.TRANSFER, recordId);
  }

  /**
   * @description The records, out of those given, that the current user can see.
   * @param recordIds The records to check.
   * @return The subset the user can see.
   */
  public Set<Id> readableIds(Set<Id> recordIds) {
    return this.allowedIds(Access.READ, recordIds);
  }

  /**
   * @description The records, out of those given, that the current user can edit.
   * @param recordIds The records to check.
   * @return The subset the user can edit.
   */
  public Set<Id> editableIds(Set<Id> recordIds) {
    return this.allowedIds(Access.EDIT, recordIds);
  }

  /**
   * @description The records, out of those given, that the current user can delete.
   * @param recordIds The records to check.
   * @return The subset the user can delete.
   */
  public Set<Id> deletableIds(Set<Id> recordIds) {
    return this.allowedIds(Access.DEL, recordIds);
  }

  /**
   * @description The records, out of those given, whose owner the current user can change.
   * @param recordIds The records to check.
   * @return The subset the user can transfer.
   */
  public Set<Id> transferableIds(Set<Id> recordIds) {
    return this.allowedIds(Access.TRANSFER, recordIds);
  }

  /**
   * @description Throws unless the current user can see this record.
   * @param recordId The record to check.
   */
  public void checkRead(Id recordId) {
    this.check(Access.READ, new Set<Id>{ recordId });
  }

  /**
   * @description Throws unless the current user can see every one of these records. The exception
   * names the first record that failed.
   * @param recordIds The records to check.
   */
  public void checkRead(Set<Id> recordIds) {
    this.check(Access.READ, recordIds);
  }

  /**
   * @description Throws unless the current user can edit this record.
   * @param recordId The record to check.
   */
  public void checkEdit(Id recordId) {
    this.check(Access.EDIT, new Set<Id>{ recordId });
  }

  /**
   * @description Throws unless the current user can edit every one of these records. The exception
   * names the first record that failed.
   * @param recordIds The records to check.
   */
  public void checkEdit(Set<Id> recordIds) {
    this.check(Access.EDIT, recordIds);
  }

  /**
   * @description Throws unless the current user can delete this record.
   * @param recordId The record to check.
   */
  public void checkDelete(Id recordId) {
    this.check(Access.DEL, new Set<Id>{ recordId });
  }

  /**
   * @description Throws unless the current user can delete every one of these records. The
   * exception names the first record that failed.
   * @param recordIds The records to check.
   */
  public void checkDelete(Set<Id> recordIds) {
    this.check(Access.DEL, recordIds);
  }

  /**
   * @description Throws unless the current user can change this record's owner.
   * @param recordId The record to check.
   */
  public void checkTransfer(Id recordId) {
    this.check(Access.TRANSFER, new Set<Id>{ recordId });
  }

  /**
   * @description Throws unless the current user can change the owner of every one of these
   * records. The exception names the first record that failed.
   * @param recordIds The records to check.
   */
  public void checkTransfer(Set<Id> recordIds) {
    this.check(Access.TRANSFER, recordIds);
  }

  /**
   * @description Answers for a single record by asking the bulk path about a set of one, so there
   * is only one place where access is actually decided.
   * @param access The kind of access being checked.
   * @param recordId The record to check.
   * @return True if the user has that access to the record.
   */
  private Boolean isAllowed(Access access, Id recordId) {
    return this.allowedIds(access, new Set<Id>{ recordId }).contains(recordId);
  }

  /**
   * @description The throwing counterpart of `allowedIds`. Asks once for the whole set, then names
   * the first record that came back without access - so checking two hundred records still costs
   * the same one query per two hundred that the bulk methods do.
   * @param access The kind of access being checked.
   * @param recordIds The records to check. Null or empty asks for nothing, and so passes.
   */
  private void check(Access access, Set<Id> recordIds) {
    if (recordIds == null || recordIds.isEmpty()) {
      return;
    }
    Set<Id> allowed = this.allowedIds(access, recordIds);
    for (Id recordId : recordIds) {
      if (!allowed.contains(recordId)) {
        throw new RecordSecurityException(
          'You do not have permission to ' +
            VERB_BY_ACCESS.get(access) +
            ' the record ' +
            recordId +
            '.'
        );
      }
    }
  }

  /**
   * @description Asks the platform which of these records the current user has the given access
   * to. Every public method funnels through here.
   *
   * A record the query returns no row for is simply left out of the result, which is what makes an
   * Id the user cannot see - or one that no longer exists - come back as "no access" rather than
   * as an error.
   * @param access The kind of access being checked.
   * @param recordIds The records to check. Null or empty returns an empty set without querying.
   * @return The subset of `recordIds` the user has that access to.
   */
  private Set<Id> allowedIds(Access access, Set<Id> recordIds) {
    Set<Id> allowed = new Set<Id>();
    if (recordIds == null || recordIds.isEmpty()) {
      return allowed;
    }
    for (List<Id> batch : this.batched(recordIds)) {
      for (UserRecordAccess recordAccess : [
        SELECT
          RecordId,
          HasReadAccess,
          HasEditAccess,
          HasDeleteAccess,
          HasTransferAccess
        FROM UserRecordAccess
        WHERE UserId = :UserInfo.getUserId() AND RecordId IN :batch
      ]) {
        if (this.hasAccess(access, recordAccess)) {
          allowed.add(recordAccess.RecordId);
        }
      }
    }
    return allowed;
  }

  /**
   * @description Reads the one field of an access row that answers the question being asked. This
   * is the one place that knows `EDIT` means `HasEditAccess`.
   * @param access The kind of access being checked.
   * @param recordAccess The platform's access row for one record.
   * @return True if that row grants the access.
   */
  private Boolean hasAccess(Access access, UserRecordAccess recordAccess) {
    switch on access {
      when READ {
        return recordAccess.HasReadAccess;
      }
      when EDIT {
        return recordAccess.HasEditAccess;
      }
      when DEL {
        return recordAccess.HasDeleteAccess;
      }
      when else {
        return recordAccess.HasTransferAccess;
      }
    }
  }

  /**
   * @description Splits the Ids into query-sized batches, because `UserRecordAccess` will only
   * answer for `MAX_IDS_PER_QUERY` records at a time and a trigger can easily hand us more.
   * @param recordIds The records to split. Expected to be non-empty.
   * @return The Ids in batches of at most `MAX_IDS_PER_QUERY`.
   */
  private List<List<Id>> batched(Set<Id> recordIds) {
    List<List<Id>> batches = new List<List<Id>>();
    List<Id> currentBatch = new List<Id>();
    for (Id recordId : recordIds) {
      if (currentBatch.size() == MAX_IDS_PER_QUERY) {
        batches.add(currentBatch);
        currentBatch = new List<Id>();
      }
      currentBatch.add(recordId);
    }
    batches.add(currentBatch);
    return batches;
  }

  /**
   * @description Thrown when the current user does not have the record-level access that a
   * `checkX` method required.
   */
  public class RecordSecurityException extends Exception {
  }
}
