@IsTest(isParallel=true)
private class CustomPermissionsTest {
  private static final String GRANTED = 'Granted_Permission';
  private static final String NOT_GRANTED = 'Not_Granted_Permission';

  @IsTest
  private static void getInstanceShouldReturnTheSameInstanceEveryTime() {
    System.Assert.areEqual(
      CustomPermissions.getInstance(),
      CustomPermissions.getInstance(),
      'getInstance should hand back one shared instance'
    );
  }

  @IsTest
  private static void getInstanceShouldReturnWhateverWasInstalledInItsPlace() {
    // This is the seam `Mock.of(CustomPermissions.class)` uses. Asserting it with a plain
    // instance keeps this package free of any dependency on the test-mocks package.
    CustomPermissions replacement = new StubbedPermissions();
    CustomPermissions.instance = replacement;

    System.Assert.areEqual(
      replacement,
      CustomPermissions.getInstance(),
      'A test should be able to put its own instance in place of the shared one'
    );
  }

  @IsTest
  private static void hasShouldBeFalseForAPermissionThatDoesNotExist() {
    System.Assert.isFalse(
      CustomPermissions.getInstance()
        .has('This_Custom_Permission_Does_Not_Exist'),
      'An unknown permission name should deny rather than throw, so a typo cannot grant access'
    );
  }

  @IsTest
  private static void hasShouldReflectWhetherThePermissionWasGranted() {
    CustomPermissions permissions = new StubbedPermissions();

    System.Assert.isTrue(
      permissions.has(GRANTED),
      'A granted permission should read as true'
    );
    System.Assert.isFalse(
      permissions.has(NOT_GRANTED),
      'A permission that was not granted should read as false'
    );
  }

  @IsTest
  private static void hasAllShouldBeTrueOnlyWhenEveryPermissionWasGranted() {
    CustomPermissions permissions = new StubbedPermissions();

    System.Assert.isTrue(
      permissions.hasAll(new List<String>{ GRANTED }),
      'Every permission in the list was granted'
    );
    System.Assert.isFalse(
      permissions.hasAll(new List<String>{ GRANTED, NOT_GRANTED }),
      'One missing permission should fail the whole check'
    );
  }

  @IsTest
  private static void hasAllShouldBeTrueForAnEmptyList() {
    System.Assert.isTrue(
      new StubbedPermissions().hasAll(new List<String>()),
      'An empty list asks for nothing, and so is satisfied'
    );
  }

  @IsTest
  private static void hasAnyShouldBeTrueWhenAtLeastOnePermissionWasGranted() {
    CustomPermissions permissions = new StubbedPermissions();

    System.Assert.isTrue(
      permissions.hasAny(new List<String>{ NOT_GRANTED, GRANTED }),
      'One granted permission is enough'
    );
    System.Assert.isFalse(
      permissions.hasAny(new List<String>{ NOT_GRANTED }),
      'No granted permissions means no match'
    );
  }

  @IsTest
  private static void hasAnyShouldBeFalseForAnEmptyList() {
    System.Assert.isFalse(
      new StubbedPermissions().hasAny(new List<String>()),
      'An empty list offers nothing to match, and so is not satisfied'
    );
  }

  @IsTest
  private static void checkShouldNotThrowForAGrantedPermission() {
    Test.startTest();
    new StubbedPermissions().check(GRANTED);
    new StubbedPermissions().checkAll(new List<String>{ GRANTED });
    Test.stopTest();

    System.Assert.isTrue(true, 'A granted permission should pass silently');
  }

  @IsTest
  private static void checkShouldThrowAndNameTheMissingPermission() {
    Test.startTest();
    Exception caught;
    try {
      new StubbedPermissions().check(NOT_GRANTED);
    } catch (CustomPermissions.CustomPermissionsException e) {
      caught = e;
    }
    Test.stopTest();

    System.Assert.isNotNull(caught, 'A missing permission should throw');
    System.Assert.isTrue(
      caught.getMessage().contains(NOT_GRANTED),
      'The message should name the permission the user is missing: ' +
      caught.getMessage()
    );
  }

  @IsTest
  private static void checkAllShouldThrowOnTheFirstMissingPermission() {
    Test.startTest();
    Exception caught;
    try {
      new StubbedPermissions()
        .checkAll(new List<String>{ GRANTED, NOT_GRANTED });
    } catch (CustomPermissions.CustomPermissionsException e) {
      caught = e;
    }
    Test.stopTest();

    System.Assert.isNotNull(
      caught,
      'One missing permission should fail the whole check'
    );
    System.Assert.isTrue(
      caught.getMessage().contains(NOT_GRANTED),
      'The message should name the one that was missing, not the one that passed: ' +
      caught.getMessage()
    );
  }

  /**
   * Answers as though the running user had been granted exactly one custom permission. Overriding
   * `has` is the only way to exercise the "granted" path, since a test cannot grant the running
   * user a real custom permission.
   */
  private class StubbedPermissions extends CustomPermissions {
    public override Boolean has(String permissionName) {
      return permissionName == GRANTED;
    }
  }
}
