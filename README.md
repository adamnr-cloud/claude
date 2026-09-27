# GNU/Hurd console on Libreboot (coreboot framebuffer)

64-bit Guix Hurd boots on a Libreboot ThinkPad, but the screen freezes on the
last thing GRUB drew (for Guix: loading `exec.static`, the last multiboot
module) and no console ever appears. The same system works in QEMU.

This repository holds the missing pieces: five patches (three for gnumach, two
for the Hurd) and a Guix module that builds them into a Hurd system.

## Why the screen stays blank

A Libreboot `corebootfb` ROM leaves the display in a linear framebuffer mode.
Nothing sits behind the EGA text buffer at `0xb8000`. QEMU's default VGA has
one, which is why QEMU works.

| Step | What happens today | Fixed by |
|---|---|---|
| gnumach multiboot header | x86_64 `boothdr.S` sets flags `0x3` and never requests video information. Upstream `7ea3a05d` only changed the i386 header. | gnumach 0003 |
| GRUB (coreboot platform, `GRUB_MACHINE_HAS_VGA_TEXT=1`) | With no video request, or with an EGA-text preference, GRUB runs `set_video_mode("text")` and reports an EGA text buffer at `0xb8000`. A `set gfxpayload=keep` placed before `multiboot` is overwritten by that preference (`grub-core/loader/multiboot.c`). | gnumach 0003 (`--enable-linear-fb`) |
| gnumach kernel console (`kd.c`) | Writes only to `0xb8000`, so every kernel message is lost. This is also why upstream kept the EGA-text preference. | gnumach 0002 |
| multiboot struct | gnumach reads the RGB field layout at offset 110. GRUB writes it at 112, because its `multiboot_info` aligns the union. | gnumach 0001, hurd 0001 |
| console-client `fb` driver | Ignores the pitch (5504 bytes vs 1366×4 = 5464 on this panel, which shears every line), writes pixels as R,G,B bytes (swaps red and blue on XRGB8888), and has the same struct offset bug. | hurd 0001 |

The unpatched kernel is probably not stuck at `exec.static`. That's just the
last thing drawn before the kernel took over the screen and wrote to memory
nobody displays. With these patches you'll see what actually happens.

## Patches

`patches/gnumach` (against `v1.8+git20260224`, the version Guix packages;
also applies to upstream master as of May 2026):

1. **multiboot: Fix offset of the framebuffer colour information.** Adds the
   two bytes of padding GRUB leaves before the colour-info union.
2. **kd: Draw the console on a linear framebuffer when there is no text
   mode.** New `i386/i386at/kd_fb.c`. When the multiboot info describes an RGB
   framebuffer, `kd` works on an in-memory 80x25 EGA page, and changed cells
   are painted onto the framebuffer with an 8x16 CP437 font rendered from GNU
   Unifont. Nothing changes when GRUB reports text mode. Prints
   `kd: framebuffer at …` when active.
3. **multiboot: Request video information on x86_64, optionally prefer a
   framebuffer.** Adds the video fields to the x86_64 header. New configure
   switch `--enable-linear-fb` asks GRUB for a linear framebuffer; EGA text
   stays the default. With `--enable-linear-fb`, GRUB still falls back to text
   when no framebuffer exists (e.g. a `txtmode` ROM).

`patches/hurd` (against `6290b4cf`, Guix's pin; also applies to master as of
September 2026):

1. **console-client: Fix the framebuffer driver on real hardware.** Adds
   pitch, RGB field positions, 16/24/32 bpp, the correct offset, bounds
   checks, and compatibility with older kernels' `/dev/mbinfo`.
2. **console: Report `--width` with the width.** One-character fix in
   `fsysopts` output.

## Using it on Guix

In the **Hurd** system configuration:

```scheme
(use-modules (gnu) (gnu system hurd) (hurd-fb))

(operating-system-with-fb-console
  (operating-system
    ;; ... your existing Hurd configuration, unchanged ...
    ))
```

`operating-system-with-fb-console` swaps in `gnumach/fb` (patched, configured
with `--enable-linear-fb`) and `hurd/fb`. It also points the console, getty
and login services at `hurd/fb`, because the console client binary comes from
the console service's own `hurd` field, not the OS `hurd` field.

