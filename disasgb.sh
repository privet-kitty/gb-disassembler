#!/bin/bash
#
# ゲームボーイのROMを逆アセするというアレ
# ./disasgb.sh ファイルパス [設定ファイル名]

if [ $# = 0 ]; then
    echo "usage: deass_gbrom.sh filename [cfgfilename]"
else
    if [ $# = 1 ]; then
	sbcl --noinform --quit --eval "(asdf:load-system :z80disas)" --eval "(z80disas:disassemble-file \"$1\" nil nil)"
    else
	sbcl --noinform --quit --eval "(asdf:load-system :z80disas)" --eval "(z80disas:disassemble-file \"$1\" nil \"$2\")"
    fi
fi
