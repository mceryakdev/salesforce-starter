/**
 * @description Checks what the current user is allowed to do to an sObject and its fields - the
 * object permissions ("CRUD") and field-level security ("FLS") granted by their profile and
 * permission sets.
 *
 * Every check comes in two forms, and which one you want depends on what your code does next.
 * `canX` answers the question and hands you a Boolean, for when there is a decision to make:
 *
 * ```
 * if (ObjectSecurity.getInstance().canUpdate(Account.SObjectType, new List<Schema.SObjectField>{ Account.Rating })) {
 *     // safe to offer the user a "re-rate this account" option
 * }
 * ```
 *
 * `checkX` throws an `ObjectSecurityException` naming whatever failed, for when missing access means
 * the code simply cannot continue:
 *
 * ```
 * ObjectSecurity.getInstance()
 *     .checkCreate(Contact.SObjectType, new List<Schema.SObjectField>{ Contact.LastName });
 * ```
 *
 * Both forms check the object first and then every field you pass, so a single call covers "can this
 * user create Contacts at all, and can they write the fields I am about to populate?". Fields are
 * optional - leave them off to check only the object.
 *
 * Fields can be given as tokens (`Contact.LastName`) or as API names (`'LastName'`), so a field list
 * that came from custom metadata, a fieldset, or an LWC is checked exactly like a hardcoded one. API
 * names are matched case-insensitively, and a name that doesn't exist on the object throws rather
 * than quietly passing - a typo in configuration should fail loudly, not silently grant access.
 *
 * These are instance methods reached through `getInstance()`, for the same reason `UnitOfWork` works
 * that way: a test can replace the instance with a mock and make these checks answer however the
 * test needs, instead of building a restricted user and a permission set to produce a "no access"
 * case.
 *
 * ```
 * Mock mockSecurity = Mock.of(ObjectSecurity.class).returns('canCreate', false);
 * ObjectSecurity.instance = (ObjectSecurity) mockSecurity.instance();
 * ```
 *
 * Two things this class deliberately does not do:
 *
 * - It does not check *record*-level access - whether sharing lets this user see one particular
 *   record. Object permissions and sharing are separate systems; `RecordSecurity` covers that one.
 * - It does not strip or filter anything. When you want inaccessible fields quietly removed rather
 *   than reported, the platform's own `Security.stripInaccessible(...)` is built for exactly that.
 *
 * If you are about to run DML and just want the platform to enforce all of this for you, prefer
 * doing that directly - `Database.insert(records, AccessLevel.USER_MODE)`, or
 * `new UnitOfWork(AccessLevel.USER_MODE)`. These checks are for the decisions you make *before* that
 * point, and for the times you need to know rather than just to fail.
 */
