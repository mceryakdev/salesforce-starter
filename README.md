# Salesforce Trigger Framework Starter

A foundation for Apex trigger work that keeps business logic out of DML plumbing. It builds on two
established open-source unlocked packages -
[Trigger Actions Framework](https://github.com/mitchspano/trigger-actions-framework) for trigger
dispatch and [Nebula Logger](https://github.com/jongpie/NebulaLogger) for observability - and adds
three small packages that connect them and make the result easy to test.

| Package         | What it gives you                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------------ |
| `unit-of-work/` | Register DML as you go, commit it once, all-or-nothing. Trigger-agnostic - usable from any Apex.              |
| `taf-ext/`      | Wires the Unit of Work into Trigger Actions Framework, committing once at the true end of a trigger run.      |
| `test-mocks/`   | A tiny Stub API mocking utility so you can test what your code *registered* instead of what the database did. |
| `force-app/`    | Default package directory for your own org-specific metadata.                                                 |

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

### 3. Optional: retrieve the packages locally for reference

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

62 tests, with `UnitOfWork` and `UOWMetadataTriggerHandler` both at 100% coverage - including
bulk (200-record) registration, dirty-record merging, empty-list edge cases, rollback behavior, and
the log entries produced on the success and failure paths. The `Mock` classes are `@IsTest`, so they
are excluded from coverage by design.

## Prerequisites for local development

- **Salesforce CLI** - [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli)
- **VS Code with the Salesforce Extension Pack** - [installation instructions](https://developer.salesforce.com/docs/platform/sfvscode-extensions/guide/install.html)
- **A development org** with the two unlocked packages above installed
