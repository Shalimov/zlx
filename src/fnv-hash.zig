const std = @import("std");

const fnv_offset_basis: u64 = 14695981039346656037;
const fnv_prime: u64 = 1099511628211;

pub fn getHash(str: []const u8) u64 {
    var resulting_hash: u64 = fnv_offset_basis;

    for (str) |char| {
        resulting_hash = resulting_hash ^ @as(u64, char);
        resulting_hash = resulting_hash *% fnv_prime;
    }

    return resulting_hash;
}

test "expect hasing function return an unsigned integer representation of a string" {
    const round1 = "hello world";
    const round2 = "hello world 1";
    const round3 = "1 hello world";
    const round4 = "1 hello world 1";

    const hash1 = getHash(round1);
    const hash2 = getHash(round2);
    const hash3 = getHash(round3);
    const hash4 = getHash(round4);

    try std.testing.expectEqual(8618312879776256743, hash1);
    try std.testing.expectEqual(10391042892682631676, hash2);
    try std.testing.expectEqual(17305448704603873496, hash3);
    try std.testing.expectEqual(17009734582186235451, hash4);
}
