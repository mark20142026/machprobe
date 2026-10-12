ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
OUT := $(ROOT)/build/phase6
CC := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun clang
FLAGS := -arch arm64 -mmacosx-version-min=11.0 -g -Wall -Wextra -I$(ROOT)/runtime -I$(ROOT)/phase4/runtime -I$(ROOT)/phase5/runtime
CORE := $(addprefix $(ROOT)/runtime/,image.c fixups.c services.c tls.c group.c)
HOST := $(ROOT)/phase4/runtime/Extended.c $(ROOT)/phase5/runtime/Policy.c $(ROOT)/phase5_5/runtime/Policy.c $(ROOT)/phase6/runtime/Policy.c
LIBS := -framework Foundation -framework AppKit -framework CoreFoundation -framework Metal -lobjc
all: $(OUT)/stk-load
$(OUT):
	mkdir -p $@
$(OUT)/stk-load: $(CORE) $(HOST) $(ROOT)/phase6/host/LoadCLI.m $(wildcard $(ROOT)/runtime/*.h) | $(OUT)
	$(CC) $(FLAGS) $(CORE) $(HOST) $(ROOT)/phase6/host/LoadCLI.m $(LIBS) -o $@
test: all
	cd $(ROOT) && python3 -m unittest discover -s phase6/tests -v
.PHONY: all test
