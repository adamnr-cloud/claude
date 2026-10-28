
(use-modules (gnu) (gnu system hurd)
             (gnu packages base)
             (gnu packages hurd)
             (gnu bootloader)
             (gnu bootloader grub)
             ;; From /home/adam/hurd-fb/guix (pass -L to guix system):
             ;; patched gnumach (framebuffer console) and patched hurd
             ;; (console client), built against Debian's rumpkernel -9.
             (hurd-fb))

(use-service-modules ssh networking)
(use-package-modules ssh)

(operating-system-with-fb-console
  (operating-system
    (inherit %hurd-default-operating-system)
    (host-name "guix-hurd64")
    (timezone "Europe/London")
    (locale "en_GB.utf8")

    (bootloader (bootloader-configuration
                 (bootloader grub-minimal-bootloader)
                 (targets '("/dev/sda"))))

    (kernel-arguments '("noide"
                        "maxcpus=1"
                        "--verbose"))

    (file-systems (cons (file-system
  ;;                        (device (file-system-label "hurd"))
                          (device "part:4:device:wd0")

                         (mount-point "/")
                          (type "ext2"))
                        %base-file-systems))

    (users (cons (user-account
                  (name "adam")
                  (group "users")
                  (supplementary-groups '("wheel")))
                 %base-user-accounts))

    (packages (cons openssh-sans-x %base-packages/hurd))

    (services
      (append
        (list
          (service openssh-service-type
                   (openssh-configuration
                     (openssh openssh-sans-x)
                     (permit-root-login #t)
                     (allow-empty-passwords? #t)
                     (password-authentication? #t)))
          (service static-networking-service-type
                   (list %loopback-static-networking
                         (static-networking
                           (addresses
                             (list (network-address
                                     (device "eth0")
                                     (value "192.168.0.26/24"))))
                           (routes
                             (list (network-route
                                     (destination "default")
                                     (gateway "192.168.0.1"))))
                           (requirement '())
                           (provision '(networking))
                           (name-servers '("194.168.4.100"
                                           "194.168.8.100"))))))
        %base-services/hurd))))
