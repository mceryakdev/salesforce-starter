# Salesforce Trigger Framework Starter

A foundation for Apex trigger work that keeps business logic out of DML plumbing. It builds on two
established open-source unlocked packages -
[Trigger Actions Framework](https://github.com/mitchspano/trigger-actions-framework) for trigger
dispatch and [Nebula Logger](https://github.com/jongpie/NebulaLogger) for observability - and adds
four small packages that connect them, make the result easy to test, and show what using all of it
together actually looks like.

| Package         | What it gives you                                                                                             |
| --------------- | ---------------------------------------------------------------------------------------------------------------- |
| `unit-of-work/` | Register DML as you go, commit it once, all-or-nothing. Trigger-agnostic - usable from any Apex.               |
| `taf-ext/`      | Wires the Unit of Work into Trigger Actions Framework, committing once at the true end of a trigger run.       |
| `test-mocks/`   | A tiny Stub API mocking utility so you can test what your code *registered* instead of what the database did.  |
| `example/`      | A working trigger built on all three, showing the intended patterns end to end. Optional - see below.          |
| `force-app/`    | Default package directory for your own org-specific metadata.                                                  |

---

## Why each package exists

### `unit-of-work` - because scattered DML is where trigger logic goes wrong

Apex that performs DML wherever it happens to need it runs into three problems, and all three get
worse as more automation is added to an object:

1. **Governor limits.** Five Trigger Actions each calling `insert` is five DML statements against a
   limit of 150 - and each one can cascade into more triggers.
2. **Partial failures.** If action A inserts Tasks and action B then throws, the Tasks are already
   committed. You're left with half-applied state unless every caller manages its own savepoint.
3. **Ordering and Ids.** A child record can't reference a parent that hasn't been inserted yet, so
   callers end up sequencing DML by hand and threading Ids through their logic.

`UnitOfWork` turns DML into a two-phase operation: *register intent* as your logic runs, then
*commit once* at the end. That gives you one DML statement per sObject type, a single savepoint
around the whole commit so any failure rolls back everything, parents inserted before children
(and deleted after them), and `registerRelationship` to populate a lookup with an Id that doesn't
exist yet at registration time.

The payoff is that business logic stops caring about DML mechanics. A Trigger Action says *what*
should happen; the Unit of Work decides *when* and *in what order* it actually hits the database.

### `taf-ext` - because someone has to commit at exactly the right moment

Trigger Actions Framework handles dispatch beautifully: metadata-driven ordering, per-action
bypasses, Apex and Flow actions. What it doesn't do is decide when a shared Unit of Work should be
committed - and that turns out to be a genuinely hard moment to find.

Committing at the end of `afterInsert` is wrong: that commit fires more triggers, which run more
Trigger Actions, which register more work on a Unit of Work nobody will commit. Committing in every
context is wrong for the same reason, plus it multiplies DML. What you want is the *true* end of the
trigger run - after every before/after context has fired, including recursive re-entry caused by the
same top-level DML statement.

`TriggerBase` already tracks that moment (it maintains a context stack and counts remaining DML
rows) and exposes it as `finalizeDmlOperation()`. `MetadataTriggerHandler` can't be subclassed, so
`UOWMetadataTriggerHandler` implements the Trigger Action interfaces itself and forwards every
call to an internal `MetadataTriggerHandler` - none of the metadata-driven dispatch, bypass, or
permission behavior changes - while overriding `finalizeDmlOperation()` to commit the Unit of Work
and flush the log buffer exactly once.

### `test-mocks` - because asserting on the database is a slow way to test logic

The natural way to test a Trigger Action is to insert records, let the trigger fire, and query the
results back. That works, but it's slow (every test pays for DML), and it tests the whole stack when
you only wanted to test one class's decision-making. It also gets ambiguous once several pieces of
automation touch the same records.

`test-mocks` swaps the Unit of Work for a stand-in that records calls instead of performing them, so
a test can assert *"this action registered exactly these two Tasks"* directly. No DML, no SOQL, and
a failure points at the class you were actually testing.

It's built on Salesforce's built-in Stub API rather than a full mocking library, which keeps it to
two small classes, needs no interfaces, and requires no changes to the code being mocked.

### `example` - because reading about a pattern and using it correctly are different skills

The other three packages are described above in isolation. `example` is a real, deployable
`AccountTrigger` built on all of them together, on the theory that a working example answers
questions a description can't: what does a `before insert` action look like when it needs no Unit
of Work at all? How do you point a new Case at a new Contact that doesn't have an Id yet? Where does
the line actually fall between "test this with a mock" and "test this with a real trigger"?

It's deliberately small - one object, two Trigger Actions, one relationship - so the whole thing can
be read in a few minutes rather than studied. See [Example: a full walkthrough](#example-a-full-walkthrough)
below for what it does and why it's built the way it is.

**This package is entirely optional and safe to delete.** It exists only to demonstrate the other
three; nothing in `unit-of-work`, `taf-ext`, or `test-mocks` depends on it. More importantly, once
deployed it installs a real, unconditionally active trigger on the standard Account object - see the
warning under the walkthrough before deploying it into any org that isn't dedicated to trying it out.

---

## Setup

### 1. Install the two unlocked packages in your org

Both are open-source unlocked packages with no namespace. Install them before deploying anything
from this repo. (For a sandbox, swap `login.salesforce.com` for `test.salesforce.com`.)

| Package                                                                          | Version    | Install link                                                                        |
| -------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------ |
| [Trigger Actions Framework](https://github.com/mitchspano/trigger-actions-framework) | `0.3.4.1`  | https://login.salesforce.com/packaging/installPackage.apexp?p0=04tKY000000R0yHYAS |
| [Nebula Logger](https://github.com/jongpie/NebulaLogger)                           | `4.19.5.1` | https://login.salesforce.com/packaging/installPackage.apexp?p0=04tg7000000IzRdAAK |

Each project documents its own post-install configuration - permission sets, `LoggerSettings__c`,
`Trigger_Action__mdt`, and so on. That isn't repeated here; follow their docs.

### 2. Deploy this repo's packages

```bash
sf project deploy start \
  --source-dir unit-of-work --source-dir taf-ext --source-dir test-mocks \
  --target-org <your-org-or-alias>
```

Each package also has its own manifest, if you'd rather deploy them one at a time:

```bash
sf project deploy start --manifest unit-of-work/manifest/package.xml --target-org <your-org-or-alias>
sf project deploy start --manifest taf-ext/manifest/package.xml      --target-org <your-org-or-alias>
sf project deploy start --manifest test-mocks/manifest/package.xml   --target-org <your-org-or-alias>
```

Deploy order matters if you split them up. `unit-of-work` stands alone; both `taf-ext` and
`test-mocks` reference `UnitOfWork`, so it goes first.

### 3. Optional: deploy the `example` package

```bash
sf project deploy start --manifest example/manifest/package.xml --target-org <your-org-or-alias>
```

Deploy this into a scratch org or a sandbox set aside for trying the pattern out - not into a shared
dev org that already runs its own automation on Account, or that hosts the other packages' test
suites. See [Example: a full walkthrough](#example-a-full-walkthrough) for why, and how to remove it
again if you deploy it somewhere you'd rather it not be.

### 4. Optional: retrieve the packages locally for reference

Neither unlocked package's source is committed here - each has its own upstream repo, and Nebula
Logger alone is over a thousand components. If you want a local read-only copy to browse while
working, retrieve it from an org that has them installed:

```bash
mkdir -p unlocked
sf project retrieve start --target-org <your-org-or-alias> --package-name "Trigger Actions Framework"
sf project retrieve start --target-org <your-org-or-alias> --package-name "Nebula Logger - Unlocked Package"
mv "Trigger Actions Framework" "Nebula Logger - Unlocked Package" unlocked/
```

`unlocked/` is listed in both `.gitignore` and `.forceignore`, so anything you retrieve there stays
local: it won't be committed, and it can't be deployed even if you target it explicitly. Treat it as
read-only - it's a mirror of what's installed, not source.

---

## Usage

### `UnitOfWork` on its own

Nothing about it is trigger-specific. Create one, register work, commit:

```apex
UnitOfWork uow = new UnitOfWork();

Account account = new Account(Name = 'Acme');
Contact contact = new Contact(LastName = 'Coyote');

uow.registerNew(account);
uow.registerNew(contact);
uow.registerRelationship(contact, Contact.AccountId, account);

uow.commitWork();
```

The Contact's `AccountId` is populated automatically, after the Account is inserted and has an Id,
but before the Contact is. Two DML statements total, and if either fails, both roll back.

When several classes contribute to the same piece of work without passing an instance around, use
the ambient instance instead:

```apex
UnitOfWork.getCurrent().registerNew(new Task(Subject = 'Follow up'));
// ... other classes register more work on the same instance ...
UnitOfWork.commitCurrent();
```

`registerDirty` and `registerDeleted` round it out. Registering the same record Id as dirty more
than once merges the populated fields into a single `update` - so two classes can each set a
different field on the same record without clobbering each other.

### `taf-ext` in a trigger

Use `UOWMetadataTriggerHandler` where you'd normally use `MetadataTriggerHandler`:

```apex
trigger AccountTrigger on Account(
	before insert, after insert, before update, after update,
	before delete, after delete, after undelete
) {
	new UOWMetadataTriggerHandler().run();
}
```

Everything else stays the same - `Trigger_Action__mdt` records, `sObject_Trigger_Setting__mdt`,
bypasses, Flow actions - because the handler forwards every call to a `MetadataTriggerHandler`
internally.

Your Trigger Actions then register work instead of performing DML:

```apex
public with sharing class CreateOnboardingTask implements TriggerAction.AfterInsert {
	public void afterInsert(List<SObject> triggerNew) {
		for (Account account : (List<Account>) triggerNew) {
			UnitOfWork.getCurrent()
				.registerNew(
					new Task(
						WhatId = account.Id,
						Subject = 'Onboard ' + account.Name,
						ActivityDate = System.today().addDays(7)
					)
				);
		}
	}
}
```

Note what isn't there: no `insert`, no bulkification bookkeeping, no savepoint. Ten Trigger Actions
written this way still produce one `insert` per sObject type for the entire trigger run.

### `test-mocks` to test that action

Because the action reaches the Unit of Work through `UnitOfWork.getCurrent()`, a test can put a
recording stand-in in its place and assert on what was registered:

```apex
@IsTest
private static void shouldRegisterAnOnboardingTaskForEachAccount() {
	MockUnitOfWork mockUow = MockUnitOfWork.install();
	List<Account> accounts = new List<Account>{
		new Account(Name = 'Acme'),
		new Account(Name = 'Initech')
	};

	new CreateOnboardingTask().afterInsert(accounts);

	List<SObject> registered = mockUow.registeredNew();
	System.Assert.areEqual(2, registered.size(), 'One Task per Account');
	System.Assert.areEqual('Onboard Acme', ((Task) registered[0]).Subject);
}
```

No DML and no SOQL, so it runs in milliseconds and fails for exactly one reason: the action
registered the wrong thing.

`MockUnitOfWork` covers the common cases - `registeredNew()`, `registeredDirty()`,
`registeredDeleted()`, and `wasCommitted()`. For anything else, `calls()` returns the underlying
generic mock:

```apex
mockUow.calls().assertCalledOnce('registerRelationship');
List<Object> arguments = mockUow.calls().argumentsOf('registerRelationship');
```

That generic mock works on any class, not just this one:

```apex
Mock mock = Mock.of(RatingService.class);
mock.returns('findRating', 'Hot');

String rating = ((RatingService) mock.instance()).findRating(accountId);

System.Assert.areEqual('Hot', rating, 'The mock should return the configured value');
mock.assertCalledOnce('findRating');
```

Two things to know about it. Method names are matched case-insensitively and overloads are recorded
together, so `registerNew(SObject)` and `registerNew(List<SObject>)` both count as `registerNew`.
And because the stand-in replaces the whole object, a method that would normally call another method
on itself doesn't - each call is intercepted on its own and the real body never runs. Salesforce's
Stub API also can't intercept `static` or `private` methods, which is why `MockUnitOfWork.install()`
works by assigning the mock to the field `UnitOfWork.getCurrent()` reads from.

### How it fits together

```
AccountTrigger
  └─ UOWMetadataTriggerHandler.run()
       ├─ forwards each context to MetadataTriggerHandler
       │    └─ your Trigger Actions → UnitOfWork.getCurrent().registerNew(...)
       └─ finalizeDmlOperation()          ← runs once, at the true end of the run
            ├─ UnitOfWork.commitCurrent()  → one DML statement per sObject type
            ├─ DmlFinalizers
            └─ Logger.saveLog()            → flushes everything buffered during the run
```

In tests, `MockUnitOfWork.install()` replaces the target of that `getCurrent()` call, so the same
Trigger Action can be tested without any of the machinery below it running.

---

## Example: a full walkthrough

`example/main/default/` wires everything above into one real trigger on Account:

| File                                | Role                                                                                          |
| ------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `triggers/AccountTrigger.trigger`   | One line: `new UOWMetadataTriggerHandler().run();`. Every context is listed; nothing else lives here. |
| `classes/SetDefaultAccountRating`   | `before insert` - defaults `Rating` when it's blank.                                          |
| `classes/CreateOnboardingRecords`   | `after insert` - registers a primary Contact and an onboarding Case per Account.               |
| `customMetadata/*.md-meta.xml`      | The `Trigger_Action__mdt` and `sObject_Trigger_Setting__mdt` records that wire the two classes above into the contexts they need, with no code change to `AccountTrigger` itself. |

### The two actions show the two shapes a Trigger Action takes

`SetDefaultAccountRating` needs no Unit of Work at all: in a `before insert` context, the records in
`triggerNew` *are* the ones about to be written, so mutating a field on them is the entire operation.
Registering them for update would be wrong - it would write the same records a second time.

`CreateOnboardingRecords` needs the Unit of Work because it touches *other* records, and it's the one
worth reading closely: the Contact's `AccountId` is set directly (the Account already has an Id by
`after insert`), but the Case's `ContactId` can't be - the Contact doesn't have an Id yet either. That's
what `registerRelationship(case, Case.ContactId, contact)` is for: it records the intent, and the Unit
of Work fills in the real Id once the Contact is inserted and before the Case is - both in the same two
DML statements the Unit of Work would have used anyway, whether this ran for one Account or two hundred.

### The tests show where the line falls between "mock it" and "run it for real"

Three test classes, three different jobs:

- **`SetDefaultAccountRatingTest`** calls `beforeInsert(...)` directly on an in-memory list. No
  trigger, no CMDT, no DML - a `before insert` action just mutates records, so a test for one just
  checks the records.
- **`CreateOnboardingRecordsTest`** calls `afterInsert(...)` directly with `MockUnitOfWork` installed,
  and asserts on what got registered - the Contact's fields, the Case's fields, and the exact
  `registerRelationship` arguments - covering blank input, bulk (200 Accounts), and that the action
  never calls `commitWork()` itself (that's the handler's job, not the action's).
- **`AccountTriggerTest`** is the odd one out, on purpose: it performs one real `insert` - unavoidable,
  since there's no way to invoke a `.trigger` file except through the DML that fires it - but asserts
  nothing about what either action did. `MockUnitOfWork.wasCommitted()` is `true` only if
  `UOWMetadataTriggerHandler.finalizeDmlOperation()` ran to completion, which only happens if the
  trigger correctly dispatched to it - so that one assertion proves the *wiring* (trigger → CMDT →
  handler) without re-testing either action's logic, which the two classes above already cover.

That split is deliberate: business rules get fast, mocked, exhaustive unit tests; the trigger itself
gets one thin test that would fail if the CMDT configuration pointed at the wrong handler, and nothing
else. Re-asserting Rating values or Case counts in `AccountTriggerTest` would just test the same logic
twice, through a slower path, and leave it unclear which test to fix when something breaks.

### This installs a real, always-on trigger - read this before deploying it anywhere shared

Once deployed, `AccountTrigger` runs for **every** insert, update, delete, and undelete on the standard
Account object in that org - not just from this demo, from anything. This isn't a hypothetical
warning: while building this example, deploying it into the same org already running `unit-of-work`'s
own test suite broke five unrelated `UnitOfWorkTest` tests. Those tests insert a plain Account and
later delete it; with `AccountTrigger` live, that insert also created a real Case, and Salesforce
refuses to delete an Account with an open Case attached. (The fix that keeps `UnitOfWorkTest` safe
regardless of what automation exists in a given org is in the test file itself -
`bypassAmbientTriggers()` - and it's worth reading as its own small example of defensive test design:
a package that claims to work in any org should not assume the org has no other automation on the
objects its tests happen to use.)

Deploy `example` into a scratch org, or a sandbox set aside for trying it out - not into a shared dev
org, and not into any org whose existing Account automation or tests you'd rather not interact with.

If you've already deployed it somewhere you'd rather it not be, in order from lightest to heaviest:

1. **Turn off just the actions, keep the trigger inert.** Set `Bypass_Execution__c` to `true` on the
   two `Trigger_Action__mdt` records (`Account_Set_Default_Rating`, `Account_Create_Onboarding_Records`)
   in Setup, or by editing and redeploying the `customMetadata/*.md-meta.xml` files. The trigger still
   fires and still commits an (empty) Unit of Work, but neither action runs.
2. **Bypass it for one transaction.** `TriggerBase.bypass('Account');` ... `TriggerBase.clearBypass('Account');`
   around the code you're running - useful in a one-off script or a test that can't avoid touching
   Account, not a permanent fix.
3. **Remove it entirely.**
   ```bash
   sf project delete source --metadata ApexTrigger:AccountTrigger --target-org <your-org-or-alias>
   ```
   or delete the `example/` directory from your own copy of this repo if you don't want it at all.

---

## Logging

Both `unit-of-work` and `taf-ext` call Nebula Logger directly, so it must be installed wherever they
are deployed.

- `UnitOfWork.commitWork()` buffers a `FINE` summary of what's about to be committed, and on failure
  logs an `ERROR` with the full exception, saves it immediately, and rethrows the original exception
  unchanged. Because that entry is published as a platform event, it survives the rollback that just
  happened - the DML disappears, the record of why does not.
- `UOWMetadataTriggerHandler.finalizeDmlOperation()` logs an `ERROR` if a `DmlFinalizer` throws,
  buffers a `FINE` entry when the run finishes cleanly, and always flushes the buffer in a `finally`
  block, so entries buffered by any Trigger Action during the run are saved either way.

`FINE` entries cost nothing in production, where `LoggerSettings__c.LoggingLevel__c` is typically set
to `ERROR` or `WARN` - turn the level up when you need to trace a transaction.

## Testing

```bash
sf apex run test --target-org <your-org-or-alias> \
  --class-names UnitOfWorkTest --class-names UOWMetadataTriggerHandlerTest \
  --class-names MockTest --class-names MockUnitOfWorkTest \
  --code-coverage
```

66 tests across the three core packages, with `UnitOfWork` and `UOWMetadataTriggerHandler` both at
100% coverage - including bulk (200-record) registration, dirty-record merging, empty-list edge
cases, rollback behavior, and the log entries produced on the success and failure paths. The `Mock`
classes are `@IsTest`, so they are excluded from coverage by design.

If you've deployed `example` too, add its test classes to the same run:

```bash
sf apex run test --target-org <your-org-or-alias> \
  --class-names UnitOfWorkTest --class-names UOWMetadataTriggerHandlerTest \
  --class-names MockTest --class-names MockUnitOfWorkTest \
  --class-names SetDefaultAccountRatingTest --class-names CreateOnboardingRecordsTest \
  --class-names AccountTriggerTest \
  --code-coverage
```

80 tests total, with all five production classes (`UnitOfWork`, `UOWMetadataTriggerHandler`,
`SetDefaultAccountRating`, `CreateOnboardingRecords`, `AccountTrigger`) at 100% coverage.

## Prerequisites for local development

- **Salesforce CLI** - [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli)
- **VS Code with the Salesforce Extension Pack** - [installation instructions](https://developer.salesforce.com/docs/platform/sfvscode-extensions/guide/install.html)
- **A development org** with the two unlocked packages above installed
