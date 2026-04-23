`include"mem_ift.vh"
`include"bus_struct.vh"

interface Mem_ift #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64
);

    import BusPack::*;

    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [DATA_WIDTH/8-1:0] mask_t;
    typedef logic ctrl_t;

    typedef struct {
        addr_t raddr;
    } RrequestBits;

    typedef struct {
        data_t rdata;
        resp_t rresp;
    } RreplyBits;

    typedef struct {
        addr_t waddr;
        data_t wdata;
        mask_t wmask;
    } WrequestBits;

    typedef struct {
        resp_t bresp;
    } WreplyBits;

    `Mem_Member_Definition(RrequestBits, r_request);
    `Mem_Member_Definition(RreplyBits, r_reply);
    `Mem_Member_Definition(WrequestBits, w_request);
    `Mem_Member_Definition(WreplyBits, w_reply);

    modport Master(
        `Master_Modport_Declaration(r_request),
        `Slave_Modport_Declaration(r_reply),
        `Master_Modport_Declaration(w_request),
        `Slave_Modport_Declaration(w_reply)
    );

    modport Slave(
        `Slave_Modport_Declaration(r_request),
        `Master_Modport_Declaration(r_reply),
        `Slave_Modport_Declaration(w_request),
        `Master_Modport_Declaration(w_reply)
    );

endinterface