public inherited sharing class ObjectSecurity {
  @TestVisible
  private static ObjectSecurity instance;

  // `UPDATE` and `DELETE` are reserved words in Apex, so those cases are `MODIFY` and `DEL`.
  private enum Operation {
    CREATE,
    READ,
    MODIFY,
    DEL
  }

  private static final Map<Operation, String> VERB_BY_OPERATION = new Map<Operation, String>{
    Operation.CREATE => 'create',
    Operation.READ => 'read',
    Operation.MODIFY => 'update',
    Operation.DEL => 'delete'
  };

  /**
   * @description Returns the shared `ObjectSecurity`, creating it if it doesn't exist yet. Reach
   * for this rather than `new ObjectSecurity()` in code you intend to unit test, so that a test
   * can put a mock in its place.
   * @return The shared `ObjectSecurity`.
   */
  public static ObjectSecurity getInstance() {
    if (ObjectSecurity.instance == null) {
      ObjectSecurity.instance = new ObjectSecurity();
    }
    return ObjectSecurity.instance;
  }

  /**
   * @description Whether the current user can create records of this sObject.
   * @param objectType The sObject to check.
   * @return True if the user can create records of this sObject.
   */
  public Boolean canCreate(Schema.SObjectType objectType) {
    return this.isObjectAllowed(Operation.CREATE, objectType);
  }

  /**
   * @description Whether the current user can create records of this sObject and populate all of
   * these fields.
   * @param objectType The sObject to check.
   * @param fields The fields the user needs to be able to populate.
   * @return True if the user can create the sObject and write every field.
   */
  public Boolean canCreate(
    Schema.SObjectType objectType,
    List<Schema.SObjectField> fields
  ) {
    return this.isAllowed(Operation.CREATE, objectType, fields);
  }

  /**
   * @description Whether the current user can create records of this sObject and populate all of
   * these fields, named by API name.
   * @param objectType The sObject to check.
   * @param fieldNames The API names of the fields the user needs to be able to populate.
   * @return True if the user can create the sObject and write every field.
   */
  public Boolean canCreate(
    Schema.SObjectType objectType,
    List<String> fieldNames
  ) {
    return this.isAllowed(
      Operation.CREATE,
      objectType,
      this.toFields(objectType, fieldNames)
    );
  }

  /**
   * @description Throws unless the current user can create records of this sObject.
   * @param objectType The sObject to check.
   */
  public void checkCreate(Schema.SObjectType objectType) {
    this.check(Operation.CREATE, objectType, new List<Schema.SObjectField>());
  }

  /**
   * @description Throws unless the current user can create records of this sObject and populate
   * all of these fields. The exception names the object or the first field that failed.
   * @param objectType The sObject to check.
   * @param fields The fields the user needs to be able to populate.
   */
  public void checkCreate(
    Schema.SObjectType objectType,
    List<Schema.SObjectField> fields
  ) {
    this.check(Operation.CREATE, objectType, fields);
  }

  /**
   * @description Throws unless the current user can create records of this sObject and populate
   * all of these fields, named by API name.
   * @param objectType The sObject to check.
   * @param fieldNames The API names of the fields the user needs to be able to populate.
   */
  public void checkCreate(
    Schema.SObjectType objectType,
    List<String> fieldNames
  ) {
    this.check(
      Operation.CREATE,
      objectType,
      this.toFields(objectType, fieldNames)
    );
  }

  /**
   * @description Whether the current user can read records of this sObject.
   * @param objectType The sObject to check.
   * @return True if the user can read records of this sObject.
   */
  public Boolean canRead(Schema.SObjectType objectType) {
    return this.isObjectAllowed(Operation.READ, objectType);
  }

  /**
   * @description Whether the current user can read records of this sObject and see all of these
   * fields.
   * @param objectType The sObject to check.
   * @param fields The fields the user needs to be able to see.
   * @return True if the user can read the sObject and every field.
   */
  public Boolean canRead(
    Schema.SObjectType objectType,
    List<Schema.SObjectField> fields
  ) {
    return this.isAllowed(Operation.READ, objectType, fields);
  }

  /**
   * @description Whether the current user can read records of this sObject and see all of these
   * fields, named by API name.
   * @param objectType The sObject to check.
   * @param fieldNames The API names of the fields the user needs to be able to see.
   * @return True if the user can read the sObject and every field.
   */
  public Boolean canRead(
    Schema.SObjectType objectType,
    List<String> fieldNames
  ) {
    return this.isAllowed(
      Operation.READ,
      objectType,
      this.toFields(objectType, fieldNames)
    );
  }

  /**
   * @description Throws unless the current user can read records of this sObject.
   * @param objectType The sObject to check.
   */
  public void checkRead(Schema.SObjectType objectType) {
    this.check(Operation.READ, objectType, new List<Schema.SObjectField>());
  }

  /**
   * @description Throws unless the current user can read records of this sObject and see all of
   * these fields. The exception names the object or the first field that failed.
   * @param objectType The sObject to check.
   * @param fields The fields the user needs to be able to see.
   */
  public void checkRead(
    Schema.SObjectType objectType,
    List<Schema.SObjectField> fields
  ) {
    this.check(Operation.READ, objectType, fields);
  }

  /**
   * @description Throws unless the current user can read records of this sObject and see all of
   * these fields, named by API name.
   * @param objectType The sObject to check.
   * @param fieldNames The API names of the fields the user needs to be able to see.
   */
  public void checkRead(
    Schema.SObjectType objectType,
    List<String> fieldNames
  ) {
    this.check(
      Operation.READ,
      objectType,
      this.toFields(objectType, fieldNames)
    );
  }

  /**
   * @description Whether the current user can update records of this sObject.
   * @param objectType The sObject to check.
   * @return True if the user can update records of this sObject.
   */
  public Boolean canUpdate(Schema.SObjectType objectType) {
    return this.isObjectAllowed(Operation.MODIFY, objectType);
  }

  /**
   * @description Whether the current user can update records of this sObject and write all of
   * these fields.
   * @param objectType The sObject to check.
   * @param fields The fields the user needs to be able to write.
   * @return True if the user can update the sObject and write every field.
   */
  public Boolean canUpdate(
    Schema.SObjectType objectType,
    List<Schema.SObjectField> fields
  ) {
    return this.isAllowed(Operation.MODIFY, objectType, fields);
  }

  /**
   * @description Whether the current user can update records of this sObject and write all of
   * these fields, named by API name.
   * @param objectType The sObject to check.
   * @param fieldNames The API names of the fields the user needs to be able to write.
   * @return True if the user can update the sObject and write every field.
   */
  public Boolean canUpdate(
    Schema.SObjectType objectType,
    List<String> fieldNames
  ) {
    return this.isAllowed(
      Operation.MODIFY,
      objectType,
      this.toFields(objectType, fieldNames)
    );
  }

  /**
   * @description Throws unless the current user can update records of this sObject.
   * @param objectType The sObject to check.
   */
  public void checkUpdate(Schema.SObjectType objectType) {
    this.check(Operation.MODIFY, objectType, new List<Schema.SObjectField>());
  }

  /**
   * @description Throws unless the current user can update records of this sObject and write all
   * of these fields. The exception names the object or the first field that failed.
   * @param objectType The sObject to check.
   * @param fields The fields the user needs to be able to write.
   */
  public void checkUpdate(
    Schema.SObjectType objectType,
    List<Schema.SObjectField> fields
  ) {
    this.check(Operation.MODIFY, objectType, fields);
  }

  /**
   * @description Throws unless the current user can update records of this sObject and write all
   * of these fields, named by API name.
   * @param objectType The sObject to check.
   * @param fieldNames The API names of the fields the user needs to be able to write.
   */
  public void checkUpdate(
    Schema.SObjectType objectType,
    List<String> fieldNames
  ) {
    this.check(
      Operation.MODIFY,
      objectType,
      this.toFields(objectType, fieldNames)
    );
  }

  /**
   * @description Whether the current user can delete records of this sObject. Deleting is an
   * all-or-nothing operation on the whole record, so there is no field-level equivalent.
   * @param objectType The sObject to check.
   * @return True if the user can delete records of this sObject.
   */
  public Boolean canDelete(Schema.SObjectType objectType) {
    return this.isObjectAllowed(Operation.DEL, objectType);
  }

  /**
   * @description Throws unless the current user can delete records of this sObject.
   * @param objectType The sObject to check.
   */
  public void checkDelete(Schema.SObjectType objectType) {
    this.check(Operation.DEL, objectType, new List<Schema.SObjectField>());
  }

  /**
   * @description Whether the operation is allowed on the object and on every one of the fields.
   * The object is checked first, because a user who cannot touch the object at all cannot touch
   * any of its fields either.
   * @param operation The operation being checked.
   * @param objectType The sObject to check.
   * @param fields The fields to check. An empty list checks only the object.
   * @return True if the object and every field allow the operation.
   */
  private Boolean isAllowed(
    Operation operation,
    Schema.SObjectType objectType,
    List<Schema.SObjectField> fields
  ) {
    if (!this.isObjectAllowed(operation, objectType)) {
      return false;
    }
    for (Schema.SObjectField field : fields) {
      if (!this.isFieldAllowed(operation, field)) {
        return false;
      }
    }
    return true;
  }

  /**
   * @description The throwing counterpart of `isAllowed`. Stops at the first failure and names it,
   * so the message points at one specific thing to grant rather than at the whole call.
   * @param operation The operation being checked.
   * @param objectType The sObject to check.
   * @param fields The fields to check. An empty list checks only the object.
   */
  private void check(
    Operation operation,
    Schema.SObjectType objectType,
    List<Schema.SObjectField> fields
  ) {
    if (!this.isObjectAllowed(operation, objectType)) {
      throw new ObjectSecurityException(
        'You do not have permission to ' +
          VERB_BY_OPERATION.get(operation) +
          ' ' +
          String.valueOf(objectType) +
          ' records.'
      );
    }
    for (Schema.SObjectField field : fields) {
      if (!this.isFieldAllowed(operation, field)) {
        throw new ObjectSecurityException(
          'You do not have permission to ' +
            VERB_BY_OPERATION.get(operation) +
            ' the ' +
            String.valueOf(objectType) +
            '.' +
            String.valueOf(field) +
            ' field.'
        );
      }
    }
  }

  /**
   * @description Maps an operation onto the matching object describe check. This is the one place
   * that knows `CREATE` means `isCreateable()` and `READ` means `isAccessible()`.
   * @param operation The operation being checked.
   * @param objectType The sObject to check.
   * @return True if the user's object permissions allow the operation.
   */
  private Boolean isObjectAllowed(
    Operation operation,
    Schema.SObjectType objectType
  ) {
    Schema.DescribeSObjectResult describe = objectType.getDescribe();
    switch on operation {
      when CREATE {
        return describe.isCreateable();
      }
      when READ {
        return describe.isAccessible();
      }
      when MODIFY {
        return describe.isUpdateable();
      }
      when else {
        return describe.isDeletable();
      }
    }
  }

  /**
   * @description Maps an operation onto the matching field describe check. Deleting has no
   * field-level equivalent - you delete a whole record - so `DEL` never reaches this method.
   * @param operation The operation being checked.
   * @param field The field to check.
   * @return True if the user's field-level security allows the operation.
   */
  private Boolean isFieldAllowed(
    Operation operation,
    Schema.SObjectField field
  ) {
    Schema.DescribeFieldResult describe = field.getDescribe();
    switch on operation {
      when CREATE {
        return describe.isCreateable();
      }
      when MODIFY {
        return describe.isUpdateable();
      }
      when else {
        return describe.isAccessible();
      }
    }
  }

  /**
   * @description Resolves field API names into field tokens, so the rest of the class only ever
   * deals in tokens. A name that isn't on the object throws instead of being skipped: field lists
   * usually come from configuration, and a typo there would otherwise look like a passing check.
   * @param objectType The sObject the fields belong to.
   * @param fieldNames The API names to resolve, matched case-insensitively.
   * @return The matching field tokens, in the order the names were given.
   */
  private List<Schema.SObjectField> toFields(
    Schema.SObjectType objectType,
    List<String> fieldNames
  ) {
    // The map this returns is keyed case-insensitively, so callers can pass field names in
    // whatever case their configuration happens to store them in.
    Map<String, Schema.SObjectField> fieldsByName = objectType.getDescribe()
      .fields.getMap();
    List<Schema.SObjectField> fields = new List<Schema.SObjectField>();
    for (String fieldName : fieldNames) {
      Schema.SObjectField field = fieldsByName.get(fieldName);
      if (field == null) {
        throw new ObjectSecurityException(
          String.valueOf(objectType) + ' has no field named ' + fieldName + '.'
        );
      }
      fields.add(field);
    }
    return fields;
  }

  /**
   * @description Thrown when the current user is missing object permissions or field-level
   * security that a `checkX` method required.
   */
  public class ObjectSecurityException extends Exception {
  }
}
