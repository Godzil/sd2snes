/* sd2snes - SD card based universal cartridge for the SNES
   Copyright (C) 2009-2012 Maximilian Rehkopf <otakon@gmx.net>
   uC firmware portion

   Inspired by and based on code from sd2iec, written by Ingo Korb et al.
   See sdcard.c|h, config.h.

   FAT file system access based on code by ChaN, Jim Brain, Ingo Korb,
   see ff.c|h.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; version 2 of the License only.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

   fpga_spi.h: functions for SPI ctrl, SRAM interfacing and feature configuration
*/
/*

    SPI commands

    cmd param       function
   =============================================
    0t  bbhhll      set address to 0xbbhhll
                t = target
                target: 0 = RAM
                    1 = MSU Audio buffer
                    2 = MSU Data buffer
                targets 1 & 2 only require 2 address bytes to
                be written.

    10  bbhhll      set SNES input address mask to 0xbbhhll
    20  bbhhll      set SRAM address mask to 0xbbhhll

    3m  -       set mapper to m
                0=HiROM, 1=LoROM, 2=ExHiROM, 6=SF96, 7=Menu

    4s  -       trigger SD DMA (512b from SD to memory)
                                s: Bit 2 = partial, Bit 1:0 = target
                                target: see above

    60  xsssyeee    set SD DMA partial transfer parameters
                x: 0 = read from sector start (skip until
                       start offset reached)
                   8 = assume mid-sector position and read
                       immediately
                sss = start offset (msb first)
                y: 0 = skip rest of SD sector
                   8 = stop mid-sector if end offset reached
                eee = end offset (msb first)

    8p  -       read (RAM only)
                p: 0 = no increment after read
                   8 = increment after read

    9p  {xx}*       write xx
                p: i-tt
                tt = target (see above)
                i = increment (see above)

    E0  ssrr        set MSU-1 status register (=FPGA status [7:0])
                ss = bits to set in status register (1=set)
                rr = bits to reset in status register (1=reset)

    E1  -       pause DAC
    E2  -       resume/play DAC
    E3  -       reset DAC playback pointer (0)
    E4  hhll        set MSU read pointer

    E5  tt{7}       set RTC (SPC7110 format + 1000s of year,
                         nibbles packed)
                                eg 0x20111210094816 is 2011-12-10, 9:48:16
    E6  ssrr        set/reset BS-X status register [7:0]
    E7  -       reset SRTC state
    E8  -       reset DSP program and data ROM write pointers
    E9  hhmmllxxxx  write+incr. DSP program ROM (xxxx=dummy writes)
    EA  hhllxxxx    write+incr. DSP data ROM (xxxx=dummy writes)
    EB  -       put DSP into reset
    EC  -       release DSP from reset
    ED  -       set feature enable bits (see below)
    EE  -       set $213f override value (0=NTSC, 1=PAL)
    F0  -       receive test token (to see if FPGA is alive)
    F1  -       receive status (16bit, MSB first), see below

    F2  -       get MSU data address (32bit, MSB first)
    F3  -       get MSU audio track no. (16bit, MSB first)
    F4  -       get MSU volume (8bit)

    FE  -       get SNES master clock frequency (32bit, MSB first)
                measured 1x/sec
    FF  {xx}*       echo (returns the sent data in the next byte)

    FPGA status word:
    bit function
   ==========================================================================
     15 SD DMA busy (0=idle, 1=busy)
     14 DAC read pointer MSB
     13 MSU read pointer MSB
     12 reserved (0)
     11 reserved (0)
     10 reserved (0)
      9 reserved (0)
      8 reserved (0)
      7 reserved (0)
      6 reserved (0)
      5 MSU1 Audio request from SNES
      4 MSU1 Data request from SNES
      3 reserved (0)
      2 MSU1 Audio control status: 0=no repeat, 1=repeat
      1 MSU1 Audio control status: 0=pause, 1=play
      0 MSU1 Audio control request

    FPGA feature enable bits:
    bit function
   ==========================================================================
     7  -
     6  -
     5  -
     4  enable $213F override
     3  enable MSU1 registers
     2  enable SRTC registers
     1  enable ST0010 mapping
     0  enable DSPx mapping

*/

#include <arm/NXP/LPC17xx/LPC17xx.h>
#include "bits.h"
#include "fpga.h"
#include "config.h"
#include "uart.h"
#include "spi.h"
#include "fpga_spi.h"
#include "timer.h"
#include "sdnative.h"