Rebuild the Hurd system the way you normally do, adding `-L` for this
repository, e.g.

```sh
guix system -L ~/src/hurd-libreboot/guix build --target=x86_64-gnu hurd.scm
```

gnumach and hurd get built locally; nothing else changes.

**The dual-boot entry in the Linux system's GRUB menu must point at the new
kernel.** If that `menu-entry` hard-codes `/gnu/store/…-gnumach…` paths, it
still boots the old kernel. Either update the store paths after every Hurd
rebuild, or refer to the Hurd system profile on the Hurd partition:
`/var/guix/profiles/system/kernel/boot/gnumach`, and
`/var/guix/profiles/system/hurd/hurd/*.static` for the modules.

After booting you should see kernel messages starting with
`kd: framebuffer at 0x…, 1366x768x32, pitch 5504, rgb 16:8 8:8 0:8`, then
the Hurd boot, then the console client's login on the same screen. If boot
stops somewhere, the last lines on screen now say where. With `--enable-kdb`
(Guix's default) a panic drops into `db>`, which also works on this screen.

The console client uses an 80x25 area by default. That limit comes from the
`/dev/vcs` translator, not the driver. To use the whole 1366x768 screen
(170x48), run `settrans -fg /dev/vcs /hurd/console --width=170 --height=48`.
I haven't tested that part.

## What was verified, and what was not

Verified here:

- x86_64 and i386 gnumach build with each patch, and each variant's multiboot
  header decodes as intended: flags `0x7`, preference `(1,80,25,0)` or
  `(0,0,0,32)`. Before the patches the x86_64 header read `0x3` with no video
  fields, the same as the installed binary.
- Boot through GRUB in QEMU (`tests/qemu-boot.sh`), screenshots in `docs/`:
  - `bochs-display` (framebuffer, no EGA text buffer): the unpatched kernel is
    blank, exactly your symptom (`docs/1-…`), and the patched kernel shows its
    console (`docs/2-…`).
  - Standard VGA: the patched kernel works in a VBE mode (`docs/3-…`), and
    the text-preference build still uses real text mode (`docs/4-…`).
- The GRUB offset was confirmed by reading `boot_info` from a running guest
  with gdb: the RGB layout sits at offset 112.
- The console-client driver was compiled with `-Wall -Wextra` against stub
  Hurd headers. A host harness (`tests/console-client-harness.c`) ran it on
  a simulated 1366x768 framebuffer with pitch 5504 and XRGB8888, reading
  `/dev/mbinfo` laid out as GRUB lays it out, from both old (118-byte) and new
  (120-byte) kernels (`docs/5-…`).
- All patches stack cleanly on top of Guix's own gnumach and hurd patches.

Not verified:

- **Real hardware.** Nothing here has run on the ThinkPad.
- **A full Hurd boot to login with the patched console client.** No Hurd
  userland was reachable from the build environment, so the patched driver
  only ran in the host harness.
- **GRUB's coreboot platform.** QEMU can't run coreboot here. The coreboot
  path (`cbfb` driver, `auto;text` mode string) was checked by reading GRUB
  2.12 sources; `bochs-display` stands in for the missing text buffer.
- **The Guix module.** It was checked against current Guix sources and parsed
  with Guile, but never evaluated by Guix itself.
- **Speed.** The kernel console maps the framebuffer uncached. A full-screen
  scroll repaints about 2000 cells, which may be visibly slow on real hardware
  during boot. It only affects kernel messages, not the console client.

## Tests and tools

- `tests/qemu-boot.sh KERNEL OUT.png [SECONDS]` boots a kernel through GRUB
  with no EGA text buffer (or `VGA="-vga std"`) and saves a screenshot.
- `tests/console-client-harness.c` is the host test for `console-client/fb.c`
  (build instructions at the top of the file).
- `tests/multiboot-header.py KERNEL` decodes a kernel's multiboot header and
  video preference.
- `tests/mkfont.py` regenerates `kd_fb_font.h` from `unifont.otf`.

## Upstream

The patches are written to be sent to `bug-hurd@gnu.org` as they are
(`git send-email patches/gnumach/*.patch`, and likewise for the hurd series).
gnumach 0001 and hurd 0001 fix real bugs whether or not the rest goes in.
