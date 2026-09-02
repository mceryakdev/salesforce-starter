# Salesforce Trigger Framework Starter

A small Salesforce Apex foundation for trigger handling, batched DML, and observability. It builds
on top of two existing open-source unlocked packages -
[Trigger Actions Framework](https://github.com/mitchspano/trigger-actions-framework) and
[Nebula Logger](https://github.com/jongpie/NebulaLogger) - and adds two more source packages of
its own: `unit-of-work` and `taf-ext`. This repo, and those two packages, are open source.

## What's in this repo

| Directory        | What it is                                                                                                                                                                          | Deploy it?                                          |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------- |
| `unlocked/`       | Reference-only copies of the two unlocked packages this project depends on, retrieved from an org for local browsing.                                                                | **No** - excluded via `.forceignore`. Don't edit these; they're not source, they're a read-only mirror of what's installed. |
| `unit-of-work/`   | A small, trigger-agnostic Unit of Work for batching DML (insert/update/delete) into one all-or-nothing commit. No dependency on Trigger Actions Framework - usable from any Apex.    | Yes                                                  |
| `taf-ext/`        | The glue layer: a drop-in trigger handler that commits the current `UnitOfWork` at the true end of a trigger run and logs the outcome via Nebula Logger.                              | Yes                                                  |
| `force-app/`      | Default package directory for your own org-specific metadata.                                                                                                                          | Yes (project-specific)                               |

### Dependencies

Both `unit-of-work` and `taf-ext` call Nebula Logger's `Logger` class directly, so **Nebula Logger
must be installed** in any org where either is deployed. `taf-ext` additionally depends on
**Trigger Actions Framework** (it extends `TriggerBase` and forwards to `MetadataTriggerHandler`).
`unit-of-work` has no dependency on Trigger Actions Framework and can be deployed and used on its
own.

## Setup

Install the two unlocked packages **before** deploying anything from this repo.

### 1. Install the unlocked packages

- **Nebula Logger** (unlocked package, no namespace) - this repo was built against version
  `4.19.5.1`:
  `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tg7000000IzRdAAK`
  (swap in `test.salesforce.com` for a sandbox). See the `nebula-logger-install` skill under
  `.claude/skills/`, or Nebula Logger's own documentation, for permission sets and
  `LoggerSettings__c` configuration - not duplicated here.

- **Trigger Actions Framework** (unlocked package, no namespace) - this repo was built against
  version `0.3.4.1`:
  `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tKY000000R0yHYAS`
  (swap in `test.salesforce.com` for a sandbox). See its own documentation for
  `Trigger_Action__mdt` / `sObject_Trigger_Setting__mdt` configuration - not duplicated here.

A read-only copy of both packages' metadata is vendored under `unlocked/` for local reference
(browsing classes, objects, fields, etc. without leaving the repo).

### 2. Deploy `unit-of-work` and `taf-ext`

```bash
sf project deploy start --source-dir unit-of-work --source-dir taf-ext --target-org <your-org-or-alias>
```

Each package also has its own manifest, if you'd rather deploy by manifest or need just one of
them:

```bash
sf project deploy start --manifest unit-of-work/manifest/package.xml --target-org <your-org-or-alias>
sf project deploy start --manifest taf-ext/manifest/package.xml --target-org <your-org-or-alias>
```

`unit-of-work` has no dependency on `taf-ext`, so it can be deployed alone. `taf-ext` depends on
`unit-of-work` (it calls `UnitOfWork.getCurrent()` / `commitCurrent()`), so deploy both together,
or `unit-of-work` first if deploying separately.

## Usage

### `UnitOfWork`

Use it directly - no trigger required:

```apex
UnitOfWork uow = new UnitOfWork();
Account acct = new Account(Name = 'Acme');
Contact con = new Contact(LastName = 'Coyote');
uow.registerNew(acct);
uow.registerNew(con);
uow.registerRelationship(con, Contact.AccountId, acct);
uow.commitWork();
```

Or share one ambient instance across classes, and commit it once at the end of "this piece of
work":

```apex
UnitOfWork.getCurrent().registerNew(new Task(Subject = 'Follow up'));
// ... more code, possibly in other classes, registers more work on the same instance ...
UnitOfWork.commitCurrent();
```

A failed `commitWork()` rolls back everything registered on that instance, logs an `ERROR` entry
to Nebula Logger with the full exception, and rethrows the original exception unchanged.

### `taf-ext`: wiring `UnitOfWork` into a trigger

In your trigger, use `TriggerActionUnitOfWorkHandler` in place of Trigger Actions Framework's
`MetadataTriggerHandler`:

```apex
trigger AccountTrigger on Account (
    before insert, after insert, before update, after update,
    before delete, after delete, after undelete
) {
    new TriggerActionUnitOfWorkHandler().run();
}
```

Everything about configuring Trigger Actions - `Trigger_Action__mdt` records,
`sObject_Trigger_Setting__mdt`, bypasses, Flow actions - works exactly as it does with
`MetadataTriggerHandler`, since `TriggerActionUnitOfWorkHandler` forwards every call to one
internally.

Inside your Trigger Actions, register work on the current `UnitOfWork` instead of performing DML
directly:

```apex
public class CreateFollowUpTask implements TriggerAction.AfterInsert {
    public void afterInsert(List<SObject> triggerNew) {
        for (SObject record : triggerNew) {
            UnitOfWork.getCurrent()
                .registerNew(new Task(WhatId = record.Id, Subject = 'Follow up'));
        }
    }
}
```

At the true end of the trigger run - after every before/after context has fired, including any
recursive re-entry caused by the same top-level DML statement, and before any `DmlFinalizer`s run
- `TriggerActionUnitOfWorkHandler` automatically:

1. Commits the current `UnitOfWork`.
2. Runs any configured `DmlFinalizer`s.
3. Flushes whatever was buffered in Nebula Logger during the run - by this class, by your Trigger
   Actions, or by `UnitOfWork` itself - with a single `Logger.saveLog()` call, regardless of
   whether the run succeeded or failed.

## Logging

Both packages call Nebula Logger directly (no `CallableLogger` indirection), so Nebula Logger must
be installed wherever they're deployed:

- `UnitOfWork.commitWork()` buffers a `FINE`-level summary before committing (counts of records to
  insert/update/delete), and logs + immediately saves an `ERROR` entry with the full exception
  before rolling back and rethrowing on failure.
- `TriggerActionUnitOfWorkHandler.finalizeDmlOperation()` logs a distinct `ERROR` entry if a
  `DmlFinalizer` throws, buffers a `FINE` entry when the whole run finishes cleanly, and always
  flushes the Nebula Logger buffer in a `finally` block, regardless of outcome.

See the `nebula-logger-*` skills under `.claude/skills/` for logging-level and `LoggerSettings__c`
conventions used by this repo.

## Testing

```bash
sf apex run test --target-org <your-org-or-alias> \
  --class-names UnitOfWorkTest --class-names TriggerActionUnitOfWorkHandlerTest \
  --code-coverage
```

Both `UnitOfWork` and `TriggerActionUnitOfWorkHandler` are covered at 100%, including bulk
(200-record) registration, empty-list edge cases, dirty-record merge behavior, and the Nebula
Logger entries produced on both the success and failure paths.

## Prerequisites for local development

- **Salesforce CLI** - [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli)
- **VS Code with the Salesforce Extension Pack** - [Installation Instructions](https://developer.salesforce.com/docs/platform/sfvscode-extensions/guide/install.html)
- **A development org** with the two unlocked packages above installed