void fpga_spi_init( void )
{
    spi_init();
    BITBAND( FPGA_MCU_RDY_REG->FIODIR, FPGA_MCU_RDY_BIT ) = 0;
}

void set_msu_addr( uint16_t address )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SETADDR | FPGA_TGT_MSUBUF );
    FPGA_TX_BYTE( ( address >> 8 ) & 0xff );
    FPGA_TX_BYTE( ( address ) & 0xff );
    FPGA_DESELECT();
}

void set_dac_addr( uint16_t address )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SETADDR | FPGA_TGT_DACBUF );
    FPGA_TX_BYTE( ( address >> 8 ) & 0xff );
    FPGA_TX_BYTE( ( address ) & 0xff );
    FPGA_DESELECT();
}

void set_mcu_addr( uint32_t address )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SETADDR | FPGA_TGT_MEM );
    FPGA_TX_BYTE( ( address >> 16 ) & 0xff );
    FPGA_TX_BYTE( ( address >> 8 ) & 0xff );
    FPGA_TX_BYTE( ( address ) & 0xff );
    FPGA_DESELECT();
}

void set_saveram_mask( uint32_t mask )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SETRAMMASK );
    FPGA_TX_BYTE( ( mask >> 16 ) & 0xff );
    FPGA_TX_BYTE( ( mask >> 8 ) & 0xff );
    FPGA_TX_BYTE( ( mask ) & 0xff );
    FPGA_DESELECT();
}

void set_rom_mask( uint32_t mask )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SETROMMASK );
    FPGA_TX_BYTE( ( mask >> 16 ) & 0xff );
    FPGA_TX_BYTE( ( mask >> 8 ) & 0xff );
    FPGA_TX_BYTE( ( mask ) & 0xff );
    FPGA_DESELECT();
}

void set_mapper( uint8_t val )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SETMAPPER( val ) );
    FPGA_DESELECT();
}

uint8_t fpga_test()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_TEST );
    uint8_t result = FPGA_RX_BYTE();
    FPGA_DESELECT();
    return result;
}

uint16_t fpga_status()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_GETSTATUS );
    uint16_t result = ( FPGA_RX_BYTE() ) << 8;
    result |= FPGA_RX_BYTE();
    FPGA_DESELECT();
    return result;
}

void fpga_set_sddma_range( uint16_t start, uint16_t end )
{
    printf( "%s %08X -> %08X\n", __func__, start, end );
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SDDMA_RANGE );
    FPGA_TX_BYTE( start >> 8 );
    FPGA_TX_BYTE( start & 0xff );
    FPGA_TX_BYTE( end >> 8 );
    FPGA_TX_BYTE( end & 0xff );
    FPGA_DESELECT();
}

void fpga_sddma( uint8_t tgt, uint8_t partial )
{
    //printf("%s %02X -> %02X\n", __func__, tgt, partial);
    //uint32_t test = 0;
    //uint8_t status = 0;
    BITBAND( SD_CLKREG->FIODIR, SD_CLKPIN ) = 0;
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SDDMA | ( tgt & 3 ) | ( partial ? FPGA_SDDMA_PARTIAL : 0 ) );
    FPGA_TX_BYTE( 0x00 ); /* dummy for falling DMA_EN edge */
    FPGA_DESELECT();
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_GETSTATUS );
    DBG_SD printf( "FPGA DMA request sent, wait for completion..." );

    while ( FPGA_RX_BYTE() & 0x80 )
    {
        FPGA_RX_BYTE(); /* eat the 2nd status byte */
    }

    DBG_SD printf( "...complete\n" );
    FPGA_DESELECT();
    BITBAND( SD_CLKREG->FIODIR, SD_CLKPIN ) = 1;
}

void dac_play()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_DACPLAY );
    FPGA_TX_BYTE( 0x00 ); /* latch reset */
    FPGA_DESELECT();
}

void dac_pause()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_DACPAUSE );
    FPGA_TX_BYTE( 0x00 ); /* latch reset */
    FPGA_DESELECT();
}

void dac_reset()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_DACRESETPTR );
    FPGA_TX_BYTE( 0x00 ); /* latch reset */
    FPGA_TX_BYTE( 0x00 ); /* latch reset */
    FPGA_DESELECT();
}

void msu_reset( uint16_t address )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_MSUSETPTR );
    FPGA_TX_BYTE( ( address >> 8 ) & 0xff ); /* address hi */
    FPGA_TX_BYTE( address & 0xff );    /* address lo */
    FPGA_TX_BYTE( 0x00 );              /* latch reset */
    FPGA_TX_BYTE( 0x00 );              /* latch reset */
    FPGA_DESELECT();
}

