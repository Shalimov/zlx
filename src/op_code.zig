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
    op_popn,

    op_jump_if_true,
    op_jump_if_false,
    op_jump_frwd,
    op_jump_bkwd,

    // Wide operations
    op_wide, // modifier that instructs that the next operation will be 2 bytes size
    op_constant,
    op_define_global,
    op_get_global,
    op_set_global,
    // Note that there is no op_define_local, because locals are comp time definitions
    // Hence no reasone pass it to VM
    op_get_local,
    op_set_local,
};
