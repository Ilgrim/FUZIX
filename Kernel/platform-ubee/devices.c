#include <kernel.h>
#include <tty.h>
#include <version.h>
#include <kdata.h>
#include <devfd.h>
#include <devhd.h>
#include <devsys.h>
#include <devlpr.h>
#include <devtty.h>

struct devsw dev_tab[] =  /* The device driver switch table */
{
  /* 0: /dev/fd		Floppy disc block devices */
  {  fd_open,     no_close,     fd_read,   fd_write,   no_ioctl  },
  /* 1: /dev/hd		Hard disc block devices */
  {  hd_open,     no_close,     hd_read,   hd_write,   no_ioctl  },
  /* 2: /dev/tty	TTY devices */
  {  tty_open,    tty_close,    tty_read,  tty_write,  tty_ioctl },
  /* 3: /dev/lpr	Printer devices */
  {  lpr_open,    lpr_close,    no_rdwr,   lpr_write,  no_ioctl  },
  /* 4: /dev/mem etc	System devices (one offs) */
  {  no_open,     no_close,     sys_read,  sys_write,  sys_ioctl },
  /* Pack to 7 with nxio if adding private devices and start at 8 */
};

bool validdev(uint16_t dev)
{
    /* This is a bit uglier than needed but the right hand side is
       a constant this way */
    if(dev > ((sizeof(dev_tab)/sizeof(struct devsw)) << 8) - 1)
	return false;
    else
        return true;
}

void device_init(void)
{
  int i;
  /* Time of day clock */
  inittod();
  /* Add 64 swaps (2MB) */
  for (i = MAX_SWAPS - 1 ; i >= 0; i--)
    swapmap_add(i);
}
