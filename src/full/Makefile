
TOP=../..

include $(TOP)/mk/paths.mk

# src_files=$(shell find . \( \( -name '*.hs' -o -name '*.lhs' \) ! -name '.*' \) )
# include hs-boot files
find_filter=\( \( \( -name '*.*hs' -o -name '*.hs-boot' \) ! -name '*~' \) ! -name '.*' \)
src_files=$(shell find . $(find_filter) )


## Lines of Code ##########################################################

lexparse=./Agda/Syntax/Parser/Lexer.x ./Agda/Syntax/Parser/Parser.y
generated=./Agda/Syntax/Parser/Lexer.hs ./Agda/Syntax/Parser/Parser.hs
allsources=$(src_files) $(lexparse)
locfiles=$(filter-out $(generated),$(allsources))

utils=$(shell find Agda/Utils $(find_filter) )
syntax=$(shell find Agda/Syntax $(find_filter) )
typechecking=$(shell find Agda/TypeChecking $(find_filter) )
termination=$(shell find Agda/Termination $(find_filter) )
interaction=$(shell find Agda/Interaction $(find_filter) )
mimer=$(shell find Agda/Mimer $(find_filter) )
compiler=$(shell find Agda/Compiler $(find_filter) )

locs : loc_utils loc_syntax loc_lexparse loc_typechecking loc_termination loc_interaction loc_mimer loc_compiler

loc_utils :
	@echo "========================================================================"
	@echo "== Lines of Code: Utils ================================================"
	@echo "========================================================================"
	@wc $(utils)

loc_syntax :
	@echo "========================================================================"
	@echo "== Lines of Code: Syntax, Operator Parsing, Scope Checking, Printing ==="
	@echo "========================================================================"
	@wc $(syntax)

loc_lexparse :
	@echo "========================================================================"
	@echo "== Lines of Code: ALexer and Happy-Parser =============================="
	@echo "========================================================================"
	@wc $(lexparse)

loc_typechecking :
	@echo "========================================================================"
	@echo "== Lines of Code: TypeChecking, Evaluation, Coverage, Positivity ======="
	@echo "========================================================================"
	@wc $(typechecking)

loc_termination :
	@echo "========================================================================"
	@echo "== Lines of Code: Termination =========================================="
	@echo "========================================================================"
	@wc $(termination)

loc_interaction :
	@echo "========================================================================"
	@echo "== Lines of Code: Interaction =========================================="
	@echo "========================================================================"
	@wc $(interaction)

loc_agsy :
	@echo "========================================================================"
	@echo "== Lines of Code: Agsy ================================================="
	@echo "========================================================================"
	@wc $(agsy)

loc_compiler :
	@echo "========================================================================"
	@echo "== Lines of Code: Compiler ============================================="
	@echo "========================================================================"
	@wc $(compiler)

# Total lines of code
loc :
	@wc $(locfiles)

debug_loc :
	@echo "lexparse=$(lexparse)"
	@echo "generated=$(generated)"
	@echo "allsources=$(allsources)"
	@echo "locfiles=$(locfiles)"

## Tags ###################################################################

hs-tags=hs-tags

CABAL_MACROS=$(BUILD_DIR)/build/autogen/cabal_macros.h

hs-tags_include = $(CABAL_MACROS)
hs-tags_flags   = -i $(CABAL_MACROS) --cabal ../../Agda.cabal

# create tags for VIM
tags : $(src_files) have-bin-$(hs-tags) $(hs-tags_include)
	$(hs-tags) $(hs-tags_flags) -c $(src_files)

# create tags for emacs
TAGS : $(src_files) have-bin-$(hs-tags) $(hs-tags_include)
	$(hs-tags) $(hs-tags_flags) -e $(src_files)

# Andreas: create tags for everything except Compilers
# ignore = $(patsubst ./%,%,$(shell find ./Agda/Compiler -name '*.hs' -o -name '*.lhs'))
ignore = $(shell find ./Agda/Compiler/JS ./Agda/Packaging -name '*.hs' -o -name '*.lhs')
hs_boot = $(shell find . -name '*.hs-boot')
tag_files = $(filter-out $(hs_boot),$(filter-out $(ignore),$(src_files)))

mytags : $(tag_files) have-bin-$(hs-tags) $(hs-tags_include)
	$(hs-tags) $(hs-tags_flags) -e $(tag_files)

## Installing binaries for developer services

.PHONY : have-bin-%
have-bin-% :
	@($* --help > /dev/null) || $(CABAL) $(CABAL_INSTALL_CMD) $*

.PHONY : debug-cabal
debug-cabal :
	@echo "CABAL             = $(CABAL)"
	@echo "CABAL_INSTALL_CMD = $(CABAL_INSTALL_CMD)"

.PHONY : debug
debug :
	@echo "Source files"
	@echo $(src_files)
	@echo "------------------------------------------------------------------------"
	@echo "Ignored files"
	@echo $(ignore)
	@echo "------------------------------------------------------------------------"
	@echo "Tag files"
	@echo $(tag_files)
# EOF
