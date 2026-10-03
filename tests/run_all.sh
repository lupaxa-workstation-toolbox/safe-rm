#!/bin/bash
# Isolated safe-rm tests. Never uses the real home Trash.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="${ROOT}/src/safe-rm"
BASH_BIN="/bin/bash"
FAIL=0
PASS=0

if [ ! -x "$BASH_BIN" ]; then
    BASH_BIN="bash"
fi

say() { printf '%s\n' "$1"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s\n        expected: [%s]\n        actual:   [%s]\n' "$desc" "$expected" "$actual"
    fi
}

assert_ok() {
    local desc="$1" status="$2"
    assert_eq "$desc" "0" "$status"
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s' "$haystack" | grep -F -q -- "$needle"; then
        PASS=$((PASS + 1))
        printf '  PASS: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL: %s\n        missing: [%s]\n' "$desc" "$needle"
    fi
}

new_env() {
    WORK="$(mktemp -d)"
    HOME_DIR="${WORK}/home"
    TRASH_DIR="${WORK}/trash"
    SRC_DIR="${WORK}/src"
    mkdir -p "$HOME_DIR" "$SRC_DIR"
    export HOME="$HOME_DIR"
    export TRASH_BASE="$TRASH_DIR"
    export TRASH_AUTO_PURGE=false
    unset XDG_DATA_HOME XDG_CONFIG_HOME SAFE_RM_TEST_HOOK SAFE_RM_INJECT
}

run_srm() {
    RUN_STATUS=0
    RUN_OUT="$("$BASH_BIN" "$SCRIPT" "$@" 2>"${WORK}/err")" || RUN_STATUS=$?
    RUN_ERR="$(cat "${WORK}/err")"
}

cleanup_env() {
    rm -rf "$WORK"
}

test_help_version() {
    say "help and version"
    new_env
    run_srm --help
    assert_ok "help exit" "$RUN_STATUS"
    assert_contains "help mentions alias" "alias rm='safe-rm'" "$RUN_OUT"
    assert_contains "help mentions limits" "time-of-check" "$RUN_OUT"
    run_srm --version
    assert_ok "version exit" "$RUN_STATUS"
    assert_contains "version string" "safe-rm 0.0.0" "$RUN_OUT"
    run_srm --quiet --verbose
    assert_eq "quiet and verbose" "2" "$RUN_STATUS"
    run_srm --no-preserve-root file
    assert_eq "no-preserve-root" "2" "$RUN_STATUS"
    run_srm --not-a-flag
    assert_eq "unknown option" "2" "$RUN_STATUS"
    cleanup_env
}

test_trash_restore() {
    say "trash and restore"
    new_env
    cd "$SRC_DIR" || exit 1
    printf 'hello\n' > file.txt
    run_srm file.txt
    assert_ok "trash exit" "$RUN_STATUS"
    if [ -e file.txt ]; then
        FAIL=$((FAIL + 1))
        printf '  FAIL: source removed\n'
    else
        PASS=$((PASS + 1))
        printf '  PASS: source removed\n'
    fi
    run_srm --list
    assert_contains "list shows file" "file.txt" "$RUN_OUT"
    id="$(printf '%s\n' "$RUN_OUT" | awk 'NR==2 {print $1}')"
    run_srm --restore "$id"
    assert_ok "restore exit" "$RUN_STATUS"
    assert_eq "bytes" "hello" "$(cat file.txt)"
    run_srm --list
    assert_eq "list empty after restore" "ID	DELETED	SIZE	TYPE	PATH" "$RUN_OUT"
    cleanup_env
}

