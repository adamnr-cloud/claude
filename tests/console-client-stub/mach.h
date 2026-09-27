#ifndef STUB_MACH_H
#define STUB_MACH_H
#include <stdint.h>
#include <stddef.h>
typedef unsigned int mach_port_t; typedef unsigned long vm_address_t; typedef unsigned long vm_size_t; typedef int kern_return_t;
mach_port_t mach_task_self (void);
kern_return_t mach_port_deallocate (mach_port_t, mach_port_t);
kern_return_t vm_deallocate (mach_port_t, vm_address_t, vm_size_t);
#endif
