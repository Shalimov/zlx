# zlx

`zlx` is a bytecode interpreter for the Lox language, written in Zig and based on the VM implementation in [Crafting Interpreters](https://craftinginterpreters.com/).

It currently includes scanning, Pratt parsing and compilation to bytecode, a stack-based virtual machine, strings and hash tables, and a custom garbage-collecting allocator. The command-line program starts a REPL when run without arguments or executes a `.lx` source file when one is supplied.

## Requirements

- Zig `0.16.0`

## Build and run

```sh
zig build
./zig-out/bin/zlx                  # REPL
./zig-out/bin/zlx path/to/file.lx  # run a program
```

Use an optimized build when measuring performance:

```sh
zig build -Doptimize=ReleaseFast
```

## Project structure

| Path | Purpose |
| --- | --- |
| `src/main.zig` | CLI entry point, REPL, and file execution. |
| `src/scanner.zig` | Source scanner and token definitions. |
| `src/compiler.zig` | Parser and bytecode compiler. |
| `src/chunk.zig`, `src/op_code.zig` | Bytecode chunk storage and instruction definitions. |
| `src/vm.zig` | Stack-based bytecode virtual machine. |
| `src/value.zig`, `src/object.zig` | Runtime values and heap objects. |
| `src/gc-allocator.zig`, `src/hash-table.zig`, `src/swiss-table.zig` | Memory management and table implementations. |
| `grammar/` | Language grammar reference. |
| `tests/` | Implementation-agnostic Lox language tests, including benchmarks. |
| `scripts/` | Development helpers, including the language-test runner. |
| `internal-docs/` | Notes and examples for bytecode implementation details. |

## Language tests

Run every `.lx` test with a Debug build:

```sh
./scripts/test-language.sh
```

For a ReleaseFast run with per-test timings:

```sh
./scripts/test-language.sh --release-fast --time
```

The runner prints a pass/fail table and failure details. It understands `// expect:`, `// expect runtime error:`, and compiler-error annotations in the test files. Pass test files or directories to run only part of the suite.
