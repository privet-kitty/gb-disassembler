(defpackage #:z80disas-asd
  (:use :cl :sb-ext :asdf))

(in-package :z80disas-asd)

(defsystem z80disas
  :name "z80disas"
  :version "0.0.0"
  :maintainer "Marii K."
  :author "Marii K."
  :licence "New BSD Licence"
  :description "z80-disassembler"
  :long-description "Disassembler for roms of gameboy"
  :serial t
  :components ((:file "disassembler") (:file "z80custom_mnemonic")))
