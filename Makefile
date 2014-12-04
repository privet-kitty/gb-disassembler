NAME = z80disas
SRC = z80custom_mnemonic.lisp disassembler.lisp z80disas.asd
#TOP = $(HOME)/quicklisp/quicklisp
#DEST = $(TOP)/$(NAME)
DEST = $(HOME)/quicklisp/quicklisp
BINDIR = /usr/local/bin
BIN = disasgb

install:
	cp $(SRC) $(DEST)
	sbcl --quit --eval "(asdf:load-system :$(NAME))"
	cp $(BIN).sh $(BINDIR)/$(BIN)

uninstall:
	for word in $(SRC); do rm $(DEST)/$$word; done
	rm $(BINDIR)/$(BIN)
