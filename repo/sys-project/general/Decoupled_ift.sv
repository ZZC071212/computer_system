interface Decoupled_ift #(
    parameter DATA_WIDTH = 64
);

    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic ctrl_t;
    data_t data;
    ctrl_t valid;
    ctrl_t ready;

    modport Master(
        output data,
        output valid,
        input ready
    );

    modport Slave(
        input data,
        input valid,
        output ready
    );
    
endinterface //interfacename