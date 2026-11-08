#!/bin/bash
# upstream-review.sh — fetch gnumach, hurd and rumpkernel and list what
# upstream has changed since the versions Guix packages.
#
# Usage: bash upstream-review.sh [WORKDIR]      (default ~/hurd-upstream)
#
# Writes WORKDIR/report.txt: for each repository, every commit after the
# Guix base, grouped by the area it touches, plus the files changed.
# Re-running only fetches what is new.
#
# Bases (update them when Guix updates its packages):
#   gnumach  f7debdac0  = Guix gnumach 1.8+git20260224
#   hurd     6290b4cf   = Guix hurd 0.9.git20251029
#   rumpkernel: Debian packaging tag for -6 (Guix) and -9 (hurd-fb.scm)

set -euo pipefail

WORK=${1:-$HOME/hurd-upstream}
GNUMACH_URL=${GNUMACH_URL:-https://git.savannah.gnu.org/git/hurd/gnumach.git}
HURD_URL=${HURD_URL:-https://git.savannah.gnu.org/git/hurd/hurd.git}
RUMP_URL=${RUMP_URL:-https://salsa.debian.org/hurd-team/rumpkernel.git}
GNUMACH_BASE=${GNUMACH_BASE:-f7debdac0582ee2f956b60085271d8588ce9e6c5}
HURD_BASE=${HURD_BASE:-6290b4cf}

GIT=git
command -v git >/dev/null || GIT="guix shell git -- git"

mkdir -p "$WORK"
REPORT="$WORK/report.txt"
: > "$REPORT"

fetch() {  # fetch NAME URL
  if [ -d "$WORK/$1" ]; then
    $GIT -C "$WORK/$1" fetch -q --tags origin
  else
    $GIT clone -q --bare "$2" "$WORK/$1"
  fi
}

head_of() {  # BRANCH_<repo> if set, else master, else the default branch
  local v="BRANCH_$1"
  if [ -n "${!v:-}" ]; then echo "${!v}"
  elif $GIT -C "$WORK/$1" rev-parse -q --verify refs/heads/master >/dev/null; then echo master
  else $GIT -C "$WORK/$1" symbolic-ref -q --short HEAD
  fi
}

section() { printf '\n==================== %s ====================\n' "$*" >> "$REPORT"; }

# area REPO RANGE TITLE PATHS... — commits in RANGE touching PATHS
area() {
  local repo=$1 range=$2 title=$3; shift 3
  local out
  out=$($GIT -C "$WORK/$repo" log --no-merges --date=short \
          --format='%h %ad %an: %s' "$range" -- "$@")
  [ -n "$out" ] || return 0
  printf '\n--- %s (%s)\n%s\n' "$title" "$*" "$out" >> "$REPORT"
}

echo "==> Fetching into $WORK (first run takes a few minutes)"
fetch gnumach "$GNUMACH_URL"
fetch hurd "$HURD_URL"
fetch rumpkernel "$RUMP_URL" || echo "    rumpkernel: fetch failed, skipping"

# ---------------------------------------------------------------- gnumach
R="$GNUMACH_BASE..$(head_of gnumach)"
section "gnumach $R"
echo "$($GIT -C "$WORK/gnumach" rev-list --count --no-merges "$R") commits" >> "$REPORT"
area gnumach "$R" "Interrupts / devices"   device/ i386/i386at/ i386/i386/irq.c i386/i386/pic.c i386/i386/apic.c x86_64/
area gnumach "$R" "Built-in disk drivers (i386 only)" linux/
area gnumach "$R" "Virtual memory"         vm/
area gnumach "$R" "Kernel / IPC / SMP"     kern/ ipc/
area gnumach "$R" "Boot / multiboot"       i386/i386at/model_dep.c i386/include/mach/i386/multiboot.h i386/i386at/boothdr.S x86_64/boothdr.S

# ---------------------------------------------------------------- hurd
R="$HURD_BASE..$(head_of hurd)"
section "hurd $R"
echo "$($GIT -C "$WORK/hurd" rev-list --count --no-merges "$R") commits" >> "$REPORT"
area hurd "$R" "Disk: rumpdisk / libmachdev / irqhelp" rumpdisk/ libmachdev/ libirqhelp/ rumpusbdisk/
area hurd "$R" "PCI / ACPI"            pci-arbiter/ acpi/ libpciaccess/
area hurd "$R" "Console"               console-client/ console/ libcons/
area hurd "$R" "Filesystems / boot"    ext2fs/ libdiskfs/ libstore/ startup/ init/ exec/ boot/
area hurd "$R" "Network"               pfinet/ lwip/ rumpnet/ eth-filter/

# ---------------------------------------------------------------- rumpkernel
if [ -d "$WORK/rumpkernel" ]; then
  section "rumpkernel (Debian packaging)"
  $GIT -C "$WORK/rumpkernel" tag -l 'debian/*' --sort=-creatordate | head -5 >> "$REPORT"
  for t in debian/0_20250111-6 debian/0_20250111-9; do
    $GIT -C "$WORK/rumpkernel" rev-parse -q --verify "$t^{commit}" >/dev/null && last=$t
  done
  if [ -n "${last:-}" ]; then
    R="$last..$(head_of rumpkernel)"
    printf '\nSince %s:\n' "$last" >> "$REPORT"
    $GIT -C "$WORK/rumpkernel" log --no-merges --date=short \
      --format='%h %ad %an: %s' "$R" >> "$REPORT"
    printf '\ndebian/patches changed since %s:\n' "$last" >> "$REPORT"
    $GIT -C "$WORK/rumpkernel" diff --stat "$R" -- debian/patches >> "$REPORT"
  fi
fi

echo "==> Report: $REPORT ($(wc -l < "$REPORT") lines)"
echo "    Show one change:  git -C $WORK/hurd show <hash>"
echo "    Export a patch:   git -C $WORK/hurd format-patch -1 <hash> -o ~/hurd-fb/patches/hurd/"
