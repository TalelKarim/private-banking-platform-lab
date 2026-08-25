# PostgreSQL backup and restore runbook

## Goal

Step 22 adds a reproducible logical backup/recovery layer on top of the Step 21
PostgreSQL service.

```text
portfolio database
      |
      | pg_dump --format=custom
      v
/var/lib/postgresql/backups
      |
      | SHA-256 + 7-day retention
      v
custom .dump archive
      |
      | pg_restore
      v
isolated restore DB / controlled production recovery
```

`make configure-lab` still remains the normal daily convergence command. The
PostgreSQL playbook now also installs the backup/restore tools, enables the
daily systemd timer and creates one initial dump if persistent backup storage is
empty.

## What is backed up

The Step 22 backup is a PostgreSQL **logical dump** of the `portfolio` database.
It includes database objects inside that database such as schemas, tables,
indexes, sequences, views and their data when those objects exist.

It is intentionally not a filesystem copy of `/var/lib/postgresql/16/main`.
The dump is created with `pg_dump` in PostgreSQL custom format so `pg_restore`
can validate and replay it.

```text
PostgreSQL engine/data files      PostgreSQL logical backup
----------------------------      -------------------------
/var/lib/postgresql/16/main  ->   pg_dump -> portfolio_....dump
```

Cluster-wide objects such as PostgreSQL roles are still owned by Ansible and
are recreated by Step 21 (`portfolio_owner`, `portfolio_app`). Recovery follows
this order:

```text
Ansible rebuilds PostgreSQL baseline/roles
                 |
                 v
pg_restore restores the portfolio database objects/data
```

## Backup storage and its deliberate lab tradeoff

Backups are stored at:

```text
/var/lib/postgresql/backups
```

That directory is a sibling of the PostgreSQL cluster directory under the same
Cinder-backed filesystem:

```text
Cinder volume postgresql-data
└── /var/lib/postgresql
    ├── 16/main       <- live PostgreSQL data
    └── backups       <- logical dumps + checksums
```

This is useful in this infrastructure-learning step because dumps survive a
Nova root/VM replacement and can recover from a bad database change or a broken
logical database state.

It is **not off-host disaster recovery**: losing/corrupting the whole Cinder
backend can lose both live data and these dumps. The later PostgreSQL hardening
step is where an external/object-storage copy, encryption policy and stronger
DR boundary belong. Step 22 does not pretend otherwise.

## Automatic backup

Ansible installs:

```text
/usr/local/sbin/private-banking-postgresql-backup
/usr/local/sbin/private-banking-postgresql-restore
/usr/local/sbin/private-banking-postgresql-test-restore

/etc/systemd/system/private-banking-postgresql-backup.service
/etc/systemd/system/private-banking-postgresql-backup.timer
```

The timer runs every day at `02:15` in the VM's local system time with up to a
5-minute randomized delay. `Persistent=true` lets systemd catch up a missed run
when the VM was powered off at the scheduled time.

Each backup is written atomically:

```text
pg_dump -> .dump.tmp
        -> pg_restore --list validation
        -> rename to .dump
        -> SHA-256 sidecar
        -> retention cleanup
```

The temporary file is never advertised as a valid backup. Retention defaults to
7 days and is applied only after a new valid archive is created.

## Operator commands from ops-runner

The Make targets discover the PostgreSQL Floating IP automatically when
`POSTGRESQL_FLOATING_IP` is omitted.

Create an on-demand backup:

```bash
make backup-postgresql
```

List retained dumps:

```bash
make list-postgresql-backups
```

Run the important restore test:

```bash
make test-postgresql-restore
```

That command deliberately creates a **fresh** dump, restores it into a temporary
database, verifies the application schema/relation count, then removes the
temporary database:

```text
portfolio
   |
   | fresh pg_dump
   v
portfolio_TIMESTAMP.dump
   |
   | pg_restore
   v
portfolio_restore_test_...
   |
   | validate
   v
SUCCESS
   |
   └── temporary DB dropped
```

No live database is destroyed by this test.

## Restore into a safe alternate database

To inspect/recover a dump without touching the live database:

```bash
make restore-postgresql \
  BACKUP=portfolio_YYYYMMDDTHHMMSSZ.dump \
  TARGET_DB=portfolio_restore_manual
```

`BACKUP=latest` can also be used.

Inspect it locally on the PostgreSQL VM with:

```bash
sudo -u postgres psql -d portfolio_restore_manual
```

When finished:

```bash
sudo -u postgres dropdb --force portfolio_restore_manual
```

## Controlled live recovery

Replacing the live `portfolio` database is destructive, so the helper refuses
it unless the operator provides an explicit confirmation token.

Before a real recovery, stop/quiesce the application writer first. Then:

```bash
make restore-postgresql \
  BACKUP=portfolio_YYYYMMDDTHHMMSSZ.dump \
  TARGET_DB=portfolio \
  CONFIRM=RESTORE_portfolio
```

The restore command:

```text
1. verifies the SHA-256 sidecar
2. verifies pg_restore can read the custom archive
3. terminates sessions on the target database
4. drops the target database
5. recreates it with owner portfolio_owner
6. restores the dump with --exit-on-error
```

The explicit confirmation exists so an accidental `make restore-postgresql`
cannot silently destroy the live database.

## Useful inspection commands on the PostgreSQL VM

```bash
sudo systemctl status private-banking-postgresql-backup.timer
sudo systemctl list-timers private-banking-postgresql-backup.timer
sudo journalctl -u private-banking-postgresql-backup.service --no-pager -n 100
sudo -u postgres ls -lah /var/lib/postgresql/backups
sudo -u postgres /usr/local/sbin/private-banking-postgresql-backup
sudo -u postgres /usr/local/sbin/private-banking-postgresql-test-restore
```

A healthy Step 22 baseline means:

```text
daily timer active
at least one readable custom-format dump
SHA-256 checksum beside every completed dump
retention configured
safe alternate-database restore available
explicitly guarded live restore available
restore test returns SUCCESS
```
