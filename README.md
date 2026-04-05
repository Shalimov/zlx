# zlx

A small interpreter / bytecode virtual machine project implemented in Zig, following the C implementation from the book *Crafting Interpreters*.

## Language Reference

- Implementation language: Zig
- Zig version: `0.16.0-dev`

## Project Overview

This repository contains a Zig-based interpreter for a custom language, including:

- `grammar/` for language grammar definitions
- `src/` for the interpreter and VM implementation
- `build.zig` and `build.zig.zon` for build configuration
- `zig-out/bin/zlx` as the compiled executable output

The project demonstrates language implementation concepts such as parsing, bytecode generation, and virtual machine execution in Zig.