test_flags() {
    say "flags and directories"
    new_env
    cd "$SRC_DIR" || exit 1
    mkdir -p dir/sub
    printf 'x\n' > dir/sub/a.txt
    printf 'y\n' > other.txt
    run_srm dir
    assert_eq "directory without -r" "1" "$RUN_STATUS"
    test -d dir
    assert_eq "directory remains" "0" "$?"
    run_srm -r dir other.txt
    assert_ok "recursive and file" "$RUN_STATUS"
    test ! -e dir && test ! -e other.txt
    assert_eq "both removed" "0" "$?"
    run_srm
    assert_eq "no operands" "2" "$RUN_STATUS"
    run_srm -f
    assert_ok "force no operands" "$RUN_STATUS"
    printf 'z\n' > keep.txt
    run_srm -- -- -keep.txt
    assert_eq "missing dashed name" "1" "$RUN_STATUS"
    printf 'z\n' > ./-dashed
    run_srm -- -dashed
    assert_ok "leading dash operand" "$RUN_STATUS"
    test ! -e ./-dashed
    assert_eq "dashed removed" "0" "$?"
    mkdir empty hidden
    printf 'h\n' > hidden/.secret
    run_srm --rmdir hidden
    assert_eq "rmdir nonempty hidden" "1" "$RUN_STATUS"
    test -d hidden
    assert_eq "hidden remains" "0" "$?"
    run_srm --rmdir empty
    assert_ok "rmdir empty" "$RUN_STATUS"
    test ! -d empty
    assert_eq "empty gone" "0" "$?"
    cleanup_env
}

test_bytes_and_links() {
    say "names and symlinks"
    new_env
    cd "$SRC_DIR" || exit 1
    mkdir -p "dir with spaces"
    printf 's\n' > "dir with spaces/a file.txt"
    run_srm -r "dir with spaces"
    assert_ok "spaces" "$RUN_STATUS"
    run_srm --list
    assert_contains "list spaces" "dir with spaces" "$RUN_OUT"
    id="$(printf '%s\n' "$RUN_OUT" | awk 'NR==2 {print $1}')"
    run_srm --restore "$id" --to "$SRC_DIR"
    assert_ok "restore spaces" "$RUN_STATUS"
    status=1
    [ -d "dir with spaces" ] && status=0
    assert_eq "tree restored" "0" "$status"
    printf 'p\n' > '100% done.txt'
    run_srm '100% done.txt'
    assert_ok "percent name" "$RUN_STATUS"
    printf 't\n' > target.txt
    ln -s target.txt the-link
    ln -s / the-root-link
    run_srm the-link the-root-link
    assert_ok "symlinks" "$RUN_STATUS"
    status=1
    [ -f target.txt ] && status=0
    assert_eq "symlink target kept" "0" "$status"
    status=1
    [ -d / ] && status=0
    assert_eq "root still exists" "0" "$status"
    ln -s target.txt slash-link
    run_srm slash-link/
    assert_eq "trailing slash symlink" "3" "$RUN_STATUS"
    status=1
    [ -L slash-link ] && status=0
    assert_eq "link remains" "0" "$status"
    run_srm /dev/null
    assert_eq "special file" "1" "$RUN_STATUS"
    nlname="$(printf 'line\nname')"
    printf 'n\n' > "$nlname"
    run_srm "$nlname"
    assert_ok "newline name" "$RUN_STATUS"
    run_srm --list
    id="$(printf '%s\n' "$RUN_OUT" | awk 'NR==2 {print $1}')"
    run_srm --restore "$id"
    assert_ok "restore newline name" "$RUN_STATUS"
    test -f "$nlname"
    assert_eq "newline file restored" "0" "$?"
    cleanup_env
}

test_protection() {
    say "protection"
    new_env
    cd "$SRC_DIR" || exit 1
    printf 'k\n' > file.txt
    run_srm /
    assert_eq "root" "3" "$RUN_STATUS"
    run_srm -rf /
    assert_eq "force root" "3" "$RUN_STATUS"
    run_srm .
    assert_eq "dot" "3" "$RUN_STATUS"
    run_srm ..
    assert_eq "dotdot" "3" "$RUN_STATUS"
    run_srm "$HOME_DIR"
    assert_eq "home" "3" "$RUN_STATUS"
    run_srm -f "$SRC_DIR"
    assert_eq "cwd" "3" "$RUN_STATUS"
    test -f file.txt
    assert_eq "file kept" "0" "$?"
    cleanup_env
}

