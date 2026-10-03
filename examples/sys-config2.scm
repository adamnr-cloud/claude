(use-modules
  (gnu)
  (srfi srfi-1)
  (srfi srfi-26)
  (ice-9 match)
  (ice-9 rdelim)
  (ice-9 regex)
  (gnu build file-systems))

(use-service-modules desktop networking ssh xorg virtualization)
(use-package-modules certs gnome xorg bootloaders)

;; Read Hurd GRUB menu entries from /hurd/boot/grub/grub.cfg at reconfigure time
(define %hurd-menuentry-regex
  "menuentry \"(GNU with the Hurd[^{\"]*)\".*multiboot ([^ \n]*) +([^\n]*)")

(define (text->hurd-menuentry text)
  (let* ((m (string-match %hurd-menuentry-regex text))
         (label (match:substring m 1))
         (kernel (match:substring m 2))
         (arguments (match:substring m 3))
         (arguments (string-split arguments #\space))
         (root (find (cute string-prefix? "root=" <>) arguments))
         (device-spec (match (string-split root #\=)
                        (("root" device) device)))
         (device (hurd-device-name->device-name device-spec))
         (modules (list-matches "module ([^\n]*)" text))
         (modules (map (cute match:substring <> 1) modules))
         (modules (map (cute string-split <> #\space) modules)))
    (menu-entry
     (label label)
     (device device)
     (multiboot-kernel kernel)
     (multiboot-arguments arguments)
     (multiboot-modules modules))))

(define %hurd-menuentries-regex
  "menuentry \"(GNU with the Hurd[^{\"]*)\" \\{([^}]|[^\n]\\})*\n\\}")

(define (grub.cfg->hurd-menuentries grub.cfg)
  (let* ((entries (list-matches %hurd-menuentries-regex grub.cfg))
         (entries (map (cute match:substring <> 0) entries)))
    (map text->hurd-menuentry entries)))

(define (hurd-menuentries)
  (let ((grub.cfg (with-input-from-file "/hurd/boot/grub/grub.cfg"
                    read-string)))
    (grub.cfg->hurd-menuentries grub.cfg)))

;; This Hurd root was installed from Linux, which cannot set its passive
;; translators, so its first boot fails in console-run while ext2fs holds
;; the root read-only.  Start ext2fs writable; runsystem still switches /
;; to read-only for fsck and back to writable afterwards.
(define (without-readonly-root entry)
  (menu-entry
    (inherit entry)
    (multiboot-modules
      (map (lambda (module)
             (if (string-suffix? "/ext2fs.static" (car module))
                 (delete "--readonly" module)
                 module))
           (menu-entry-multiboot-modules entry)))))

;; Test entry: the same Hurd entry, booting the framebuffer-console kernel
;; copied to /hurd/boot/gnumach-fb (from the gnumach/fb package of
;; /home/adam/hurd-fb).  Only added while that file exists.
(define %hurd-fb-test-kernel "/hurd/boot/gnumach-fb")

(define (fb-test-entry entry)
  (menu-entry
    (inherit entry)
    (label (string-append (menu-entry-label entry) " (fb test kernel)"))
    ;; Path as GRUB sees it on the Hurd partition.
    (multiboot-kernel "/boot/gnumach-fb")))

;; Test entry: the fb test entry, plus GRUB commands that stop the devices
;; sharing IRQ 16 with the SATA controller (i915 00:02.0, SMBus 00:1f.3,
;; Ricoh SD reader 01:00.0) from raising INTx interrupts, which the Hurd has
;; no drivers to clear.  Guix's menu-entry has no field for extra GRUB
;; commands; the multiboot arguments are written verbatim, so an argument
;; starting with a newline ends the multiboot line and adds these commands,
;; which GRUB runs before booting.
(define %intx-off-commands
  (string-append "\n  insmod setpci"
                 "\n  setpci -s 00:02.0 COMMAND=400:400"
                 "\n  setpci -s 00:1f.3 COMMAND=400:400"
                 "\n  setpci -s 01:00.0 COMMAND=400:400"))

(define (intx-off-entry entry)
  (menu-entry
    (inherit entry)
    (label (string-append (menu-entry-label entry) " (INTx off)"))
    (multiboot-arguments
      (append (menu-entry-multiboot-arguments entry)
              (list %intx-off-commands)))))

;; The Hurd entries are read from the Hurd partition.  Refuse to reconfigure
;; when it is not mounted, rather than silently dropping them from the menu.
(define %hurd-grub.cfg "/hurd/boot/grub/grub.cfg")

(unless (file-exists? %hurd-grub.cfg)
  (error "Hurd partition not mounted: run 'sudo mount /dev/sda4 /hurd' first"
         %hurd-grub.cfg))


(operating-system
  (kernel-arguments (cons "iomem=relaxed" %default-kernel-arguments)) ;;for flashing. comment out when not flashing
  (locale "en_GB.utf8")
  (timezone "Europe/London")
  (keyboard-layout (keyboard-layout "gb"))
  (host-name "guix230")

  (name-service-switch %mdns-host-lookup-nss)

  (users (cons* (user-account
                  (name "adam")
                  (comment "Adam")
                  (group "users")
                  (home-directory "/home/adam")
                  (supplementary-groups
                    '("wheel" "netdev" "audio" "video" "kvm" "libvirt" "input")))
                %base-user-accounts))

  (packages
    (append
      (list gnome-shell
            gvfs)
      %base-packages))

  (services
    (modify-services
      (append
        (list
          (service libvirt-service-type
            (libvirt-configuration (unix-sock-group "libvirt")))
          (service virtlog-service-type)
          (service openssh-service-type)
          (service gnome-desktop-service-type)
          (service bluetooth-service-type)
          (simple-service 'uinput-udev-rules
            udev-service-type
            (list (udev-rule
                    "99-uinput.rules"
                    "KERNEL==\"uinput\", GROUP=\"input\", MODE=\"0660\"")))
          (set-xorg-configuration
            (xorg-configuration
              (keyboard-layout keyboard-layout)))
          (simple-service 'static-resolv-conf
            etc-service-type
            (list `("resolv.conf"
                    ,(plain-file "resolv.conf"
                       "nameserver 1.1.1.1\nnameserver 9.9.9.9\n"))))
          (simple-service 'persistent-grub-font
            special-files-service-type
            `(("/boot/grub/unicode.pf2"
               ,(file-append grub "/share/grub/unicode.pf2")))))
        %desktop-services)
      (gdm-service-type config =>
        (gdm-configuration (wayland? #t)))
      (network-manager-service-type config =>
        (network-manager-configuration
          (inherit config)
          (dns "none")))))

    (bootloader
    (bootloader-configuration
      (theme (grub-theme
               (inherit (grub-theme))
               (gfxmode '("1366x768" "auto"))))
      (bootloader grub-bootloader)
      (targets '("/dev/sda"))
      (keyboard-layout keyboard-layout)
      (menu-entries
        (let ((entries (map without-readonly-root (hurd-menuentries))))
          (if (file-exists? %hurd-fb-test-kernel)
              (append entries
                      (map fb-test-entry entries)
                      (map (compose intx-off-entry fb-test-entry) entries))
              entries)))))

  (swap-devices
    (list (swap-space
            (target (uuid "6bf268eb-94f8-4de6-8f4b-e17b30c68cb1")))))

  (file-systems
    (cons* (file-system
             (mount-point "/")
             (device (uuid "d8602ea3-05d8-496d-a862-5450fd52cafc" 'ext4))
             (type "ext4"))
           (file-system
             (device (file-system-label "hurd"))
             (mount-point "/hurd")
             (type "ext2"))
           %base-file-systems)))
