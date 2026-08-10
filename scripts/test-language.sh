#!/usr/bin/env bash
# Run the implementation-agnostic language tests in tests/.
#
# The test files follow Crafting Interpreters conventions:
#   // expect: output
#   // expect runtime error: message
#   // [line N] Error ...

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$ROOT_DIR/tests"
MODE="Debug"
SHOW_TIME=0
BUILD=1

usage() {
    cat <<'EOF'
Usage: scripts/test-language.sh [options] [test-file-or-directory ...]

Options:
  --mode MODE       Zig optimization mode: Debug (default), ReleaseFast, ReleaseSafe,
                    or ReleaseSmall.
  --release-fast    Shorthand for --mode ReleaseFast.
  --time            Include elapsed time for every test in the table.
  --no-build        Reuse zig-out/bin/zlx instead of building first.
  -h, --help        Show this help.

With no paths, every .lx file below tests/ is run. Paths may be absolute or
relative to the repository root. A non-zero exit status means at least one
test failed.
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 2
}

while (($#)); do
    case "$1" in
        --mode)
            (($# >= 2)) || die '--mode requires a value'
            MODE="$2"
            shift 2
            ;;
        --release-fast)
            MODE="ReleaseFast"
            shift
            ;;
        --time)
            SHOW_TIME=1
            shift
            ;;
        --no-build)
            BUILD=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            die "unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

case "$MODE" in
    Debug|ReleaseFast|ReleaseSafe|ReleaseSmall) ;;
    *) die "unsupported mode '$MODE'" ;;
esac

if ((BUILD)); then
    printf 'Building zlx (%s)...\n' "$MODE"
    (cd "$ROOT_DIR" && zig build "-Doptimize=$MODE") || exit $?
fi

BINARY="$ROOT_DIR/zig-out/bin/zlx"
[[ -x "$BINARY" ]] || die "executable not found: $BINARY (omit --no-build or build it first)"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zlx-language-tests.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

