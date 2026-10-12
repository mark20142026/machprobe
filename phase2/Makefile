ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
SDK := $(shell xcrun --sdk macosx --show-sdk-path)
OUT := $(ROOT)/build/phase2
CC := xcrun clang
FLAGS := -arch arm64 -isysroot $(SDK) -mmacosx-version-min=11.0 -Wall -Wextra -g -O0 -I$(ROOT)/runtime
RUNTIME := $(ROOT)/runtime/image.c $(ROOT)/runtime/fixups.c $(ROOT)/runtime/services.c $(ROOT)/runtime/tls.c $(ROOT)/runtime/group.c
LIBS := -framework Foundation -framework CoreFoundation -framework Metal -lobjc
.PHONY: all test sanitize
all: $(OUT)/runner $(OUT)/interactive
$(OUT):
	mkdir -p $@
$(OUT)/runner: $(RUNTIME) $(ROOT)/phase2/host/cli.c $(wildcard $(ROOT)/runtime/*.h) | $(OUT)
	$(CC) $(FLAGS) $(RUNTIME) $(ROOT)/phase2/host/cli.c $(LIBS) -o $@
$(OUT)/interactive: $(ROOT)/phase2/guests/interactive.c $(ROOT)/runtime/guest_abi.h | $(OUT)
	$(CC) $(FLAGS) -Wl,-export_dynamic $< -o $@
all: $(OUT)/foundation $(OUT)/metal_compute
$(OUT)/foundation: $(ROOT)/phase2/guests/foundation.m | $(OUT)
	$(CC) $(FLAGS) -fobjc-arc -fno-objc-exceptions -fno-exceptions -Wl,-export_dynamic $< $(LIBS) -o $@
$(OUT)/metal_compute: $(ROOT)/phase2/guests/metal_compute.m | $(OUT)
	$(CC) $(FLAGS) -fobjc-arc -fno-objc-exceptions -fno-exceptions -Wl,-export_dynamic $< $(LIBS) -o $@
all: $(OUT)/abi-test
$(OUT)/abi-test: $(RUNTIME) $(ROOT)/phase2/tests/abi.c $(ROOT)/phase2/host/checks.c $(wildcard $(ROOT)/runtime/*.h) | $(OUT)
	$(CC) $(FLAGS) $(RUNTIME) $(ROOT)/phase2/tests/abi.c $(ROOT)/phase2/host/checks.c $(LIBS) -o $@
$(OUT)/runner-sanitize: $(RUNTIME) $(ROOT)/phase2/host/cli.c $(wildcard $(ROOT)/runtime/*.h) | $(OUT)
	$(CC) $(FLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer $(RUNTIME) $(ROOT)/phase2/host/cli.c $(LIBS) -o $@
$(OUT)/abi-test-sanitize: $(RUNTIME) $(ROOT)/phase2/tests/abi.c $(ROOT)/phase2/host/checks.c $(wildcard $(ROOT)/runtime/*.h) | $(OUT)
	$(CC) $(FLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer $(RUNTIME) $(ROOT)/phase2/tests/abi.c $(ROOT)/phase2/host/checks.c $(LIBS) -o $@
sanitize: all $(OUT)/runner-sanitize $(OUT)/abi-test-sanitize
	cd $(ROOT) && MP_RUNNER=build/phase2/runner-sanitize MP_ABI_TEST=build/phase2/abi-test-sanitize python3 -m unittest discover -s phase2/tests -v
test: all
	cd $(ROOT) && python3 -m unittest discover -s phase2/tests -v
