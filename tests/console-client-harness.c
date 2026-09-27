/* Host test for console-client/fb.c on a 1366x768 panel with pitch 5504.

   Build from a Hurd checkout with the patches applied:

     python3 tests/mkfont.py | sed 1,4d > kdfont.h
     gcc -w -D_GNU_SOURCE -DDEFAULT_VGA_FONT_DIR=\"/x/\" -I$HURD/console-client -I$HURD \
         -Itests/console-client-stub -I. -o harness tests/console-client-harness.c
     ./harness && convert fb.ppm fb.png  */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <wchar.h>
#include "fb.c"
#include "kdfont.h"

char *vga_videomem;
void vga_memset (void *s, int c, size_t n) { memset (s, c, n); }
void vga_memmove (void *d, const void *s, size_t n) { memmove (d, s, n); }
error_t driver_add_display (struct display_ops *ops, void *h) { return 0; }
error_t driver_remove_display (struct display_ops *ops, void *h) { return 0; }
static struct bdf_glyph glyphs[256];
void bdf_destroy (bdf_font_t f) {}
bdf_error_t bdf_read (FILE *f, bdf_font_t *font, int *line) { return 0; }
void bdf_sort_glyphs (bdf_font_t f) {}
error_t get_privileged_ports (mach_port_t *h, mach_port_t *d) { *d = 1; return 0; }
mach_port_t mach_task_self (void) { return 0; }
kern_return_t mach_port_deallocate (mach_port_t a, mach_port_t b) { return 0; }
kern_return_t vm_deallocate (mach_port_t t, vm_address_t a, vm_size_t s) { return 0; }
kern_return_t device_open (mach_port_t m, int mode, const char *n, mach_port_t *d) { *d = 2; return 0; }
/* The kernel's copy of GRUB's multiboot info (120 bytes, GRUB layout).  */
static unsigned char grub_mbi[120];
static uint32_t kernel_size = 120;
kern_return_t device_read (mach_port_t d, int mode, int rec, uint32_t n, io_buf_ptr_t *data, uint32_t *cnt)
{ if (n > kernel_size) return 2501; memcpy (*data, grub_mbi, n); *cnt = n; return 0; }
static void make_grub_mbi (void)
{
  uint32_t flags = 0x1000; uint64_t addr = 0xe0000000; uint32_t pitch = 5504, w = 1366, h = 768;
  memcpy (grub_mbi + 0, &flags, 4);
  memcpy (grub_mbi + 88, &addr, 8); memcpy (grub_mbi + 96, &pitch, 4);
  memcpy (grub_mbi + 100, &w, 4); memcpy (grub_mbi + 104, &h, 4);
  grub_mbi[108] = 32; grub_mbi[109] = 1;
  unsigned char col[6] = { 16, 8, 8, 8, 0, 8 };
  memcpy (grub_mbi + 112, col, 6);
}
struct bdf_glyph *bdf_find_glyph (bdf_font_t f, int enc, int ienc)
{ return (enc >= 0 && enc < 256) ? &glyphs[enc] : NULL; }

static void put (void *h, const char *str, int row)
{
  conchar_t buf[200]; int n = strlen (str);
  memset (buf, 0, sizeof buf);
  for (int i = 0; i < n; i++) { buf[i].chr = str[i]; buf[i].attr.fgcol = i % 8 ? 7 : 1 + (row % 6); buf[i].attr.bgcol = 0; }
  fb_display_write (h, buf, n, 0, row);
}

int main (void)
{
  for (int i = 0; i < 256; i++) { glyphs[i].bitmap = (unsigned char *) kdfb_font[i]; }
  /* What GRUB passes on a 1366x768 ThinkPad per the host's efifb log.  */
  make_grub_mbi ();
  kernel_size = 118;	/* old kernel: struct ends right after colour info */
  fb_get_multiboot_params ();
  printf ("old kernel: type=%d %dx%dx%d pitch=%d r%d:%d g%d:%d b%d:%d\n", fb_type, fb_width, fb_height, fb_bpp, fb_pitch,
	  fb_red_pos, fb_red_size, fb_green_pos, fb_green_size, fb_blue_pos, fb_blue_size);
  kernel_size = 120;
  fb_get_multiboot_params ();
  printf ("new kernel: type=%d %dx%dx%d pitch=%d r%d:%d g%d:%d b%d:%d\n", fb_type, fb_width, fb_height, fb_bpp, fb_pitch,
	  fb_red_pos, fb_red_size, fb_green_pos, fb_green_size, fb_blue_pos, fb_blue_size);
  vga_videomem = calloc (1, fb_pitch * fb_height);
  struct fb_display *disp = calloc (1, sizeof *disp);
  disp->width = fb_width; disp->height = fb_height;
  fb_set_dimension (disp, 170, 48);
  char line[200];
  for (int r = 0; r < 48; r++) {
    snprintf (line, sizeof line, "row %02d  The quick brown fox jumps over the lazy dog | pitch 5504 != 1366*4 | %s", r,
	      "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!");
    put (disp, line, r);
  }
  fb_display_scroll (disp, 2);
  put (disp, "after scrolling by two lines: last row", 47);
  FILE *f = fopen ("fb.ppm", "wb");
  fprintf (f, "P6 %d %d 255\n", fb_width, fb_height);
  for (int y = 0; y < fb_height; y++)
    for (int x = 0; x < fb_width; x++) {
      uint32_t p = *(uint32_t *) (vga_videomem + y * fb_pitch + x * 4);
      unsigned char rgb[3] = { p >> 16, p >> 8, p };
      fwrite (rgb, 1, 3, f);
    }
  fclose (f);
  /* Padding bytes between width*4 and pitch must stay untouched.  */
  for (int y = 0; y < fb_height; y++)
    for (int b = fb_width * 4; b < fb_pitch; b++)
      if (vga_videomem[y * fb_pitch + b]) { printf ("padding written at row %d\n", y); return 1; }
  printf ("ok\n");
  return 0;
}
