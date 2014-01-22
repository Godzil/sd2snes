#ifndef _ARM_BITS_H
#define _ARM_BITS_H

/* The classic macro */
#define BV(x) (1<<(x))

/* CM3 bit-bang access macro - no error checks! */
#define BITBANG(addr,bit) \
    (*((volatile unsigned long *)( \
                                   ((unsigned long)&(addr) & 0x01ffffff)*32 + \
                                   (bit)*4 + 0x02000000 + ((unsigned long)&(addr) & 0xfe000000) \
                                 )))

#define BITBANG_OFF(addr,offset,bit) \
    (*((volatile unsigned long *)( \
                                   (((unsigned long)&(addr) + offset) & 0x01ffffff)*32 + \
                                   (bit)*4 + 0x02000000 + (((unsigned long)&(addr) + offset) & 0xfe000000) \
                                 )))


#endif
