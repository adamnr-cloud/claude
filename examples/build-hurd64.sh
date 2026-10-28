#!/bin/bash
# build-hurd64.sh — build and install 64-bit (x86_64-gnu) GNU/Hurd to /hurd,
# then reconfigure the Guix Linux system so GRUB picks up the new menu entry.
#
# Usage: sudo bash /home/adam/guix-backup/build-hurd64.sh
#
# What it does:
#   1. Back up configs to ~/guix-backup/backups/
#   2. guix system init --target=x86_64-pc-gnu hurd-config.scm /hurd
#        Builds 64-bit Hurd (with the hurd-fb module from HURD_FB_MODULES)
#        and installs it to /hurd.  --no-bootloader leaves the MBR alone,
#        but also skips writing /hurd/boot/grub/grub.cfg, so the grub.cfg
#        it built is copied there explicitly.
#   3. guix system reconfigure sys-config.scm
#        Regenerates the Linux GRUB menu.  sys-config.scm reads
#        /hurd/boot/grub/grub.cfg to inject the Hurd menu entries.
#
# Substitutes: ensure https://bordeaux.guix.gnu.org is authorised in
#   /etc/guix/acl (see: guix archive --authorize) so Hurd binaries are
#   fetched rather than cross-compiled locally.

set -euo pipefail

HURD_CONFIG="/home/adam/guix-backup/hurd-config.scm"
SYS_CONFIG="/home/adam/guix-backup/sys-config.scm"
HURD_FB_MODULES="/home/adam/hurd-fb/guix"
HURD_MOUNT="/hurd"
HURD_DEVICE="/dev/sda4"
BACKUP_DIR="/home/adam/guix-backup/backups"
INIT_LOG="/tmp/hurd-init.log"

die() { echo "Error: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run with sudo."
mountpoint -q "${HURD_MOUNT}"   || die "${HURD_MOUNT} is not mounted."
[ "$(findmnt -no SOURCE "${HURD_MOUNT}" | head -1)" = "${HURD_DEVICE}" ] \
  || die "${HURD_MOUNT} is not ${HURD_DEVICE}"
[ -f "${HURD_CONFIG}" ]         || die "Missing ${HURD_CONFIG}"
[ -f "${SYS_CONFIG}" ]          || die "Missing ${SYS_CONFIG}"
[ -f "${HURD_FB_MODULES}/hurd-fb.scm" ] \
  || die "Missing ${HURD_FB_MODULES}/hurd-fb.scm"

# Step 1 — back up both configs
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "${BACKUP_DIR}"
cp "${HURD_CONFIG}" "${BACKUP_DIR}/hurd-config.${STAMP}.scm"
cp "${SYS_CONFIG}"  "${BACKUP_DIR}/sys-config.${STAMP}.scm"
echo "==> Configs backed up to ${BACKUP_DIR}/"

# Step 2 — build + install 64-bit Hurd
echo "==> Building and installing 64-bit GNU/Hurd to ${HURD_MOUNT}..."

guix system init \
  -L "${HURD_FB_MODULES}" \
  --target=x86_64-pc-gnu \
  --no-bootloader \
  --skip-checks -v3 \
  "${HURD_CONFIG}" \
  "${HURD_MOUNT}" 2>&1 | tee "${INIT_LOG}"

# --no-bootloader also skips writing ${HURD_MOUNT}/boot/grub/grub.cfg,
# which sys-config.scm reads.  Install the grub.cfg that init just built.
NEW_GRUB_CFG=$(grep -o '/gnu/store/[a-z0-9]*-grub\.cfg' "${INIT_LOG}" | tail -1 || true)
[ -n "${NEW_GRUB_CFG}" ] || die "could not find the new grub.cfg in ${INIT_LOG}"
mkdir -p "${HURD_MOUNT}/boot/grub"
cp "${NEW_GRUB_CFG}" "${HURD_MOUNT}/boot/grub/grub.cfg"
echo "==> Installed ${NEW_GRUB_CFG} as ${HURD_MOUNT}/boot/grub/grub.cfg"

ENTRY=$(grep -c 'menuentry "GNU with the Hurd' "${HURD_MOUNT}/boot/grub/grub.cfg" || true)
echo "    Found ${ENTRY} Hurd menu entry/entries in grub.cfg."

# Step 3 — regenerate the Linux GRUB menu with the new Hurd entries
echo "==> Reconfiguring Guix Linux system (Linux GRUB + Hurd entries)..."
guix system reconfigure "${SYS_CONFIG}"

# Show which kernel the menu now boots: flags=0x00000007 is the patched one.
KERNEL=$(grep -m1 -o '/gnu/store/[^ ]*gnumach[^ ]*' /boot/grub/grub.cfg || true)
echo ""
echo "==> Done.  Hurd kernel in the GRUB menu: ${KERNEL:-<not found>}"
echo "    Check it with:"
echo "    guix shell python -- python3 /home/adam/hurd-fb/tests/multiboot-header.py ${HURD_MOUNT}${KERNEL}"
echo "    Hurd GRUB config : ${HURD_MOUNT}/boot/grub/grub.cfg"
