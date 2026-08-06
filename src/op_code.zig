pub const OpCode = enum {
    op_constant_long,
    op_constant,
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
    op_define_global,
    op_define_global_long,
    op_pop,
};
