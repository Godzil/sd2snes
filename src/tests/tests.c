/* ___DISCLAIMER___ */

#include <arm/NXP/LPC17xx/LPC17xx.h>
#include "bits.h"
#include "config.h"
#include "uart.h"
#include "timer.h"
#include "led.h"
#include "cli.h"
#include "fpga.h"
#include "fpga_spi.h"
#include "ff.h"
#include "fileops.h"
#include "crc32.h"
#include "diskio.h"
#include "cic.h"
#include "rtc.h"
#include "memory.h"
#include "snes.h"
#include "cli.h"

#include "tests.h"

#define PROGRESS	("-\\|/")

int test_sd() {
  printf("SD test... please insert card\n=============================\n");
  while(disk_status(0) & (STA_NOINIT|STA_NODISK)) cli_entrycheck();

  file_open((uint8_t*)"/sd2snes/testfile.bin", FA_WRITE | FA_CREATE_ALWAYS);
  if(file_res) {
    printf("could not open /sd2snes/testfile.bin: Error %d\n", file_res);
    printf("FAILED\n\n\n");
    return FAILED;
  }
  uint32_t testval = 0x55AA55AA;
  uint32_t crc = 0;
  uint32_t count, blkcount;
  for(count=0; count < 8192; count++) {
    for(blkcount=0; blkcount < 512; blkcount++) {
      file_buf[blkcount] = testval&0xff;
      crc=crc32_update(crc, testval&0xff);
      testval ^= (crc * (count + blkcount + 7)) - 1;
    }
    file_write();
  }
  printf("crc1 = %08lx ", crc);
  file_close();
  file_open((uint8_t*)"/sd2snes/testfile.bin", FA_READ);
  uint32_t crc2 = 0;
  for(count=0; count < 8192; count++) {
    file_read();
    for(blkcount=0; blkcount < 512; blkcount++) {
      testval = file_buf[blkcount];
      crc2 = crc32_update(crc2, testval&0xff);
    }
  }
  file_close();
  printf("crc2 = %08lx ", crc2);
  if(crc==crc2) {
    printf("  PASSED\n\n\n");
    return PASSED;
  } else {
    printf("  FAILED\n\n\n");
    return FAILED;
  }
}

int test_cic() {
  int cic_state = get_cic_state();
  printf("CIC Test:\n=========\n");
  printf("Current CIC state: %s\n", get_cic_statename(cic_state));
  if(cic_state == CIC_FAIL) {
    printf("CIC reports error, push reset...\n");
    while((cic_state = get_cic_state()) == CIC_FAIL);
  }
  if(cic_state == CIC_OK) {
    printf("CIC reports OK; no pair mode available. Provoking CIC error...\n");
    cic_pair(1,1);
    delay_ms(200);
    cic_init(0);
    printf("new CIC state: %s\n", get_cic_statename(get_cic_state()));
    if(get_cic_state() == CIC_FAIL) {
      printf("***Please reset SNES***\n");
      int failcount=2;
      while(failcount--) {
        while(get_cic_state() == CIC_FAIL);
        delay_ms(200);
      }
      if(get_cic_state() != CIC_FAIL) {
        printf("PASSED\n\n\n");
        return PASSED;
      }
      printf("CIC did not recover properly.\nFAILED\n");
      return FAILED;
    }
    printf("FAILED\n\n\n");
    return FAILED;
  }
  if(cic_state == CIC_SCIC) {
    printf("CIC reports OK; pair mode available. Switching to pair mode...\n");
    cic_init(1);
    delay_ms(100);
    cic_pair(0,0);
    delay_ms(1000);
    printf("new CIC state: %s\n", get_cic_statename(cic_state = get_cic_state()));
    if(get_cic_state() != CIC_PAIR) {
      printf("FAILED to switch to pair mode!!!\n");
      return FAILED;
    }
  }
  if(cic_state == CIC_PAIR) {
    cic_init(1);
    cic_pair(0,0);
    printf("cycling modes, observe power LED color\n");
    for(cic_state = 0; cic_state < 17; cic_state++) {
      cic_videomode(cic_state & 1);
      delay_ms(200);
    }
  }
  printf("PASSED\n\n\n");
  return PASSED;
}

int test_rtc() {
  struct tm time;
  printf("RTC Test\n========\n");
  printf("setting clock to 2011-01-01 00:00:00\n");
  set_bcdtime(0x20110101000000LL);
  printf("waiting 5 seconds\n");
  delay_ms(5000);
//  uint64_t newtime = get_bcdtime();
  printf("new time: ");
  read_rtc(&time);
  printtime(&time);
  if((get_bcdtime() & 0xffffffffffffff) >= 0x20110101000004LL) {
    printf("PASSED\n\n\n");
    return PASSED;
  } else printf("FAILED\n\n\n");
  return FAILED;
}

int test_fpga() {
  printf("FPGA test\n=========\n");
  printf("configuring fpga...\n");
  fpga_pgm((uint8_t*)"/sd2snes/test.bit");
  printf("basic communication test...");
  if(fpga_test() != FPGA_TEST_TOKEN) {
    printf("FAILED\n\n\n");
    return FAILED;
  } else printf("PASSED\n\n\n");
  return PASSED;
}

/*************************************************************************************/
/*************************************************************************************/

