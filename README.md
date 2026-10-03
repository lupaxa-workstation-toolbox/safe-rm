<p align="center">
    <a href="https://github.com/lupaxa-workstation-toolbox">
        <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/organisations/workstation-toolbox/readme-logo.png" alt="Organisation Logo" />
    </a>
</p>

<h1 align="center">Safe RM</h1>

Recoverable replacement for interactive `rm` and `rmdir`. A normal removal
moves the operand into a private store so it can be listed and restored.
Permanent deletion happens only through `--delete`, `--empty`, `--purge`,
`--permanent`, or an explicitly enabled retention purge.

The installed program is one Bash script, `src/safe-rm`. It targets macOS
Bash 3.2 and Linux Bash 3.2 or newer, using standard system utilities. It is
not a transparent replacement for every GNU or BSD `rm` option, and it does
not replace `/bin/rm`.

## Requirements

- Bash 3.2 or newer (`/bin/bash` on macOS is enough)
- Standard `cp`, `mv`, `rm`, `rmdir`, `mkdir`, `find`, `stat`, `date`, `du`, and `awk`
- A SHA-256 tool, detected as `shasum -a 256` or `sha256sum`
- Optional `uuidgen` and `fzf`

`jq`, Python, Perl, and Node.js are not required at runtime.

## Quick Start

Clone and run the script:

```bash
git clone git@github.com:lupaxa-workstation-toolbox/safe-rm.git
cd safe-rm
./src/safe-rm --help
```

To put a checkout on `PATH`:

```bash
cp /path/to/safe-rm/src/safe-rm ~/bin/safe-rm
chmod +x ~/bin/safe-rm
```

Homebrew installs that same executable. After a stable release is published
in the tap:

```bash
brew tap the-lupaxa-project/tap
brew trust the-lupaxa-project/tap
brew install safe-rm
```

Suggested interactive-shell aliases. They do not affect scripts, `command rm`,
other shells, or programs that unlink files themselves:

```bash
alias rm='safe-rm'
alias rmdir='safe-rm --rmdir'
alias rm-permanent='safe-rm --permanent'
```

Removing the alias or the executable does not delete the store.

## What it Does

```bash
safe-rm file.txt
safe-rm -r directory
safe-rm --rmdir empty-directory
safe-rm --list
safe-rm --restore <id>
safe-rm --delete <id>
safe-rm --empty
safe-rm --purge
safe-rm --permanent -r directory
safe-rm --doctor
```

A successful trash leaves no original operand, a payload at `files/<id>`,
valid metadata, and a completed transaction. Human output is quiet on success
unless `-v` is set. `--json` is accepted for `--list`, `--info`, `--stats`,
and `--doctor`.

## Store

The default store is private to safe-rm. It is not Finder or Freedesktop trash.

```text
${XDG_DATA_HOME:-$HOME/.local/share}/Trash
```

`TRASH_BASE` selects another absolute directory. If that path already exists,
is not empty, and has no safe-rm marker, safe-rm refuses it and does not move
or delete its contents. Point `TRASH_BASE` at a new directory instead.

Payload names are ids. Original names come from metadata. The store is created
mode `0700` and must be owned by the invoking user.

## Prompts

`-i` asks once per top-level operand, including a whole directory. `-I` asks
once when there are more than three operands or a recursive directory. These
are not native per-child prompts. The last of `-f`, `-i`, and `-I` wins.

`-f` skips removal prompts and the missing-operand error. It does not skip
permission, safety, lock, checksum, or transfer failures.

`--delete`, `--empty`, `--purge`, and `--permanent` ask for exactly `y`, `Y`,
`yes`, or `YES` on `/dev/tty` unless `--force` is set. Any other answer,
including end of file, cancels with exit 0. Without a terminal, those commands
require `--force`.

`TRASH_INTERACTIVE=never` skips ordinary removal prompts only. It is not
consent for irreversible commands.

## Restore and Ids

`--restore <id>` puts the object back at the recorded absolute path.
`--to DIR` puts the original basename inside an existing directory. An occupied
destination, including a dangling symlink, is refused. `--rename` uses
`<name>.restored-1` and then higher numbers. `--overwrite` trashes the
destination in its own transaction first; it never permanently erases that
object. `--force` does not overwrite.

Ids are lowercase UUIDs. Management commands accept a unique hexadecimal prefix
of at least eight characters. Ids are not paths or globs. `--restore` with no
id needs a terminal and a numbered choice, or `fzf` when it is installed.
Cancelling does not change anything.

A stored checksum is checked before restore. On mismatch the entry stays put.
`--ignore-checksum` is a deliberate override and is logged.

## Irreversible Actions

`--delete <id>` removes one committed entry. `--empty` removes every committed
entry from a locked snapshot. `--purge` applies age and then size policy.
Quarantine, incomplete transactions, logs, and unknown files are excluded.
If uncertain entries exist, `--empty` refuses and tells you to run doctor.

`TRASH_AUTO_PURGE` defaults to `false`. Setting it to `true` is consent to
delete expired or over-size entries after a successful trash, without another
prompt. A purge failure does not undo the trash; it is a separate warning.

`--permanent` resolves `/bin/rm` or `/usr/bin/rm`, checks that it is not this
script, and still applies the path protections below. Dry-run prints the
command and does not run it.

## Protections

These cannot be disabled by `-f` or configuration:

- `/`, your home directory, and the current working directory
- Ancestors of the working directory or the trash store
- The trash store and everything inside it
- Filesystem mount roots
- Paths in `TRASH_PROTECT_PATHS`

