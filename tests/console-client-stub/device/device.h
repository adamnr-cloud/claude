#include <mach.h>
#define D_READ 1
typedef char *io_buf_ptr_t;
kern_return_t device_open (mach_port_t, int, const char *, mach_port_t *);
kern_return_t device_read (mach_port_t, int, int, uint32_t, io_buf_ptr_t *, uint32_t *);
