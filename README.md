gb-disassembler
===============

Disassembler for Gameboy ROMs

# About This Tool
It is a disassembler for Nintendo Gameboy ROMs, mainly aimed at reverse engineering.




# Installation
It is supposed that SBCL and ASDF exist in your environment. It can, however, probably be carried out on another Common Lisp implementations too.  
<http://www.sbcl.org/>  
I have confirmed that it runs on Windows8.1 + Cygwin + SBCL1.1.17(x64) and I used to carry it out on Linux + SBCL(x32) a long time ago.

First, you should open Makefile and assign DEST the correct path of the ASDF registry, which you can get on your Lisp implementation by a variable `asdf:*central-registry*`.  

    (require :asdf)
    asdf:*central-registry*

And then, you can make it install.

    $ make install

Makefile is written so that it will copy all of the .lisp files to the ASDF registry (e.g. /home/username/quicklisp/quicklisp), if you do `make install`. This is for my personal reasons: the system of symbolic link doesn't work in my environment as it would do on a Linux machine. On a more standard platform, you will be able to avoid it through the following way in place of `make install` if you want:  

    $ ln -s z80disas.asd /path/of/asdf/registry/
    $ sbcl
    (require :asdf)
    (asdf:load-system :z80disas)




# Usage
    disasgb rom_file [config_file] > output_file

You can omit the config file.




# Structure of Configuration File
By a configuration file you can  
1. tell the disassembler where are data blocks in the ROM file and  
2. name or annotate specific functions.  
Of course, you can do disassembling without it. In that case, however, it will also disassemble data blocks and sometimes print a wrong code near the border of a data block and a code block.


The following is an example of a configuration file.

    ;You can comment it out with semicolon. The line will be ignored after it.
    ;First, you write notes in conjunction with function calls, such as CALL 0180h.
    
    (
    (#x0180 "random number generator")
    (#x6a2a "put the beginning address (e.g. AFh) of an attacking unit to the DE")
    (#x7019 "add B to the success rate (a450)")
    )
    
    ;They are in the form of (ADDRESS "NOTE").
    ;#x means a hex number and can be omitted when you want to put a decimal number.
    ;If you write as above, the output of the disassembler will be like the follwing:
    
    ;...
    ;00:30BB CD 80 01    CALL  0180    //random number generator
    ;...
    
    ;As the bank system is never taken into account, if the duplication of an
    ;address between different banks exists, you should note so on your own.
    ;The whole ()s must be parenthesized with another () as above.
    ;If you don't need this function, you must just write () and go to the next.
    
    
    ;Second, you set addresses of data blocks for each bank.
    
    nil ;ROM0 end
    nil ;ROM1 end
    nil ;ROM2 end
    nil ;ROM3 end
    nil ;ROM4 end
    nil ;ROM5 end
    nil ;ROM6 end
    #x4000 #x4100 "Weapon Data"
    #x42c0 #x44f0 "Armor Data"
    #x5a00 #x6000 "Monster Names"
    nil ;ROM7 end
    nil ;ROM8 end
    nil ;ROM9 end
    nil ;ROMa end
    ;....
    
    ;For every bank, you can point out data blocks as follows:
    ;BEGINNING_ADDRESS FINAL_ADDRESS+1 "TITLE OF THE BLOCK"
    ;When you want to finish designating addresses for a bank,
    ;you must put nil and then you can go to the next bank.
    ;If you write as above, the 4000h-40FFh of the bank 7 will be indicated as data.
    
    ;==data:Weapon Data==
    ;07:4000 02 22 10 03 10 00 0A 0E 00 00 00 00 08 00 00 01
    ;07:4010 08 18 07 03 4A 14 2C 00 0D 00 00 00 15 00 00 00
    ;07:4020 11 30 0D 00 33 0F 00 0E 00 00 00 00 07 1C 00 09
    ;07:4040 08 1F 28 01 12 14 0B 00 0D 00 00 00 10 03 00 10
    
    ;When the disassembler reads the end-of-file, it will be interpreted as nil.
    ;Therefore, you don't need to count the total number of banks and
    ;may just finish the designations wherever you want.