test_dry_run_and_json() {
    say "dry-run and json"
    new_env
    cd "$SRC_DIR" || exit 1
    printf 'd\n' > file.txt
    before="$(find "$SRC_DIR" "$HOME_DIR" -print 2>/dev/null | LC_ALL=C sort)"
    run_srm --dry-run file.txt
    assert_ok "dry-run exit" "$RUN_STATUS"
    assert_contains "dry-run text" "DRY RUN" "$RUN_OUT"
    after="$(find "$SRC_DIR" "$HOME_DIR" -print 2>/dev/null | LC_ALL=C sort)"
    assert_eq "dry-run no writes" "$before" "$after"
    test -f file.txt
    assert_eq "dry-run kept file" "0" "$?"
    run_srm --permanent --dry-run file.txt
    assert_ok "permanent dry-run" "$RUN_STATUS"
    test -f file.txt
    assert_eq "permanent dry-run kept file" "0" "$?"
    run_srm file.txt
    run_srm --list --json
    assert_ok "json list" "$RUN_STATUS"
    printf '%s\n' "$RUN_OUT" | python3 -m json.tool >/dev/null
    assert_eq "json parses" "0" "$?"
    assert_contains "percent path" '"encoding":"percent"' "$RUN_OUT"
    cleanup_env
}

test_config_inert() {
    say "config"
    new_env
    cd "$SRC_DIR" || exit 1
    cfg="${WORK}/cfg"
    # shellcheck disable=SC2016  # intentional literal config for injection test
    printf 'TRASH_BASE=$(printf pwned)\nTRASH_CHECKSUM=auto\n' > "$cfg"
    run_srm --config "$cfg" --version
    assert_eq "version ignores bad config" "0" "$RUN_STATUS"
    printf 'hello\n' > file.txt
    unset TRASH_BASE
    run_srm --config "$cfg" file.txt
    assert_eq "bad base rejected" "2" "$RUN_STATUS"
    test ! -e "${WORK}/pwned"
    assert_eq "substitution not executed" "0" "$?"
    printf 'NOPE=1\n' > "$cfg"
    run_srm --config "$cfg" file.txt
    assert_eq "unknown key" "2" "$RUN_STATUS"
    test -f file.txt
    assert_eq "file not trashed" "0" "$?"
    cleanup_env
}

test_delete_and_doctor() {
    say "delete and doctor"
    new_env
    cd "$SRC_DIR" || exit 1
    printf 'a\n' > a.txt
    printf 'b\n' > b.txt
    run_srm a.txt b.txt
    assert_ok "batch trash" "$RUN_STATUS"
    run_srm --doctor
    assert_ok "doctor healthy" "$RUN_STATUS"
    run_srm --delete --force
    assert_eq "delete needs id" "2" "$RUN_STATUS"
    id="$( "$BASH_BIN" "$SCRIPT" --list | awk 'NR==2 {print $1}')"
    prefix="$(printf '%s' "$id" | cut -c1-8)"
    run_srm --delete "$prefix" --force
    assert_ok "prefix delete" "$RUN_STATUS"
    run_srm --empty --dry-run
    assert_ok "empty dry-run" "$RUN_STATUS"
    run_srm --empty --force
    assert_ok "empty force" "$RUN_STATUS"
    run_srm --list
    assert_eq "empty list" "ID	DELETED	SIZE	TYPE	PATH" "$RUN_OUT"
    cleanup_env
}

test_injection() {
    say "failure injection"
    new_env
    cd "$SRC_DIR" || exit 1
    printf 'secret\n' > secret.txt
    SAFE_RM_TEST_HOOK=1 SAFE_RM_INJECT=prepared \
        "$BASH_BIN" "$SCRIPT" secret.txt >"${WORK}/out" 2>"${WORK}/err"
    status=$?
    assert_eq "injected exit" "5" "$status"
    status=1
    [ -f secret.txt ] && status=0
    assert_eq "source kept before move" "0" "$status"
    assert_contains "inject message" "injected failure" "$(cat "${WORK}/err")"
    run_srm --doctor
    assert_contains "doctor sees transaction" "transaction" "$RUN_ERR$RUN_OUT"
    cleanup_env
}

test_help_version
test_trash_restore
test_flags
test_bytes_and_links
test_protection
test_dry_run_and_json
test_config_inert
test_delete_and_doctor
test_injection

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
exit 0