typedef struct memory_test
{
  char name[20];
  int a_len;
  int d_len;

  unsigned int (*read)(unsigned int addr);
  void (*write)(unsigned int addr, unsigned int data);
  void (*open)(void);
  void (*close)(void);
} memory_test;

/*************************************************************************************/

void rom_open(void)
{
  snes_reset(1);
  fpga_select_mem(0);
  FPGA_DESELECT();
  delay_ms(1);
  FPGA_SELECT();
  delay_ms(1);
}
void rom_close(void)
{
}

unsigned int rom_read(unsigned int addr)
{
  return sram_readbyte(addr);
}

void rom_write(unsigned int addr, unsigned int data)
{
  sram_writebyte(data, addr);
}

memory_test rom = {
  .name = "RAM0 (128Mbit)",
  .a_len = 22,
  .d_len = 8,
  .read = rom_read,
  .write = rom_write,
  .open = rom_open,
  .close = rom_close,
};

/*************************************************************************************/

void sram_open(void)
{
  snes_reset(1);
  fpga_select_mem(1);
}

void sram_close(void)
{
}

unsigned int sram_read(unsigned int addr)
{
  return sram_readbyte(addr);
}

void sram_write(unsigned int addr, unsigned int data)
{
  sram_writebyte(data, addr);
}

memory_test sram = 
{
  .name = "RAM1(4Mbit)",
  .a_len = 19,
  .d_len = 8,
  .read = sram_read,
  .write = sram_write,
  .open = sram_open,
  .close = sram_close,
};

int do_test(memory_test *test)
{
  int i, j, read, want;
  int ret = 0;
  int a_mask = (1 << test->a_len) - 1;
  int d_mask = (1 << test->d_len) - 1;

  test->open();

  printf("-- Will test %s\n", test->name);
  printf("---- Fill with AA55  ");
  test->write(0, 0xAA);
  for (i = 1; i < a_mask; i++)
  {
    if((i&0xffff) == 0)printf("\x8%c", PROGRESS[(i>>16)&3]);
    want = (i&1)?0x55:0xAA;
    test->write(i, want);

    want = ((i-1)&1)?0x55:0xAA;
    read = test->read(i-1);

    if (read != want)
    {
      printf("Failed [@%8X Want: %02X Get: %02X]", i-1, want, read);
      ret |= 1;
      break;
    }
  }

  printf("Ok \n---- Fill with 00    ");
  for (i = 0; i < a_mask; i++)
  {
    if((i&0xffff) == 0)printf("\x8%c", PROGRESS[(i>>16)&3]);
    test->write(i, 0);
  }

  printf("Ok \n---- Check data lines...\n"
         "-----           ");
  for (i = 0; i < test->d_len; i++) printf("%X", i);
  printf("\n");
  /* Check on 4 addresses, taken evenly */
#define TEST_NUM (10)

  for (j = 0; j < TEST_NUM; j ++)
  {
    printf("----- %8X [", j * a_mask/TEST_NUM);
    for (i = 0; i < test->d_len; i++)
    {
      read = test->read(j * a_mask/TEST_NUM);
      if ((test->read(j * a_mask/TEST_NUM) & (1<<i)) != 0)
      {
        printf("1", read);
        ret |= 2;
        goto next_data;
      }
      test->write(j * a_mask/TEST_NUM, (1<<i));
      read = test->read(j * a_mask/TEST_NUM);
      if (read == 0)
      {
        printf("0");
        ret |= 4;
        goto next_data;
      }
      printf("x");

next_data:
      test->write(j * a_mask/4, 0);
    }
    printf("]\n");
  }


  test->close();
  return ret;
}

int test_mem()
{
  int ret = PASSED;
  printf("RAM test\n========\n");

  if (do_test(&rom) != 0)
    ret = FAILED;
  if (do_test(&sram) != 0);
    ret = FAILED;
  return PASSED;
}


int test_clk() {
  uint32_t sysclk[4];
  int32_t diff, max_diff = 0;
  int i, error=0;
  printf("sysclk test\n===========\n");
  printf("measuring SNES clock...\n");
  for(i=0; i<4; i++) {
    sysclk[i]=get_snes_sysclk();
    if(sysclk[i] < 21000000 || sysclk[i] > 22000000) error = 1;
    printf("%lu Hz ", sysclk[i]);
    if(i) {
      diff = sysclk[i] - sysclk[i-1];
      if(diff < 0) diff = -diff;
      if(diff > max_diff) max_diff = diff;
      printf("diff = %ld  max = %ld", diff, max_diff);
    }
    printf("\n");
    delay_ms(1010);
  }
  if(error) {
    printf("clock frequency out of range!\n");
  }
  if(diff > 1000000) {
    printf("clock variation too great!\n");
    error = 1;
  }
  printf("   CPUCLK: %lu\n", get_snes_cpuclk());
  printf("  READCLK: %lu\n", get_snes_readclk());
  printf(" WRITECLK: %lu\n", get_snes_writeclk());
  printf("  PARDCLK: %lu\n", get_snes_pardclk());
  printf("  PAWRCLK: %lu\n", get_snes_pawrclk());
  printf("  REFRCLK: %lu\n", get_snes_refreshclk());
  printf("ROMSELCLK: %lu\n", get_snes_romselclk());
  if(error) {
    printf("FAILED\n\n\n");
    return FAILED;
  }
  printf("PASSED\n\n\n");
  return PASSED;
}
