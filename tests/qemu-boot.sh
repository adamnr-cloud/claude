#!/bin/bash
# Boot a gnumach image through GRUB in QEMU and save a screenshot.
#
#   tests/qemu-boot.sh KERNEL OUT.png [SECONDS]
#
# By default the display is bochs-display, which, like coreboot with a
# framebuffer (Libreboot corebootfb ROMs), gives a linear framebuffer with
# nothing behind the EGA text buffer at 0xb8000.  Set VGA="-vga std" to
# test a classic BIOS machine instead.
#
# Needs qemu-system-x86_64, grub-mkrescue (grub-pc-bin), xorriso, mtools
# and python3-pil.  Without Hurd modules the kernel ends in the debugger
# with "No bootstrap code loaded", which is enough to see its console.
set -e
K=$1; OUT=$2; T=${3:-12}
d=$(mktemp -d)
mkdir -p "$d/boot/grub"
cp "$K" "$d/boot/gnumach"
cat > "$d/boot/grub/grub.cfg" <<CFG
set timeout=0
insmod all_video
menuentry gnumach { multiboot /boot/gnumach }
CFG
grub-mkrescue -o "$d/boot.iso" "$d" >/dev/null 2>&1
(sleep "$T"; echo "screendump $d/screen.ppm"; sleep 1; echo quit) |
  timeout $((T + 20)) qemu-system-x86_64 -m 2048 -cdrom "$d/boot.iso" \
    ${VGA:--vga none -device bochs-display,xres=1280,yres=800} \
    -display none -monitor stdio >/dev/null 2>&1 || true
python3 -c "from PIL import Image; Image.open('$d/screen.ppm').save('$OUT')"
rm -rf "$d"
