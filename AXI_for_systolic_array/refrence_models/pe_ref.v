//==============================================================
// REFERENCE MODEL 1
// PROCESSING ELEMENT REFERENCE MODEL
//==============================================================

localparam ACC_WIDTH = (2*DATA_WIDTH)+1;

//--------------------------------------------------------------
// Reference Registers
//--------------------------------------------------------------

reg signed [DATA_WIDTH-1:0] ref_weight;
reg signed [DATA_WIDTH-1:0] ref_a_pipe;

reg signed [(2*DATA_WIDTH)-1:0] ref_product;

reg signed [ACC_WIDTH-1:0] ref_psum_out;

reg signed [DATA_WIDTH-1:0] exp_a_out;
reg signed [ACC_WIDTH-1:0] exp_psum_out;


//--------------------------------------------------------------
// Reference Model
//--------------------------------------------------------------

task automatic pe_reference_model;

begin

    //----------------------------------------------------------
    // RESET
    //----------------------------------------------------------

    if(rst)
    begin

        ref_weight   = 0;
        ref_a_pipe   = 0;
        ref_product  = 0;
        ref_psum_out = 0;

        exp_a_out    = 0;
        exp_psum_out = 0;

    end

    //----------------------------------------------------------
    // NORMAL OPERATION
    //----------------------------------------------------------

    else
    begin

        //--------------------------------------
        // Load Weight
        //--------------------------------------

        if(load_weight)
            ref_weight = weight_in;

        //--------------------------------------
        // Forward activation
        //--------------------------------------

        exp_a_out = a_in;

        //--------------------------------------
        // Multiply
        //--------------------------------------

        ref_product = a_in * ref_weight;

        //--------------------------------------
        // Accumulate
        //--------------------------------------

        exp_psum_out = psum_in + ref_product;

    end

end

endtask
