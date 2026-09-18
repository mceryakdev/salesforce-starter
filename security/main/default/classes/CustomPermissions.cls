/**
 * @description Checks which custom permissions the current user has been granted.
 *
 * Custom permissions are the answer to "is this user allowed to do this *thing*", where the thing
 * isn't an object or a record - approving a discount, running a recalculation, seeing an internal
 * cost field. An admin grants them through permission sets, so the rule can move between users
 * without a code change.
 *
 * ```
 * if (CustomPermissions.getInstance().has('Approve_Large_Discounts')) {
 *     // ...
 * }
 *
 * CustomPermissions.getInstance().check('Approve_Large_Discounts');
 * ```
 *
 * `has` returns a Boolean; `check` throws a `CustomPermissionsException` naming the permission. Pass
 * the permission's API name, not its label.
 *
 * A name that doesn't match any custom permission in the org comes back as `false` rather than as an
 * error, so a typo reads as "this user doesn't have it". That fails safe - nobody is accidentally
 * granted anything - but it does mean a misspelled name will quietly deny everyone, so it is worth
 * checking the spelling when a permission seems to have no effect.
 *
 * These are instance methods reached through `getInstance()` so that a test can replace the instance
 * with a mock and exercise both the granted and the not-granted path without assigning permission
 * sets:
 *
 * ```
 * Mock mockPermissions = Mock.of(CustomPermissions.class).returns('has', true);
 * CustomPermissions.instance = (CustomPermissions) mockPermissions.instance();
 * ```
 */
public inherited sharing virtual class CustomPermissions {
	@TestVisible
	private static CustomPermissions instance;

	/**
	 * @description Returns the shared `CustomPermissions`, creating it if it doesn't exist yet.
	 * Reach for this rather than `new CustomPermissions()` in code you intend to unit test, so that
	 * a test can put a mock in its place.
	 * @return The shared `CustomPermissions`.
	 */
	public static CustomPermissions getInstance() {
		if (CustomPermissions.instance == null) {
			CustomPermissions.instance = new CustomPermissions();
		}
		return CustomPermissions.instance;
	}

	/**
	 * @description Whether the current user has this custom permission.
	 *
	 * This is the only method that consults the platform, and every other method here goes through
	 * it - which is why it is `virtual`. There is no way to grant the running user a custom
	 * permission from inside a test, so overriding this one method is how a test covers the
	 * "granted" path without an org that has particular permission sets in it.
	 * @param permissionName The API name of the custom permission.
	 * @return True if the user has been granted it.
	 */
	public virtual Boolean has(String permissionName) {
		return FeatureManagement.checkPermission(permissionName);
	}

	/**
	 * @description Whether the current user has every one of these custom permissions. An empty list
	 * asks for nothing, and so is satisfied.
	 * @param permissionNames The API names of the custom permissions.
	 * @return True if the user has been granted all of them.
	 */
	public Boolean hasAll(List<String> permissionNames) {
		for (String permissionName : permissionNames) {
			if (!this.has(permissionName)) {
				return false;
			}
		}
		return true;
	}

	/**
	 * @description Whether the current user has at least one of these custom permissions. An empty
	 * list offers nothing to match, and so is not satisfied.
	 * @param permissionNames The API names of the custom permissions.
	 * @return True if the user has been granted any of them.
	 */
	public Boolean hasAny(List<String> permissionNames) {
		for (String permissionName : permissionNames) {
			if (this.has(permissionName)) {
				return true;
			}
		}
		return false;
	}

	/**
	 * @description Throws unless the current user has this custom permission.
	 * @param permissionName The API name of the custom permission.
	 */
	public void check(String permissionName) {
		if (!this.has(permissionName)) {
			throw new CustomPermissionsException(
				'You do not have the ' + permissionName + ' custom permission.'
			);
		}
	}

	/**
	 * @description Throws unless the current user has every one of these custom permissions. The
	 * exception names the first one they are missing.
	 * @param permissionNames The API names of the custom permissions.
	 */
	public void checkAll(List<String> permissionNames) {
		for (String permissionName : permissionNames) {
			this.check(permissionName);
		}
	}

	/**
	 * @description Thrown when the current user does not have a custom permission that a `check`
	 * method required.
	 */
	public class CustomPermissionsException extends Exception {
	}
}
