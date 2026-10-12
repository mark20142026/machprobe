ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
OUT := $(ROOT)/build/phase5.5
CC := DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun clang
FLAGS := -arch arm64 -mmacosx-version-min=11.0 -g -Wall -Wextra -I$(ROOT)/runtime -I$(ROOT)/phase4/runtime -I$(ROOT)/phase5/runtime
CORE := $(addprefix $(ROOT)/runtime/,image.c fixups.c services.c tls.c group.c)
LIBS := -framework Foundation -framework AppKit -framework CoreFoundation -framework Metal -lobjc
all: $(OUT)/load-cli $(OUT)/tls-guest $(OUT)/tls-test
$(OUT):
	mkdir -p $@
$(OUT)/load-cli: $(CORE) $(ROOT)/phase4/runtime/Extended.c $(ROOT)/phase5/runtime/Policy.c $(ROOT)/phase5_5/runtime/Policy.c $(ROOT)/phase5_5/host/LoadCLI.m $(wildcard $(ROOT)/runtime/*.h) | $(OUT)
	$(CC) $(FLAGS) $(CORE) $(ROOT)/phase4/runtime/Extended.c $(ROOT)/phase5/runtime/Policy.c $(ROOT)/phase5_5/runtime/Policy.c $(ROOT)/phase5_5/host/LoadCLI.m $(LIBS) -o $@
$(OUT)/tls-guest: $(ROOT)/phase5_5/guests/tls.c | $(OUT)
	$(CC) $(FLAGS) -O2 -Wl,-export_dynamic $< -o $@
$(OUT)/tls-test: $(CORE) $(ROOT)/phase5_5/tests/tls_host.c $(wildcard $(ROOT)/runtime/*.h) | $(OUT)
	$(CC) $(FLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all $(CORE) $(ROOT)/phase5_5/tests/tls_host.c $(LIBS) -o $@
test: all
	cd $(ROOT) && python3 -m unittest discover -s phase5_5/tests -v
.PHONY: all test