A symlink whose own path is outside those locations may be removed even when
it points at a protected directory. A trailing slash that would follow a final
symlink is refused. Version 1 refuses a recursive transfer that crosses a
nested mount. `--preserve-root` is accepted. `--no-preserve-root` is rejected.
`--one-file-system` is accepted and is already how version 1 behaves.

Effective uid 0 is refused. There is no root bypass.

## Cross-device Copies and Limits

Same-filesystem trash is a rename. Cross-filesystem trash copies into the
store, verifies types, modes, sizes, symlink targets, and SHA-256 of every
regular file, publishes the copy, and only then removes the source. `mv` is
not allowed to hide that boundary.

If the copy fails, the disk fills, a child is unreadable, preservation cannot
be verified, or the source changes during the copy, the source stays in place.
A partial source removal keeps the verified copy and a journal. Repair will
not delete remaining source data to force a tidy store.

Sparse files may use a different amount of space after a copy. Hard links to
objects outside the transferred tree are not preserved as the same links.
ACLs, extended attributes, flags, and macOS resource forks are kept only when
the platform copy can be checked; otherwise the transfer is refused.

These checks narrow races. They do not close every time-of-check/time-of-use
race with another writer, and they do not add durability beyond the filesystem.
Stop writers, or snapshot the tree, when you need a stronger guarantee. Trash
is not a backup and it does not securely erase data.

Hashing a large cross-device tree holds the store lock for the whole copy.
Plan for the extra space of a full second copy.

## Locks, Doctor, and Quarantine

The lock is an atomic `mkdir` of `.lock`. A timeout (default 10 seconds) exits
4. A stale lock is cleared only when this host can show that the recorded pid
no longer exists. Age, permission errors, and pid reuse are not enough.

`--doctor` is read-only. `--doctor --repair` may finalize a proven commit, move
a proven same-device staged object back onto a vacant original path, or
quarantine the evidence. It does not invent paths, overwrite an occupied
original path, or delete unknown payloads. Quarantine is not purged. Inspect
it with `--doctor` and `--list --quarantine`, then copy the payload out
yourself.

SIGKILL and power loss are recovered from the journal, not from traps.
`--doctor` is the recovery command.

## Configuration

Precedence is built-in defaults, then the config file, then the environment,
then the command line. The file is data. It is not sourced or evaluated.
The default path is `${XDG_CONFIG_HOME:-$HOME/.config}/safe-rm/config`.
A missing default file is fine. `--config PATH` must exist. Duplicate keys,
unknown keys, and group or world writable files are errors.

| Setting                     | Default              |
| --------------------------- | -------------------- |
| `TRASH_BASE`                | XDG-style path above |
| `TRASH_MAX_DAYS`            | `30`                 |
| `TRASH_MAX_SIZE`            | `10GiB`              |
| `TRASH_CHECKSUM`            | `auto`               |
| `TRASH_CHECKSUM_MAX_SIZE`   | `1GiB`               |
| `TRASH_AUTO_PURGE`          | `false`              |
| `TRASH_AUTO_PURGE_INTERVAL` | `3600`               |
| `TRASH_LOG_MAX_SIZE`        | `10MiB`              |
| `TRASH_LOG_ROTATIONS`       | `3`                  |
| `TRASH_LOCK_TIMEOUT`        | `10`                 |
| `TRASH_INTERACTIVE`         | `default`            |
| `TRASH_PROTECT_PATHS`       | empty                |

`TRASH_CHECKSUM=never` skips optional stored digests. It does not skip the
mandatory cross-device verification. Sizes accept `B`, `K`, `KB`, `KiB`, and
the `M`, `G`, and `T` forms. Decimal suffixes (`KB`, `MB`, …) use powers of
1000. Short and `iB` suffixes use powers of 1024. `off` disables a policy.
`0` is a real zero limit.

## Dry-run

`--dry-run` parses arguments, checks protections, and prints `DRY RUN`. It
does not create the store, take a lock, move, copy, delete, or write logs.

## Exit Codes

| Code          | Meaning                                        |
| ------------- | ---------------------------------------------- |
| 0             | Success, a no-op, or a cancel                  |
| 1             | Ordinary operand, permission, or copy failure  |
| 2             | Usage or invalid configuration                 |
| 3             | Protected path or store refusal                |
| 4             | Lock timeout or ambiguous lock                 |
| 5             | Integrity failure or an unresolved transaction |
| 6             | A required platform tool is missing            |
| 129, 130, 143 | HUP, INT, TERM                                 |

For a mixed batch the precedence is integrity, safety, capability, lock, then
ordinary failure. A log or automatic-purge warning after a successful trash
does not change that success.

## Validation

Checked on this machine with `/bin/bash` 3.2.57 and BSD tools (macOS): syntax,
shellcheck, and `tests/run_all.sh` (73 passed). That suite covers ordinary
removal and restore, directories, rmdir including hidden names, leading-dash
and newline names, symlinks including a link to `/`, special-file refusal,
catastrophic paths, dry-run inventories, JSON parsed by Python's `json`
module, inert config, delete and empty, and an injected failure before the
source move.

A separate probe mounted a private HFS disk image and trashed one regular
file onto it, then restored it. The bytes came back. That image mounted with
`noowners`, so it does not prove ownership, ACLs, or a large tree. ENOSPC,
unreadable children, and Linux GNU tools were not run. Power-loss durability
was not measured. Do not treat this tree as proven on every platform until
those runs exist.

```bash
/bin/bash -n src/safe-rm
/bin/bash tests/run_all.sh
```

<a href="https://github.com/the-lupaxa-project">
    <img src="https://raw.githubusercontent.com/the-lupaxa-project/brand-assets/master/logos/components/footer-for-child-orgs.svg" alt="The Lupaxa Project Footer" width="100%" />
</a>
