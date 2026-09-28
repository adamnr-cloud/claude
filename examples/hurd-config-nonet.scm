
(use-modules (gnu) (gnu system hurd)
             (gnu packages base)
             (gnu packages hurd)
             (gnu bootloader)
             (gnu bootloader grub))

(use-service-modules networking)

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

  (packages %base-packages/hurd)

  ;; Test variant: loopback only, no eth0 and no SSH, so that netdde never
  ;; starts.  Used to check whether the rumpdisk "device timeout" errors on
  ;; the X230 are related to netdde starting.  The original services were
  ;; openssh-service-type and static-networking-service-type with eth0.
  (services
    (cons (service static-networking-service-type
                   (list %loopback-static-networking))
          %base-services/hurd)))
