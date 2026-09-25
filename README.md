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

## Language Features

Status of Lx-lang features:

### Data Types & Literals
- [x] **Numbers**: Double-precision floating point (`f64`).
- [x] **Booleans**: `true` and `false`.
- [x] **Nil**: `nil`.
- [x] **Strings**: ASCII/UTF-8 string literals with string interning.

### Expressions & Operators
- [x] **Arithmetic**: Binary `+`, `-`, `*`, `/` (numeric operands only) and unary `-`.
- [x] **String Concatenation**: Dedicated `++` operator (deviation from standard Lox overloaded `+`).
- [x] **Comparison**: `<`, `<=`, `>`, `>=`.
- [x] **Equality**: `==`, `!=`.
- [x] **Logical Operators**: Unary `!`, short-circuiting `and` and `or`.
- [x] **Grouping**: Parenthesized expressions `(...)`.
- [x] **Variable Assignment**: `identifier = expression` (locals and globals).
- [ ] **Ternary Operator**: `expression if condition else expression`
- [ ] **Comma Operator**: `expr1, expr2`

### Statements & Declarations
- [x] **Expression Statements**: `expression;`.
- [x] **Print Statements**: `print expression;`.
- [x] **Block Statements**: `{ ... }` establishing local lexical scopes.

### Variables & Scope
- [x] **Variable Declarations (`var`)**: Mutable variables with optional initializer (defaults to `nil`).
- [x] **Global Variables**: Late-bound global lookup and assignment via hash table.
- [x] **Local Variables**: Stack-allocated local resolution within lexical blocks.
- [x] **Lexical Shadowing**: Nested local scopes shadowing outer bindings.
- [x] **Self-Referencing Initializer Check**: Disallows `var a = a;` in local scope.
- [ ] **Constants (`const`)** *(Language extension)*:
  - [x] Local `const`: Enforces mandatory initial value and immutability checks at compile time.
  - [ ] Global `const`: Parsed and stored, but immutability is not yet enforced for global bindings.

### Control Flow
- [x] **Conditionals**: `if (condition) thenBranch` with optional `else branch`.
- [x] **Truthiness**: `nil` and `false` are falsy; all other values are truthy.
- [x] **While Loops**: `while (condition) statement`.
- [x] **Range-Based For Loops** *(Language extension)*: `for (var i in start..end)` and `for (var i in start..=end)` desugared with `op_inc_local`.
- [x] **Infinite Loops** *(Language extension)*: `loop statement` repeats a statement or block indefinitely; `continue;` starts the next iteration.
- [ ] **Loop Control Statements**:
  - [x] `continue`: Supported in basic loops.
  - [ ] `break`: Lexical loop break context not yet implemented.

### Functions & Closures
- [ ] **Function Declarations**: `fun name(params) { ... }`.
- [ ] **Function Calls**: `callee(args)`.
- [ ] **Return Statements**: `return expression;`.
- [ ] **Closures**: Upvalue capture from enclosing lexical environments.
- [ ] **Anonymous Functions / Lambdas**: `fun(params) expression`.
- [ ] **Native Functions**: Built-in runtime functions (e.g., `clock()`).
- [ ] **Call Frames & Stack**: Multi-frame call stack in the virtual machine.

### Classes & Object-Oriented Programming
- [ ] **Class Declarations**: `class Name { ... }`.
- [ ] **Instances & Fields**: Dynamic property access and assignment (`object.field`).
- [ ] **Methods**: Member function dispatch on instances.
- [ ] **Initializers**: Constructor methods (`init()`).
- [ ] **`this` Keyword**: Self-reference within instance methods.
- [ ] **Inheritance**: Superclass derivation (`class Sub < Super`).
- [ ] **`super` Keyword**: Superclass method dispatch.
- [ ] **Extended OOP Features**: Static methods, properties, and protocols (defined in grammar, uncompiled).

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
