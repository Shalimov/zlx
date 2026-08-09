pub const OpCode = enum {
    op_negate,
    op_not,
    op_nil,
    op_true,
    op_equal,
    op_less,
    op_greater,
    op_false,
    op_concat,
    op_add,
    op_sub,
    op_mul,
    op_div,
    op_return,
    // debugging
    op_print,

    // Special cases
    op_pop,

    // Wide operations
    op_wide, // modifier that instructs that the next operation will be 2 bytes size
    op_constant,
    op_define_global,
    op_get_global,
    op_set_global,
};
