const std = @import("std");

const Chunk = @import("chunk.zig").Chunk;
const Compiler = @import("compiler.zig").Compiler;
const OpCode = @import("op_code.zig").OpCode;
const GcAllocator = @import("gc-allocator.zig").GcAllocator;
const debug = @import("debug.zig");
const vm = @import("vm.zig");

const Io = std.Io;
const InterpretError = vm.InterpretError;
const VirtualMachine = vm.VirtualMachine;

const REPL_BUFFER_SIZE = 512;
const VM_MAX_STACK_SIZE = 1024;
var stack_buffer: [VM_MAX_STACK_SIZE]u8 = undefined;

const CliError = error{
    TooManyArguments,
};

fn repl(alloc: std.mem.Allocator, io: Io, virt: *VirtualMachine) !void {
    var read_buffer: [REPL_BUFFER_SIZE]u8 = undefined;
    var write_buffer: [REPL_BUFFER_SIZE]u8 = undefined;

    const stdin = Io.File.stdin();
    const stdout = Io.File.stdout();
    var stdin_reader: Io.File.Reader = stdin.reader(io, &read_buffer);
    var stdout_writer: Io.File.Writer = stdout.writer(io, &write_buffer);

    var reader: *Io.Reader = &stdin_reader.interface;
    var writer: *Io.Writer = &stdout_writer.interface;

    try writer.print("[script]> ", .{});
    try writer.flush();

    while (reader.takeDelimiterExclusive('\n')) |line| {
        reader.toss(1);

        if (line.len == 0) {
            try writer.print("Bye bye\n", .{});
            try writer.flush();

            break;
        }

        try interpret(alloc, virt, line);

        try writer.print("[script]> ", .{});
        try writer.flush();
    } else |err| {
        try writer.print("error happend during reading {any}", .{err});
    }
}

fn runFile(alloc: std.mem.Allocator, io: Io, virt: *VirtualMachine, path: [:0]const u8) !void {
    const cwd = Io.Dir.cwd();
    const script = try Io.Dir.readFileAlloc(cwd, io, path, alloc, Io.Limit.limited(65_536));
    defer alloc.free(script);

    try interpret(alloc, virt, script);
}

fn interpret(alloc: std.mem.Allocator, virt: *VirtualMachine, line: []u8) !void {
    try virt.interpret(alloc, line);
}

pub fn main(init: std.process.Init) !void {
    const aa = init.arena.allocator();
    var gc = try GcAllocator.prepare(init.gpa);
    const gc_alloc = gc.allocator();

    defer gc.deinit();

    const arguments = try init.minimal.args.toSlice(aa);

    var virt: VirtualMachine = .init;

    if (arguments.len == 1) {
        try repl(gc_alloc, init.io, &virt);
    } else if (arguments.len == 2) {
        try runFile(gc_alloc, init.io, &virt, arguments[1]);
    } else {
        try Io.File.stdout().writeStreamingAll(init.io, "Usage: zlx [path]\n");

        return CliError.TooManyArguments;
    }
}
