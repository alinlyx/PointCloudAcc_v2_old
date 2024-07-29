// This is a simple example.
// You can make a your own header file and set its path to settings.
// (Preferences > Package Settings > Verilog Gadget > Settings - User)
//
//      "header": "Packages/Verilog Gadget/template/verilog_header.v"
//
// -----------------------------------------------------------------------------
// Copyright (c) 2014-2020 All rights reserved
// -----------------------------------------------------------------------------
// Author : zhouchch@pku.edu.cn
// File   : SHIFT.v
// Create : 2020-07-14 21:09:52
// Revise : 2020-08-13 10:33:19
// -----------------------------------------------------------------------------
module SHF #(
    parameter DATA_WIDTH        = 8,
    parameter SRAM_WIDTH        = 256,
    parameter ADDR_WIDTH        = 16,
    parameter SHIFTISA_WIDTH    = 128,
    parameter SHF_ADDR_WIDTH    = 8
    )(
    input                                       clk             ,
    input                                       rst_n           ,

    // Configure
    input                                       CCUSHF_CfgVld   ,
    output                                      SHFCCU_CfgRdy   ,
    input  [SHIFTISA_WIDTH              -1 : 0] CCUSHF_CfgInfo  ,
   
    output [ADDR_WIDTH                  -1 : 0] SHFGLB_InRdAddr     ,
    output                                      SHFGLB_InRdAddrVld  ,
    input                                       GLBSHF_InRdAddrRdy  ,
    input  [SRAM_WIDTH                  -1 : 0] GLBSHF_InRdDat      ,    
    input                                       GLBSHF_InRdDatVld   ,    
    output                                      SHFGLB_InRdDatRdy   ,     
    output [ADDR_WIDTH                  -1 : 0] SHFGLB_OutWrAddr    ,
    output [SRAM_WIDTH                  -1 : 0] SHFGLB_OutWrDat     ,   
    output                                      SHFGLB_OutWrDatVld  ,
    input                                       GLBSHF_OutWrDatRdy   

);

//=====================================================================================================================
// Constant Definition :
//=====================================================================================================================
localparam IDLE    = 3'b000;
localparam COMP    = 3'b010;
localparam WAITFNH = 3'b100;

localparam NUM = SRAM_WIDTH / DATA_WIDTH;
//=====================================================================================================================
// Variable Definition :
//=====================================================================================================================

genvar                                  gv_i;
wire                                    overflow_CntAddr;
reg                                     overflow_CntAddr_s1;
wire                                    overflow_CntAddr_s2;
wire                                    rdy_s0;
wire                                    rdy_s1;
wire                                    rdy_s2;
wire                                    vld_s0;
wire                                    vld_s1;
reg                                     vld_s2;
wire                                    handshake_s0;
wire                                    handshake_s1;
wire                                    handshake_s2;
wire                                    ena_s0;
wire                                    ena_s1;
wire                                    ena_s2;
wire [ADDR_WIDTH                -1 : 0] CntAddr;
reg  [ADDR_WIDTH                -1 : 0] CntAddr_s1;
wire [ADDR_WIDTH                -1 : 0] CntAddr_s2;

wire [SHF_ADDR_WIDTH + 1        -1 : 0] fifo_count;
wire                                    shift_din_rdy;
wire                                    shift_dout_vld;
wire                                    shift_dout_rdy;
wire [DATA_WIDTH*NUM            -1 : 0] shift_dout;

wire [ADDR_WIDTH                -1 : 0] MaxCntWrAddr;
wire [ADDR_WIDTH                -1 : 0] CntWrAddr;
wire                                    overflow_CntWrAddr;

wire [ADDR_WIDTH                -1 : 0] CCUSHF_CfgInAddr;
wire [ADDR_WIDTH                -1 : 0] CCUSHF_CfgOutAddr;
wire [ADDR_WIDTH                -1 : 0] CCUSHF_CfgNum;
wire [4                         -1 : 0] CCUSHF_CfgByteWrIncr;
wire [ADDR_WIDTH                -1 : 0] CCUSHF_CfgByteWrStep;
wire [ADDR_WIDTH                -1 : 0] CCUSHF_CfgWrBackStep;
wire                                    CCUSHF_CfgStop;
//=====================================================================================================================
// Logic Design: Cfg
//=====================================================================================================================
assign {
    CCUSHF_CfgWrBackStep,   // 16
    CCUSHF_CfgByteWrStep,   // 16
    CCUSHF_CfgByteWrIncr,   // 4
    CCUSHF_CfgInAddr,       // 16
    CCUSHF_CfgOutAddr,      // 16
    CCUSHF_CfgNum           // 16
} = CCUSHF_CfgInfo[SHIFTISA_WIDTH -1 : 16];
assign CCUSHF_CfgStop = CCUSHF_CfgInfo[9]; //[8]==1: Rst, [9]==1: Stop
//=====================================================================================================================
// Logic Design: FSM
//=====================================================================================================================
reg [ 3 -1:0 ]state;
reg [ 3 -1:0 ]next_state;
always @(*) begin
    case ( state )
        IDLE :  if(SHFCCU_CfgRdy & (CCUSHF_CfgVld & !CCUSHF_CfgStop))// 
                    next_state <= COMP; //
                else
                    next_state <= IDLE;

        COMP:   if(CCUSHF_CfgVld)
                    next_state <= IDLE;
                else if( overflow_CntAddr & handshake_s0 ) // wait pipeline finishing
                    next_state <= WAITFNH;
                else
                    next_state <= COMP;

        WAITFNH:if(CCUSHF_CfgVld)
                    next_state <= IDLE;
                else if (overflow_CntWrAddr & handshake_s2)
                    next_state <= IDLE;
                else
                    next_state <= WAITFNH;
                
        default: next_state <= IDLE;
    endcase
