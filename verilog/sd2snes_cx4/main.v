`timescale 1 ns / 1 ns
//////////////////////////////////////////////////////////////////////////////////
// Company: Rehkopf
// Engineer: Rehkopf
// 
// Create Date:    01:13:46 05/09/2009 
// Design Name: 
// Module Name:    main 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: Master Control FSM
//
// Dependencies: address
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module main(
  /* input clock */
  input CLKIN,

  /* SNES signals */
  input [23:0] SNES_ADDR_IN,
  input SNES_READ,
  input SNES_WRITE,
  input SNES_CS,
  inout [7:0] SNES_DATA,
  input SNES_CPU_CLK,
  input SNES_REFRESH,
  output SNES_IRQ,
  output SNES_DATABUS_OE,
  output SNES_DATABUS_DIR,
  input SNES_SYSCLK,

  input [7:0] SNES_PA,
  input SNES_PARD,
  input SNES_PAWR,
  
  /* SRAM signals */
  /* Bus 1: PSRAM, 128Mbit, 16bit, 70ns */
  inout [15:0] ROM_DATA,
  output [22:0] ROM_ADDR,
  output ROM_CE,
  output ROM_OE,
  output ROM_WE,
  output ROM_BHE,
  output ROM_BLE,

  /* Bus 2: SRAM, 4Mbit, 8bit, 45ns */
  inout [7:0] RAM_DATA,
  output [18:0] RAM_ADDR,
  output RAM_CE,
  output RAM_OE,
  output RAM_WE,

  /* MCU signals */
  input SPI_MOSI,
  inout SPI_MISO,
  input SPI_SS,
  inout SPI_SCK,
  input MCU_OVR,
  output MCU_RDY,
  
  output DAC_MCLK,
  output DAC_LRCK,
  output DAC_SDOUT,

  /* SD signals */
  input [3:0] SD_DAT,
  inout SD_CMD,
  inout SD_CLK,

  /* debug */
  output p113_out
);

wire CLK2;

reg [23:0] SNES_ADDR_r [2:0];
always @(posedge CLK2) begin
  SNES_ADDR_r[2] <= SNES_ADDR_r[1];
  SNES_ADDR_r[1] <= SNES_ADDR_r[0];
  SNES_ADDR_r[0] <= SNES_ADDR_IN;
end
wire [23:0] SNES_ADDR = SNES_ADDR_r[2] & SNES_ADDR_r[1];

wire [7:0] CX4_SNES_DATA_IN;
wire [7:0] CX4_SNES_DATA_OUT;

wire [7:0] spi_cmd_data;
wire [7:0] spi_param_data;
wire [7:0] spi_input_data;
wire [31:0] spi_byte_cnt;
wire [2:0] spi_bit_cnt;
wire [23:0] MCU_ADDR;
wire [2:0] MAPPER;
wire [23:0] SAVERAM_MASK;
wire [23:0] ROM_MASK;
wire [7:0] SD_DMA_SRAM_DATA;
wire [1:0] SD_DMA_TGT;
wire [10:0] SD_DMA_PARTIAL_START;
wire [10:0] SD_DMA_PARTIAL_END;

wire [10:0] dac_addr;
wire [7:0] msu_volumerq_out;
wire [6:0] msu_status_out;
wire [31:0] msu_addressrq_out;
wire [15:0] msu_trackrq_out;
wire [13:0] msu_write_addr;
wire [13:0] msu_ptr_addr;
wire [7:0] MSU_SNES_DATA_IN;
wire [7:0] MSU_SNES_DATA_OUT;
wire [5:0] msu_status_reset_bits;
wire [5:0] msu_status_set_bits;

wire [23:0] MAPPED_SNES_ADDR;
wire ROM_ADDR0;

wire [23:0] cx4_datrom_data;
wire [9:0] cx4_datrom_addr;
wire cx4_datrom_we;

sd_dma snes_sd_dma(
  .CLK(CLK2),
  .SD_DAT(SD_DAT),
  .SD_CLK(SD_CLK),
  .SD_DMA_EN(SD_DMA_EN),
  .SD_DMA_STATUS(SD_DMA_STATUS),
  .SD_DMA_SRAM_WE(SD_DMA_SRAM_WE),
  .SD_DMA_SRAM_DATA(SD_DMA_SRAM_DATA),
  .SD_DMA_NEXTADDR(SD_DMA_NEXTADDR),
  .SD_DMA_PARTIAL(SD_DMA_PARTIAL),
  .SD_DMA_PARTIAL_START(SD_DMA_PARTIAL_START),
  .SD_DMA_PARTIAL_END(SD_DMA_PARTIAL_END),
  .SD_DMA_START_MID_BLOCK(SD_DMA_START_MID_BLOCK),
  .SD_DMA_END_MID_BLOCK(SD_DMA_END_MID_BLOCK)
);

wire SD_DMA_TO_ROM = (SD_DMA_STATUS && (SD_DMA_TGT == 2'b00));

dac snes_dac(
  .clkin(CLK2),
  .sysclk(SNES_SYSCLK),
  .mclk(DAC_MCLK),
  .lrck(DAC_LRCK),
  .sdout(DAC_SDOUT),
  .we(SD_DMA_TGT==2'b01 ? SD_DMA_SRAM_WE : 1'b1),
  .pgm_address(dac_addr),
  .pgm_data(SD_DMA_SRAM_DATA),
  .DAC_STATUS(DAC_STATUS),
  .volume(msu_volumerq_out),
  .vol_latch(msu_volume_latch_out),
  .play(dac_play),
  .reset(dac_reset)
);

msu snes_msu (
  .clkin(CLK2),
  .enable(msu_enable),
  .pgm_address(msu_write_addr),
  .pgm_data(SD_DMA_SRAM_DATA),
  .pgm_we(SD_DMA_TGT==2'b10 ? SD_DMA_SRAM_WE : 1'b1),
  .reg_addr(SNES_ADDR[2:0]),
  .reg_data_in(MSU_SNES_DATA_IN),
  .reg_data_out(MSU_SNES_DATA_OUT),
  .reg_oe(SNES_READ),
  .reg_we(SNES_WRITE),
  .status_out(msu_status_out),
  .volume_out(msu_volumerq_out),
  .volume_latch_out(msu_volume_latch_out),
  .addr_out(msu_addressrq_out),
  .track_out(msu_trackrq_out),
  .status_reset_bits(msu_status_reset_bits),
  .status_set_bits(msu_status_set_bits),
  .status_reset_we(msu_status_reset_we),
  .msu_address_ext(msu_ptr_addr),
  .msu_address_ext_write(msu_addr_reset)
);

spi snes_spi(
  .clk(CLK2),
  .MOSI(SPI_MOSI),
  .MISO(SPI_MISO),
  .SSEL(SPI_SS),
  .SCK(SPI_SCK),
  .cmd_ready(spi_cmd_ready),
  .param_ready(spi_param_ready),
  .cmd_data(spi_cmd_data),
  .param_data(spi_param_data),
  .endmessage(spi_endmessage),
  .startmessage(spi_startmessage),
  .input_data(spi_input_data),
  .byte_cnt(spi_byte_cnt),
  .bit_cnt(spi_bit_cnt)
);

reg [7:0] MCU_DINr;
wire [7:0] MCU_DOUT;

mcu_cmd snes_mcu_cmd(
  .clk(CLK2),
  .snes_sysclk(SNES_SYSCLK),
  .cmd_ready(spi_cmd_ready),
  .param_ready(spi_param_ready),
  .cmd_data(spi_cmd_data),
  .param_data(spi_param_data),
  .mcu_mapper(MAPPER),
  .mcu_write(MCU_WRITE),
  .mcu_data_in(MCU_DINr),
  .mcu_data_out(MCU_DOUT),
  .spi_byte_cnt(spi_byte_cnt),
  .spi_bit_cnt(spi_bit_cnt),
  .spi_data_out(spi_input_data),
  .addr_out(MCU_ADDR),
  .saveram_mask_out(SAVERAM_MASK),
  .rom_mask_out(ROM_MASK),
  .SD_DMA_EN(SD_DMA_EN),
  .SD_DMA_STATUS(SD_DMA_STATUS),
  .SD_DMA_NEXTADDR(SD_DMA_NEXTADDR),
  .SD_DMA_SRAM_DATA(SD_DMA_SRAM_DATA),
  .SD_DMA_SRAM_WE(SD_DMA_SRAM_WE),
  .SD_DMA_TGT(SD_DMA_TGT),
  .SD_DMA_PARTIAL(SD_DMA_PARTIAL),
  .SD_DMA_PARTIAL_START(SD_DMA_PARTIAL_START),
  .SD_DMA_PARTIAL_END(SD_DMA_PARTIAL_END),
  .SD_DMA_START_MID_BLOCK(SD_DMA_START_MID_BLOCK),
  .SD_DMA_END_MID_BLOCK(SD_DMA_END_MID_BLOCK),
  .dac_addr_out(dac_addr),
  .DAC_STATUS(DAC_STATUS),
//  .dac_volume_out(dac_volume),
//  .dac_volume_latch_out(dac_vol_latch),
  .dac_play_out(dac_play),
  .dac_reset_out(dac_reset),
  .msu_addr_out(msu_write_addr),
  .MSU_STATUS(msu_status_out),
  .msu_status_reset_out(msu_status_reset_bits),
  .msu_status_set_out(msu_status_set_bits),
  .msu_status_reset_we(msu_status_reset_we),
  .msu_volumerq(msu_volumerq_out),
  .msu_addressrq(msu_addressrq_out),
  .msu_trackrq(msu_trackrq_out),
  .msu_ptr_out(msu_ptr_addr),
  .msu_reset_out(msu_addr_reset),
  .mcu_rrq(MCU_RRQ),
  .mcu_wrq(MCU_WRQ),
  .mcu_rq_rdy(MCU_RDY),
  .use_msu1(use_msu1),
  .cx4_datrom_addr_out(cx4_datrom_addr),
  .cx4_datrom_data_out(cx4_datrom_data),
  .cx4_datrom_we_out(cx4_datrom_we),
  .cx4_reset_out(cx4_reset),
  .region_out(mcu_region)
);

wire [7:0] DCM_STATUS;
// dcm1: dfs 4x
my_dcm snes_dcm(
  .CLKIN(CLKIN),
  .CLKFX(CLK2),
  .LOCKED(DCM_LOCKED),
  .RST(DCM_RST),
  .STATUS(DCM_STATUS)
);

assign DCM_RST=0;

reg [7:0] SNES_PARDr;
reg [7:0] SNES_PAWRr;
reg [7:0] SNES_READr;
reg [7:0] SNES_WRITEr;
reg [7:0] SNES_CPU_CLKr;

wire SNES_FAKE_CLK = &SNES_CPU_CLKr[2:1];
//wire SNES_FAKE_CLK = ~(SNES_READ & SNES_WRITE);

reg SNES_DEADr;
initial SNES_DEADr = 0;

wire SNES_PARD_start = (SNES_PARDr[7:1] == 7'b1111110);
wire SNES_PAWR_start = (SNES_PAWRr[7:1] == 7'b0000001);
wire SNES_RD_start = (SNES_READr[7:1] == 7'b1111110);
wire SNES_WR_start = (SNES_WRITEr[7:1] == 7'b1111110);
wire SNES_WR_end = (SNES_WRITEr[7:1] == 7'b0000001);
wire SNES_cycle_start = ((SNES_CPU_CLKr[7:2] & SNES_CPU_CLKr[6:1]) == 6'b000001);
wire SNES_cycle_end = ((SNES_CPU_CLKr[7:2] & SNES_CPU_CLKr[6:1]) == 6'b111110);

always @(posedge CLK2) begin
  SNES_PARDr <= {SNES_PARDr[6:0], SNES_PARD};
end

always @(posedge CLK2) begin
  SNES_PAWRr <= {SNES_PAWRr[6:0], SNES_PAWR};
  SNES_READr <= {SNES_READr[6:0], SNES_READ};
  SNES_WRITEr <= {SNES_WRITEr[6:0], SNES_WRITE};
  SNES_CPU_CLKr <= {SNES_CPU_CLKr[6:0], SNES_CPU_CLK};
end

address snes_addr(
  .CLK(CLK2),
  .MAPPER(MAPPER),
  .SNES_ADDR(SNES_ADDR), // requested address from SNES
  .SNES_PA(SNES_PA),
  .SNES_CS(SNES_CS),
  .ROM_ADDR(MAPPED_SNES_ADDR),   // Address to request from SRAM (active low)
  .ROM_SEL(ROM_SEL),     // which SRAM unit to access
  .IS_SAVERAM(IS_SAVERAM),
  .IS_ROM(IS_ROM),
  .IS_WRITABLE(IS_WRITABLE),
  .SAVERAM_MASK(SAVERAM_MASK),
  .ROM_MASK(ROM_MASK),
  .use_msu1(use_msu1),
  //MSU-1
  .msu_enable(msu_enable),
  //CX4
  .cx4_enable(cx4_enable),
  .cx4_vect_enable(cx4_vect_enable),
  //region
  .r213f_enable(r213f_enable),
  //CMD Interface
  .snescmd_rd_enable(snescmd_rd_enable),
  .snescmd_wr_enable(snescmd_wr_enable)
);

reg [7:0] CX4_DINr;
wire [23:0] CX4_ADDR;

cx4 snes_cx4 (
    .DI(CX4_SNES_DATA_IN), 
    .DO(CX4_SNES_DATA_OUT), 
    .ADDR(SNES_ADDR[12:0]), 
    .CS(cx4_enable), 
    .SNES_VECT_EN(cx4_vect_enable), 
    .nRD(SNES_READ), 
    .nWR(SNES_WRITE), 
    .CLK(CLK2), 
    .DATROM_DI(cx4_datrom_data), 
    .DATROM_WE(cx4_datrom_we), 
    .DATROM_ADDR(cx4_datrom_addr), 
    .BUS_DI(CX4_DINr), 
    .BUS_ADDR(CX4_ADDR), 
    .BUS_RRQ(CX4_RRQ), 
    .BUS_RDY(CX4_RDY), 
    .cx4_active(cx4_active)
    );
	 
parameter MODE_SNES = 1'b0;
parameter MODE_MCU = 1'b1;

parameter ST_IDLE         = 21'b000000000000000000001;
parameter ST_SNES_RD_ADDR = 21'b000000000000000000010;
parameter ST_SNES_RD_WAIT = 21'b000000000000000000100;
parameter ST_SNES_RD_END  = 21'b000000000000000001000;
parameter ST_SNES_WR_ADDR = 21'b000000000000000010000;
parameter ST_SNES_WR_WAIT1= 21'b000000000000000100000;
parameter ST_SNES_WR_DATA = 21'b000000000000001000000;
parameter ST_SNES_WR_WAIT2= 21'b000000000000010000000;
parameter ST_SNES_WR_END  = 21'b000000000000100000000;
parameter ST_MCU_RD_ADDR  = 21'b000000000001000000000;
parameter ST_MCU_RD_WAIT  = 21'b000000000010000000000;
parameter ST_MCU_RD_WAIT2 = 21'b000000000100000000000;
parameter ST_MCU_RD_END   = 21'b000000001000000000000;
parameter ST_MCU_WR_ADDR  = 21'b000000010000000000000;
parameter ST_MCU_WR_WAIT  = 21'b000000100000000000000;
parameter ST_MCU_WR_WAIT2 = 21'b000001000000000000000;
parameter ST_MCU_WR_END   = 21'b000010000000000000000;
parameter ST_CX4_RD_ADDR  = 21'b000100000000000000000;
parameter ST_CX4_RD_WAIT  = 21'b001000000000000000000;
parameter ST_CX4_RD_END   = 21'b010000000000000000000;

parameter ROM_RD_WAIT = 4'h1;
parameter ROM_RD_WAIT_MCU = 4'h6;
parameter ROM_WR_WAIT = 4'h4;
parameter ROM_WR_WAIT1 = 4'h3;
parameter ROM_WR_WAIT2 = 4'h1;
parameter ROM_WR_WAIT_MCU = 4'h5;
parameter ROM_RD_WAIT_CX4 = 4'h7;

parameter SNES_DEAD_TIMEOUT = 17'd88000; // 1ms

reg [20:0] STATE;
initial STATE = ST_IDLE;

reg [7:0] SNES_DINr;
reg [7:0] SNES_DOUTr;
reg [7:0] ROM_DOUTr;

assign MSU_SNES_DATA_IN = SNES_DATA;
assign CX4_SNES_DATA_IN = SNES_DATA;

reg [7:0] r213fr;
reg r213f_forceread;
reg [2:0] r213f_delay;
reg [1:0] r213f_state;
initial r213fr = 8'h55;
initial r213f_forceread = 0;
initial r213f_state = 2'b01;
initial r213f_delay = 3'b011;

reg[7:0] snescmd_regs[15:0];

assign SNES_DATA = (snescmd_rd_enable & ~SNES_PARD) ? snescmd_regs[SNES_ADDR[3:0]]
                   :(r213f_enable & ~SNES_PARD & ~r213f_forceread) ? r213fr
                   :(~SNES_READ ^ (r213f_forceread & r213f_enable & ~SNES_PARD))
                                ? (msu_enable ? MSU_SNES_DATA_OUT
                                  :cx4_enable ? CX4_SNES_DATA_OUT
											 :(cx4_active & cx4_vect_enable) ? CX4_SNES_DATA_OUT
                                  :SNES_DOUTr /*(ROM_ADDR0 ? ROM_DATA[7:0] : ROM_DATA[15:8])*/) : 8'bZ;

reg [3:0] ST_MEM_DELAYr;
reg MCU_RD_PENDr;
reg MCU_WR_PENDr;
reg CX4_RD_PENDr;
reg [23:0] ROM_ADDRr;
reg NEED_SNES_ADDRr;
always @(posedge CLK2) begin
  if(SNES_cycle_end) NEED_SNES_ADDRr <= 1'b1;
  else if(STATE & (ST_SNES_RD_END | ST_SNES_WR_END)) NEED_SNES_ADDRr <= 1'b0;
end

wire IS_CART = IS_ROM | IS_SAVERAM | IS_WRITABLE;

reg RQ_MCU_RDYr;
initial RQ_MCU_RDYr = 1'b1;
assign MCU_RDY = RQ_MCU_RDYr;

reg RQ_CX4_RDYr;
initial RQ_CX4_RDYr = 1'b1;
assign CX4_RDY = RQ_CX4_RDYr;

reg ROM_SAr;
initial ROM_SAr = 1'b1;
wire ROM_SA = ROM_SAr;

reg ROM_CAr;
initial ROM_CAr = 1'b0;
wire ROM_CA = ROM_CAr;

reg [23:0] CX4_ADDRr;

assign ROM_ADDR  = (SD_DMA_TO_ROM) ? MCU_ADDR[23:1] : ROM_CA ? CX4_ADDRr[23:1] : ROM_SA ? MAPPED_SNES_ADDR[23:1] : ROM_ADDRr[23:1];
assign ROM_ADDR0 = (SD_DMA_TO_ROM) ? MCU_ADDR[0] : ROM_CA ? CX4_ADDRr[0] : ROM_SA ? MAPPED_SNES_ADDR[0] : ROM_ADDRr[0];

reg ROM_WEr;
initial ROM_WEr = 1'b1;
reg ROM_DOUT_ENr;
initial ROM_DOUT_ENr = 1'b0;

reg[17:0] SNES_DEAD_CNTr;
initial SNES_DEAD_CNTr = 0;

always @(posedge CLK2) begin
  if(cx4_active) begin
    if(CX4_RRQ) begin
	   CX4_RD_PENDr <= 1'b1;
		RQ_CX4_RDYr <= 1'b0;
		CX4_ADDRr <= CX4_ADDR;
	 end else if(STATE == ST_CX4_RD_END) begin
	   CX4_RD_PENDr <= 1'b0;
		RQ_CX4_RDYr <= 1'b1;
	 end
  end else begin
    CX4_RD_PENDr <= 1'b0;
	 RQ_CX4_RDYr <= 1'b1;
  end
end

always @(posedge CLK2) begin
  if(MCU_RRQ) begin
    MCU_RD_PENDr <= 1'b1;
    RQ_MCU_RDYr <= 1'b0;
    ROM_ADDRr <= MCU_ADDR;
  end else if(MCU_WRQ) begin
    MCU_WR_PENDr <= 1'b1;
    RQ_MCU_RDYr <= 1'b0;
    ROM_ADDRr <= MCU_ADDR;
  end else if(STATE & (ST_MCU_RD_END | ST_MCU_WR_END)) begin
    MCU_RD_PENDr <= 1'b0;
    MCU_WR_PENDr <= 1'b0;
    RQ_MCU_RDYr <= 1'b1;
  end
end

always @(posedge CLK2) begin
  if(~SNES_CPU_CLK) SNES_DEAD_CNTr <= SNES_DEAD_CNTr + 1;
  else SNES_DEAD_CNTr <= 17'h0;
end

always @(posedge CLK2) begin
  if(SNES_DEAD_CNTr > SNES_DEAD_TIMEOUT) SNES_DEADr <= 1'b1;
  else if(SNES_CPU_CLK) SNES_DEADr <= 1'b0;
end

always @(posedge CLK2) begin
  if(SNES_DEADr & SNES_CPU_CLK) STATE <= ST_IDLE; // interrupt+restart an ongoing MCU access when the SNES comes alive
  else
  case(STATE)
    ST_IDLE: begin
	   ROM_SAr <= 1'b1;
		ROM_CAr <= 1'b0;
		ROM_DOUT_ENr <= 1'b0;
		if(cx4_active) begin
        if(CX4_RD_PENDr) STATE <= ST_CX4_RD_ADDR;
		end else if(SNES_cycle_start & ~SNES_WRITE) begin
		  STATE <= ST_SNES_WR_ADDR;
		  if(IS_SAVERAM | IS_WRITABLE) begin
		    ROM_WEr <= 1'b0;
          ROM_DOUT_ENr <= 1'b1;
        end
		end else if(SNES_cycle_start) begin
		  STATE <= ST_SNES_RD_ADDR;		  
//        STATE <= ST_SNES_RD_END;
		end else if(SNES_DEADr & MCU_RD_PENDr) begin
		  STATE <= ST_MCU_RD_ADDR;
		end else if(SNES_DEADr & MCU_WR_PENDr) begin
		  STATE <= ST_MCU_WR_ADDR;
		end
	 end
	 ST_SNES_RD_ADDR: begin
	   ST_MEM_DELAYr <= ROM_RD_WAIT;
		STATE <= ST_SNES_RD_WAIT;
	 end
	 ST_SNES_RD_WAIT: begin
	   ST_MEM_DELAYr <= ST_MEM_DELAYr - 1;
           if(ST_MEM_DELAYr == 0) begin
             STATE <= ST_SNES_RD_END;
             SNES_DOUTr <= (ROM_ADDR0 ? ROM_DATA[7:0] : ROM_DATA[15:8]);
           end
           else STATE <= ST_SNES_RD_WAIT;
	 end
	 
	 ST_SNES_WR_ADDR: begin
           ROM_DOUT_ENr <= 1'b1;
	   ST_MEM_DELAYr <= ROM_WR_WAIT1;
	   STATE <= ST_SNES_WR_WAIT1;
	 end
	 ST_SNES_WR_WAIT1: begin
	   ST_MEM_DELAYr <= ST_MEM_DELAYr - 1;
		if(ST_MEM_DELAYr == 0) begin
		  ST_MEM_DELAYr <= ROM_WR_WAIT2;
        STATE <= ST_SNES_WR_WAIT2;
		  ROM_DOUTr <= SNES_DATA;
		end
		else STATE <= ST_SNES_WR_WAIT1;
	 end
	 ST_SNES_WR_WAIT2: begin
	   ST_MEM_DELAYr <= ST_MEM_DELAYr - 1;
		if(ST_MEM_DELAYr == 0) begin
                  STATE <= ST_SNES_WR_END;
                  ROM_WEr <= 1'b1;
		end
		else STATE <= ST_SNES_WR_WAIT2;
         end
         ST_SNES_RD_END, ST_SNES_WR_END: begin
//         ROM_DOUT_ENr <= 1'b0;
           if(MCU_RD_PENDr) begin
             STATE <= ST_MCU_RD_ADDR;
           end else if(MCU_WR_PENDr) begin
             STATE <= ST_MCU_WR_ADDR;
           end else STATE <= ST_IDLE;
         end
    ST_MCU_RD_ADDR: begin
      ROM_SAr <= 1'b0;
		ST_MEM_DELAYr <= ROM_RD_WAIT_MCU;
		STATE <= ST_MCU_RD_WAIT;
	 end
	 ST_MCU_RD_WAIT: begin
	   ST_MEM_DELAYr <= ST_MEM_DELAYr - 1;
		if(ST_MEM_DELAYr == 0) begin
        STATE <= ST_MCU_RD_END;
		end
		else STATE <= ST_MCU_RD_WAIT;
	 end
	 ST_MCU_RD_END: begin
      MCU_DINr <= ROM_ADDRr[0] ? ROM_DATA[7:0] : ROM_DATA[15:8];
	   STATE <= ST_IDLE;
	 end
	 
	 ST_MCU_WR_ADDR: begin
      ROM_DOUTr <= MCU_DOUT;
      ROM_SAr <= 1'b0;
	   ST_MEM_DELAYr <= ROM_WR_WAIT_MCU;
		STATE <= ST_MCU_WR_WAIT;
		ROM_WEr <= 1'b0;
	 end
	 ST_MCU_WR_WAIT: begin
           ST_MEM_DELAYr <= ST_MEM_DELAYr - 1;
           ROM_DOUT_ENr <= 1'b1;
           if(ST_MEM_DELAYr == 0) begin
		  ROM_WEr <= 1'b1;
		  STATE <= ST_MCU_WR_END;
		end
		else STATE <= ST_MCU_WR_WAIT;	 
	 end
	 ST_MCU_WR_END: begin
		ROM_DOUT_ENr <= 1'b0;
	   STATE <= ST_IDLE;
	 end
	 ST_CX4_RD_ADDR: begin
	   ROM_CAr <= 1'b1;
	   ST_MEM_DELAYr <= ROM_RD_WAIT_CX4;
		STATE <= ST_CX4_RD_WAIT;
	 end
	 ST_CX4_RD_WAIT: begin
	   ST_MEM_DELAYr <= ST_MEM_DELAYr - 1;
		if(ST_MEM_DELAYr == 0) begin
                  CX4_DINr <= CX4_ADDRr[0] ? ROM_DATA[7:0] : ROM_DATA[15:8];
		  STATE <= ST_CX4_RD_END;
		end
		else STATE <= ST_CX4_RD_WAIT;
	 end
	 ST_CX4_RD_END: begin
	   ROM_CAr <= 1'b0;
	   STATE <= ST_IDLE;
	 end
	 
  endcase
end

always @(posedge CLK2) begin
  if(SNES_cycle_end) r213f_forceread <= 1'b1;
  else if(SNES_PARD_start & r213f_enable) begin
    r213f_delay <= 3'b000;
    r213f_state <= 2'b10;
  end else if(r213f_state == 2'b10) begin
    r213f_delay <= r213f_delay - 1;
    if(r213f_delay == 3'b000) begin
      r213f_forceread <= 1'b0;
      r213f_state <= 2'b01;
      r213fr <= {SNES_DATA[7:5], mcu_region, SNES_DATA[3:0]};
    end
  end
end

always @(posedge CLK2) begin
  if(SNES_WR_end & snescmd_wr_enable) begin
    snescmd_regs[SNES_ADDR[3:0]] <= SNES_DATA;
  end
end

reg ROM_WE_1;
reg MCU_WRITE_1;

always @(posedge CLK2) begin
  ROM_WE_1 <= ROM_WE;
  MCU_WRITE_1<= MCU_WRITE;
end

assign ROM_DATA[7:0] = ROM_ADDR0
                       ?(SD_DMA_TO_ROM ? (!MCU_WRITE_1 ? MCU_DOUT : 8'bZ)
							                   /*: ((~SNES_WRITE & (IS_WRITABLE | IS_FLASHWR)) ? SNES_DATA */
                                        : (ROM_DOUT_ENr ? ROM_DOUTr : 8'bZ) //)
                        )
                       :8'bZ;

assign ROM_DATA[15:8] = ROM_ADDR0 ? 8'bZ
                        :(SD_DMA_TO_ROM ? (!MCU_WRITE_1 ? MCU_DOUT : 8'bZ)
								                 /*:  ((~SNES_WRITE & (IS_WRITABLE | IS_FLASHWR)) ? SNES_DATA */
                                         : (ROM_DOUT_ENr ? ROM_DOUTr : 8'bZ) //)
                         );

assign ROM_WE = SD_DMA_TO_ROM
                ?MCU_WRITE
                :/*(SNES_FAKE_CLK & (IS_WRITABLE | IS_FLASHWR)) ? SNES_WRITE :*/ ROM_WEr;

// OE always active. Overridden by WE when needed.
assign ROM_OE = 1'b0;

assign ROM_CE = 1'b0;

assign ROM_BHE = /*(~SD_DMA_TO_ROM & ~ROM_WE & ~ROM_SA) ?*/ ROM_ADDR0 /*: 1'b0*/;
assign ROM_BLE = /*(~SD_DMA_TO_ROM & ~ROM_WE & ~ROM_SA) ?*/ !ROM_ADDR0 /*: 1'b0*/;

assign SNES_DATABUS_OE = msu_enable ? 1'b0 :
                         cx4_enable ? 1'b0 :
								 (cx4_active & cx4_vect_enable) ? 1'b0 :
                         r213f_enable & !SNES_PARD ? 1'b0 :
								 (snescmd_wr_enable | snescmd_rd_enable) & !SNES_PARD ? 1'b0 :
                         ((IS_ROM & SNES_CS)
                          |(!IS_ROM & !IS_SAVERAM & !IS_WRITABLE)
                          |(SNES_READr[0] & SNES_WRITEr[0])
                         );

assign SNES_DATABUS_DIR = (!SNES_READr[0] | (!SNES_PARD & (r213f_enable | snescmd_rd_enable)))
                           ? 1'b1 ^ (r213f_forceread & r213f_enable & ~SNES_PARD)
                           : 1'b0;

assign SNES_IRQ = 1'b0;

assign p113_out = 1'b0;

/*
wire [35:0] CONTROL0;

icon icon (
    .CONTROL0(CONTROL0) // INOUT BUS [35:0]
);

ila ila (
    .CONTROL(CONTROL0), // INOUT BUS [35:0]
    .CLK(CLK2), // IN
    .TRIG0(SNES_ADDR), // IN BUS [23:0]
    .TRIG1(SNES_DATA), // IN BUS [7:0]
    .TRIG2({SNES_READ, SNES_WRITE, SNES_CPU_CLK, SNES_cycle_start, SNES_cycle_end, SNES_DEADr, MCU_RRQ, MCU_WRQ, MCU_RDY, cx4_active, ROM_WE, ROM_DOUT_ENr, ROM_SA, CX4_RRQ, CX4_RDY, ROM_CA}), // IN BUS [15:0]
    .TRIG3(ROM_ADDRr), // IN BUS [23:0]
    .TRIG4(CX4_ADDRr), // IN BUS [23:0]
    .TRIG5(ROM_DATA), // IN BUS [15:0]
    .TRIG6(CX4_DINr), // IN BUS [7:0]
    .TRIG7(STATE) // IN BUS [21:0]
);*/
/*
ila ila (
    .CONTROL(CONTROL0), // INOUT BUS [35:0]
    .CLK(CLK2), // IN
    .TRIG0(SNES_ADDR), // IN BUS [23:0]
    .TRIG1(SNES_DATA), // IN BUS [7:0]
    .TRIG2({SNES_READ, SNES_WRITE, SNES_CPU_CLK, SNES_cycle_start, SNES_cycle_end, SNES_DEADr, MCU_RRQ, MCU_WRQ, MCU_RDY, ROM_WEr, ROM_WE, ROM_DOUT_ENr, ROM_SA, DBG_mcu_nextaddr, SNES_DATABUS_DIR, SNES_DATABUS_OE}),	 // IN BUS [15:0]
    .TRIG3({bsx_data_ovr, SPI_SCK, SPI_MISO, SPI_MOSI, spi_cmd_ready, spi_param_ready, spi_input_data, SD_DAT}), // IN BUS [17:0]
    .TRIG4(ROM_ADDRr), // IN BUS [23:0]
    .TRIG5(ROM_DATA), // IN BUS [15:0]
    .TRIG6(MCU_DINr), // IN BUS [7:0]
	 .TRIG7(spi_byte_cnt[3:0])
);
*/
/*
ila_srtc ila (
    .CONTROL(CONTROL0), // INOUT BUS [35:0]
    .CLK(CLK2), // IN
    .TRIG0(SD_DMA_DBG_cyclecnt), // IN BUS [23:0]
    .TRIG1(SD_DMA_SRAM_DATA), // IN BUS [7:0]
    .TRIG2({SPI_SCK, SPI_MOSI, SPI_MISO, spi_cmd_ready, SD_DMA_SRAM_WE, SD_DMA_EN, SD_CLK, SD_DAT, SD_DMA_NEXTADDR, SD_DMA_STATUS, 3'b000}),	 // IN BUS [15:0]
    .TRIG3({spi_cmd_data, spi_param_data}), // IN BUS [17:0]
    .TRIG4(ROM_ADDRr), // IN BUS [23:0]
    .TRIG5(ROM_DATA), // IN BUS [15:0]
    .TRIG6(MCU_DINr), // IN BUS [7:0]
	 .TRIG7(ST_MEM_DELAYr)
);
*/

endmodule