void set_msu_status( uint8_t set, uint8_t reset )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_MSUSETBITS );
    FPGA_TX_BYTE( set );
    FPGA_TX_BYTE( reset );
    FPGA_TX_BYTE( 0x00 ); /* latch reset */
    FPGA_DESELECT();
}

uint16_t get_msu_track()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_MSUGETTRACK );
    uint16_t result = ( FPGA_RX_BYTE() ) << 8;
    result |= FPGA_RX_BYTE();
    FPGA_DESELECT();
    return result;
}

uint32_t get_msu_offset()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_MSUGETADDR );
    uint32_t result = ( FPGA_RX_BYTE() ) << 24;
    result |= ( FPGA_RX_BYTE() ) << 16;
    result |= ( FPGA_RX_BYTE() ) << 8;
    result |= ( FPGA_RX_BYTE() );
    FPGA_DESELECT();
    return result;
}

uint32_t get_snes_sysclk()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_GETSYSCLK );
    FPGA_TX_BYTE( 0x00 ); /* dummy (copy current sysclk count to register) */
    uint32_t result = ( FPGA_RX_BYTE() ) << 24;
    result |= ( FPGA_RX_BYTE() ) << 16;
    result |= ( FPGA_RX_BYTE() ) << 8;
    result |= ( FPGA_RX_BYTE() );
    FPGA_DESELECT();
    return result;
}

void set_bsx_regs( uint8_t set, uint8_t reset )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_BSXSETBITS );
    FPGA_TX_BYTE( set );
    FPGA_TX_BYTE( reset );
    FPGA_TX_BYTE( 0x00 ); /* latch reset */
    FPGA_DESELECT();
}

void set_fpga_time( uint64_t time )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_RTCSET );
    FPGA_TX_BYTE( ( time >> 48 ) & 0xff );
    FPGA_TX_BYTE( ( time >> 40 ) & 0xff );
    FPGA_TX_BYTE( ( time >> 32 ) & 0xff );
    FPGA_TX_BYTE( ( time >> 24 ) & 0xff );
    FPGA_TX_BYTE( ( time >> 16 ) & 0xff );
    FPGA_TX_BYTE( ( time >> 8 ) & 0xff );
    FPGA_TX_BYTE( time & 0xff );
    FPGA_TX_BYTE( 0x00 );
    FPGA_DESELECT();
}

void fpga_reset_srtc_state()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SRTCRESET );
    FPGA_TX_BYTE( 0x00 );
    FPGA_TX_BYTE( 0x00 );
    FPGA_DESELECT();
}

void fpga_reset_dspx_addr()
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_DSPRESETPTR );
    FPGA_TX_BYTE( 0x00 );
    FPGA_TX_BYTE( 0x00 );
    FPGA_DESELECT();
}

void fpga_write_dspx_pgm( uint32_t data )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_DSPWRITEPGM );
    FPGA_TX_BYTE( ( data >> 16 ) & 0xff );
    FPGA_TX_BYTE( ( data >> 8 ) & 0xff );
    FPGA_TX_BYTE( ( data ) & 0xff );
    FPGA_TX_BYTE( 0x00 );
    FPGA_TX_BYTE( 0x00 );
    FPGA_DESELECT();
}

void fpga_write_dspx_dat( uint16_t data )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_DSPWRITEDAT );
    FPGA_TX_BYTE( ( data >> 8 ) & 0xff );
    FPGA_TX_BYTE( ( data ) & 0xff );
    FPGA_TX_BYTE( 0x00 );
    FPGA_TX_BYTE( 0x00 );
    FPGA_DESELECT();
}

void fpga_dspx_reset( uint8_t reset )
{
    FPGA_SELECT();
    FPGA_TX_BYTE( reset ? FPGA_CMD_DSPRESET : FPGA_CMD_DSPUNRESET );
    FPGA_TX_BYTE( 0x00 );
    FPGA_DESELECT();
}

void fpga_set_features( uint8_t feat )
{
    printf( "set features: %02x\n", feat );
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SETFEATURE );
    FPGA_TX_BYTE( feat );
    FPGA_DESELECT();
}

void fpga_set_213f( uint8_t data )
{
    printf( "set 213f: %d\n", data );
    FPGA_SELECT();
    FPGA_TX_BYTE( FPGA_CMD_SET213F );
    FPGA_TX_BYTE( data );
    FPGA_DESELECT();
}