end

always @ ( posedge clk or negedge rst_n ) begin
    if ( !rst_n ) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

assign SHFCCU_CfgRdy = state==IDLE;

//=====================================================================================================================
// Logic Design: s0
//=====================================================================================================================
// Combinational Logic

// HandShake
assign rdy_s0       = state == IDLE? 0 : GLBSHF_InRdAddrRdy;
assign handshake_s0 = rdy_s0 & vld_s0;
assign ena_s0       = handshake_s0 | ~vld_s0;

assign vld_s0       = state == COMP;
wire [ADDR_WIDTH     -1 : 0] MaxCntAddr = CCUSHF_CfgNum -1;

// Reg Update
counter#(
    .COUNT_WIDTH ( ADDR_WIDTH )
)u0_counter_CntAddr(
    .CLK       ( clk            ),
    .RESET_N   ( rst_n          ),
    .CLEAR     ( state == IDLE  ),
    .DEFAULT   ( {ADDR_WIDTH{1'b0}}),
    .INC       ( handshake_s0   ),
    .DEC       ( 1'b0           ),
    .MIN_COUNT ( {ADDR_WIDTH{1'b0}}),
    .MAX_COUNT (  MaxCntAddr    ),
    .OVERFLOW  ( overflow_CntAddr),
    .UNDERFLOW (                ),
    .COUNT     ( CntAddr        )
);

//=====================================================================================================================
// Logic Design: s1
//=====================================================================================================================
// Combinational Logic
assign SHFGLB_InRdAddr      = state == IDLE? 0 : CCUSHF_CfgInAddr + CntAddr;
assign SHFGLB_InRdAddrVld   = state == IDLE? 0 : vld_s0;

// HandShake
assign rdy_s1       = shift_din_rdy;
assign handshake_s1 = rdy_s1 & vld_s1;
assign ena_s1       = handshake_s1 | ~vld_s1;
assign vld_s1       = state == IDLE? 0 : GLBSHF_InRdDatVld;

assign SHFGLB_InRdDatRdy = state == IDLE? 0 : rdy_s1;

// Reg Update
always @ ( posedge clk or negedge rst_n ) begin
    if ( !rst_n ) begin
        overflow_CntAddr_s1 <= 0;
        CntAddr_s1          <= 0;
    end else if( state == IDLE) begin
        overflow_CntAddr_s1 <= 0;
        CntAddr_s1          <= 0;
    end else if(ena_s1) begin
        overflow_CntAddr_s1 <= overflow_CntAddr;
        CntAddr_s1          <= CntAddr;
    end
end

//=====================================================================================================================
// Logic Design: s2
//=====================================================================================================================

// HandShake
assign rdy_s2       = state == IDLE? 0 : GLBSHF_OutWrDatRdy;
assign handshake_s2 = rdy_s2 & vld_s2;
assign ena_s2       = handshake_s2 | ~vld_s2;
assign vld_s2       = shift_dout_vld;

// Reg Update
SHIFT #(
    .DATA_WIDTH(DATA_WIDTH  ),
    .WIDTH     (NUM         ), // 32
    .ADDR_WIDTH(SHF_ADDR_WIDTH)
) u_SHIFT (               
    .clk                 ( clk           ),
    .rst_n               ( rst_n         ),
    .Rst                 ( state == IDLE ),   
    .ByteWrIncr          ( CCUSHF_CfgByteWrIncr[0] ),  
    .ByteWrStep          ( CCUSHF_CfgByteWrStep[0 +: SHF_ADDR_WIDTH] ),
    .WrBackStep          ( CCUSHF_CfgWrBackStep[0 +: SHF_ADDR_WIDTH] ),
    .shift_din           ( state == IDLE? 0 : GLBSHF_InRdDat),
    .shift_din_vld       ( vld_s1        ),
    .shift_din_last      ( overflow_CntAddr_s1), // for pop last NUM data (triangle)
    .shift_din_rdy       ( shift_din_rdy ),                        
    .shift_dout          ( shift_dout    ),
    .shift_dout_vld      ( shift_dout_vld),
    .shift_dout_rdy      ( shift_dout_rdy),
    .fifo_count          ( fifo_count    ) 
);
assign shift_dout_rdy = rdy_s2;

assign SHFGLB_OutWrDat      = state == IDLE? 0 : vld_s2? shift_dout : 0;
assign SHFGLB_OutWrAddr     = state == IDLE? 0 : CCUSHF_CfgOutAddr + CntWrAddr; 
assign SHFGLB_OutWrDatVld   = state == IDLE? 0 : vld_s2;

assign MaxCntWrAddr = CCUSHF_CfgByteWrIncr[0]?
                           CCUSHF_CfgNum -1 // format 0 -> 1
                           : CCUSHF_CfgNum -1 - NUM; // format 2/3 -> 0
counter#(
    .COUNT_WIDTH ( ADDR_WIDTH )
)u0_counter_CntWrAddr(
    .CLK       ( clk            ),
    .RESET_N   ( rst_n          ),
    .CLEAR     ( state == IDLE  ),
    .DEFAULT   ( {ADDR_WIDTH{1'b0}}),
    .INC       ( SHFGLB_OutWrDatVld & GLBSHF_OutWrDatRdy   ),
    .DEC       ( 1'b0           ),
    .MIN_COUNT ( {ADDR_WIDTH{1'b0}}),
    .MAX_COUNT ( MaxCntWrAddr   ),
    .OVERFLOW  ( overflow_CntWrAddr),
    .UNDERFLOW (                ),
    .COUNT     ( CntWrAddr      )
);


endmodule
