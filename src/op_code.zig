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
    op_constant_long,
    op_constant,
    op_define_global_long,
    op_define_global,
    op_get_global_long,
    op_get_global,
    op_set_global_long,
    op_set_global,
};
