`define Decoupled_Definition\
    decoupled_bit data; \
    ctrl_t valid;       \
    ctrl_t ready;       \
                        \
    modport Master(     \
        output data,    \
        output valid,   \
        input ready     \
    );                  \
                        \
    modport Slave(      \
        input data,     \
        input valid,    \
        output ready    \
    );

/*
interface R_reply_ift;

    typedef struct {
        data_t rdata;
        resp_t rresp;
    } decoupled_bit;

    `Decoupled_Definition

endinterface
*/