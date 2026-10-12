ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
OUT := $(ROOT)/build/phase8
CC := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun clang
FLAGS := -arch arm64 -mmacosx-version-min=11.0 -g -O1 -Wall -Wextra -I$(ROOT)/runtime -I$(ROOT)/phase4/runtime -I$(ROOT)/phase5/runtime
CORE := $(addprefix $(ROOT)/runtime/,image.c fixups.c services.c tls.c group.c)
HOST := $(ROOT)/phase4/runtime/Extended.c $(ROOT)/phase5/runtime/Policy.c $(ROOT)/phase5_5/runtime/Policy.c $(ROOT)/phase8/runtime/Policy.c
LIBS := -framework Foundation -framework AppKit -framework CoreFoundation -framework Metal -lobjc
all: $(OUT)/cp-load
$(OUT):
	mkdir -p $@
$(OUT)/cp-load: $(CORE) $(HOST) $(ROOT)/phase8/host/LoadCLI.m $(wildcard $(ROOT)/runtime/*.h) | $(OUT)
	$(CC) $(FLAGS) $(CORE) $(HOST) $(ROOT)/phase8/host/LoadCLI.m $(LIBS) -o $@
.PHONY: all
