;;; Framebuffer console for GNU/Hurd on coreboot/Libreboot machines.
;;;
;;; Variants of Guix's gnumach and hurd packages with the patches from
;;; ../patches applied, and a procedure that switches an existing Hurd
;;; operating-system declaration over to them.
;;;
;;; Use with `guix system -L /path/to/this/repo/guix ...' and
;;; `(use-modules (hurd-fb))' in the Hurd system configuration.

(define-module (hurd-fb)
  #:use-module (guix packages)
  #:use-module (guix gexp)
  #:use-module (guix git-download)
  #:use-module (guix utils)
  #:use-module (gnu packages hurd)
  #:use-module (gnu services)
  #:use-module (gnu services hurd)
  #:use-module (gnu system)
  #:export (gnumach/fb
            rumpkernel/debian-9
            hurd/fb
            hurd-fb-services
            operating-system-with-fb-console))

(define gnumach/fb
  (package
    (inherit gnumach)
    (source
     (origin
       (inherit (package-source gnumach))
       (patches
        (append
         (origin-patches (package-source gnumach))
         (list
          (local-file
           "../patches/gnumach/0001-multiboot-Fix-offset-of-the-framebuffer-colour-infor.patch")
          (local-file
           "../patches/gnumach/0002-kd-Draw-the-console-on-a-linear-framebuffer-when-the.patch")
          (local-file
           "../patches/gnumach/0003-multiboot-Request-video-information-on-x86_64-option.patch"))))))
    (arguments
     (substitute-keyword-arguments (package-arguments gnumach)
       ;; Ask GRUB for a linear framebuffer rather than EGA text; on
       ;; coreboot with a framebuffer there is no EGA text buffer.
       ((#:configure-flags flags ''())
        `(cons "--enable-linear-fb" ,flags))))))

(define rumpkernel/debian-9
  ;; Debian's rumpkernel packaging at 0~20250111-9, which adds Michael
  ;; Kelly's DMA bounce buffer support (patches/dma_bounce_buffers.diff) for
  ;; rumpdisk on real hardware.  Guix itself still packages -6.
  (let ((commit "9406e1fbbfd3de0a3265046dadb0d9e5e5748a0a")
        (revision "9"))
    (package
      (inherit rumpkernel)
      (version (git-version "0-20250111" revision commit))
      (source
       (origin
         (method git-fetch)
         (uri (git-reference
               (url "https://salsa.debian.org/hurd-team/rumpkernel.git")
               (commit commit)))
         ;; Placeholder: the first build fails with "hash mismatch" and
         ;; prints the actual hash; put that here.
         (sha256
          (base32 "0000000000000000000000000000000000000000000000000000"))
         (file-name (git-file-name "rumpkernel" version))))
      (arguments
       (substitute-keyword-arguments (package-arguments rumpkernel)
         ((#:phases phases)
          #~(modify-phases #$phases
              ;; debian/rules defines NOGCCERROR since -9; NetBSD make
              ;; picks it up from the environment.
              (add-before 'build 'no-gcc-error
                (lambda _
                  (setenv "NOGCCERROR" "yes"))))))))))

(define hurd/fb
  (package
    (inherit hurd)
    ;; rumpdisk is linked statically against the rump kernel libraries.
    (inputs (modify-inputs (package-inputs hurd)
              (replace "rumpkernel" rumpkernel/debian-9)))
    (source
     (origin
       (inherit (package-source hurd))
       (patches
        (append
         (origin-patches (package-source hurd))
         (list
          (local-file
           "../patches/hurd/0001-console-client-Fix-the-framebuffer-driver-on-real-ha.patch")
          (local-file
           "../patches/hurd/0002-console-Report-width-with-the-width-not-the-number-o.patch"))))))))

(define (hurd-fb-services services)
  "Return SERVICES with the Hurd console, getty and login services using
hurd/fb, so that the console client is the patched one."
  (modify-services services
    (hurd-console-service-type
     config => (hurd-console-configuration
                (inherit config)
                (hurd hurd/fb)))
    (hurd-getty-service-type
     config => (hurd-getty-configuration
                (inherit config)
                (hurd hurd/fb)))
    (hurd-login-service-type
     config => (hurd-login-configuration
                (inherit config)
                (hurd hurd/fb)))))

(define (operating-system-with-fb-console os)
  "Return OS, a Hurd operating-system, booting gnumach/fb with the
servers and console client from hurd/fb."
  (operating-system
    (inherit os)
    (kernel gnumach/fb)
    (hurd hurd/fb)
    (services (hurd-fb-services (operating-system-user-services os)))))