declare -a TESTS=()
if (($# == 0)); then
    while IFS= read -r file; do
        TESTS+=("$file")
    done < <(find "$TEST_DIR" -type f -name '*.lx' | LC_ALL=C sort)
else
    for path in "$@"; do
        [[ "$path" = /* ]] || path="$ROOT_DIR/$path"
        if [[ -f "$path" ]]; then
            TESTS+=("$path")
        elif [[ -d "$path" ]]; then
            while IFS= read -r file; do
                TESTS+=("$file")
            done < <(find "$path" -type f -name '*.lx' | LC_ALL=C sort)
        else
            die "test path not found: $path"
        fi
    done
fi

((${#TESTS[@]})) || die 'no .lx tests found'

normalize_debug_output() {
    # Debug builds deliberately dump bytecode and VM state through stderr.
    # Remove only those trace records; regular language output remains intact.
    sed -E \
        -e $'s/\r//g' \
        -e '/^== code ==$/d' \
        -e '/^[[:space:]]*[0-9]{4}[[:space:]]/d' \
        -e '/^        \[/d' \
        -e '/^error: /d' \
        -e '/^\/.* in .* \(zlx\)$/d' \
        -e '/^[[:space:]]*\^$/d' \
        -e '/^[[:space:]]*$/d'
}

expected_output() {
    # Runtime-error expectations are checked separately, not treated as stdout.
    sed -nE 's@.*//[[:space:]]*expect:[[:space:]]?(.*)$@\1@p' "$1"
}

runtime_expectations() {
    sed -nE 's@.*//[[:space:]]*expect runtime error:[[:space:]]?(.*)$@\1@p' "$1"
}

compile_expectations() {
    sed -nE 's@^[[:space:]]*//[[:space:]]*(\[line [0-9]+\] Error.*)$@\1@p' "$1"
}

printf '\n%-5s %-8s' 'No.' 'Result'
printf ' %-54s' 'Test'
((SHOW_TIME)) && printf ' %10s' 'Time'
printf '\n'
printf '%-5s %-8s' '----' '--------'
printf ' %-54s' '------------------------------------------------------'
((SHOW_TIME)) && printf ' %10s' '----------'
printf '\n'

passed=0
failed=0
test_number=0
declare -a FAILURE_LOGS=()

for test_file in "${TESTS[@]}"; do
    ((test_number += 1))
    log_file="$TEMP_DIR/$test_number.log"

    # Perl supplies a portable sub-second timer on macOS and Linux. Its marker
    # is removed before comparing the interpreter output.
    perl -MTime::HiRes=time -e '
        my $start = time;
        system @ARGV;
        my $status = $?;
        printf STDERR "\n__ZLX_DURATION__%.6f\n", time - $start;
        exit($status == -1 ? 127 : $status >> 8);
    ' "$BINARY" "$test_file" >"$log_file" 2>&1
    exit_code=$?

    duration="$(sed -nE 's/^__ZLX_DURATION__([0-9.]+)$/\1/p' "$log_file" | tail -n 1)"
    sed '/^__ZLX_DURATION__/d' "$log_file" >"$log_file.clean"
    actual="$(normalize_debug_output <"$log_file.clean")"
    expected="$(expected_output "$test_file")"
    runtime_errors="$(runtime_expectations "$test_file")"
    compile_errors="$(compile_expectations "$test_file")"
    reason=""

    if [[ -n "$compile_errors" ]]; then
        if ((exit_code == 0)); then
            reason='expected a compile error, but execution succeeded'
        else
            while IFS= read -r expected_error; do
                [[ -z "$expected_error" ]] && continue
                if ! grep -Fqx "$expected_error" "$log_file.clean"; then
                    reason="missing compiler error: $expected_error"
                    break
                fi
            done <<<"$compile_errors"
        fi
    elif [[ -n "$runtime_errors" ]]; then
        if ((exit_code == 0)); then
            reason='expected a runtime error, but execution succeeded'
        else
            while IFS= read -r expected_error; do
                [[ -z "$expected_error" ]] && continue
                if ! grep -Fq "$expected_error" "$log_file.clean"; then
                    reason="missing runtime error: $expected_error"
                    break
                fi
            done <<<"$runtime_errors"
        fi
        # Error text itself is diagnostic output, not language output. Compare
        # only the output emitted before the first expected runtime-error text.
        first_runtime_error="${runtime_errors%%$'\n'*}"
        actual_before_error="${actual%%"$first_runtime_error"*}"
        if [[ -z "$reason" && "$actual_before_error" != "$expected" ]]; then
            reason='output before the runtime error differs'
        fi
    else
        if ((exit_code != 0)); then
            reason="unexpected exit status $exit_code"
        elif [[ "$actual" != "$expected" ]]; then
            reason='output differs from // expect: comments'
        fi
    fi

    display_path="${test_file#"$ROOT_DIR"/}"
    if [[ -z "$reason" ]]; then
        result='PASS'
        ((passed += 1))
    else
        result='FAIL'
        ((failed += 1))
        detail_file="$TEMP_DIR/$test_number.detail"
        {
            printf '%s: %s\n' "$display_path" "$reason"
            printf 'Expected output:\n%s\n' "${expected:-<empty>}"
            printf 'Actual output:\n%s\n' "${actual:-<empty>}"
            printf 'Raw interpreter output:\n'
            sed -n '1,160p' "$log_file.clean"
        } >"$detail_file"
        FAILURE_LOGS+=("$detail_file")
    fi

    printf '%-5d %-8s %-54s' "$test_number" "$result" "$display_path"
    ((SHOW_TIME)) && printf ' %9.3f s' "${duration:-0}"
    printf '\n'
done

printf '\nSummary: %d passed, %d failed, %d total (%s).\n' \
    "$passed" "$failed" "$test_number" "$MODE"

if ((failed)); then
    printf '\nFailure details:\n'
    for detail_file in "${FAILURE_LOGS[@]}"; do
        printf '\n%s\n' '----------------------------------------------------------------------'
        cat "$detail_file"
    done
    exit 1
fi
