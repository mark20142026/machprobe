SDK := $(shell xcrun --sdk macosx --show-sdk-path)
CC := xcrun clang
CXX := xcrun clang++
TARGET := -arch arm64 -isysroot $(SDK) -mmacosx-version-min=11.0
WARN := -Wall -Wextra -Wpedantic
CFLAGS := $(TARGET) $(WARN) -O0 -g
CXXFLAGS := $(CFLAGS) -std=c++17 -Iinclude
SOURCES := src/main.cpp src/macho.cpp src/deps.cpp
SAMPLES := build/hello build/file_io build/framework build/metal_info
.PHONY: all samples run-samples test test-sanitize evidence clean
all: samples build/machprobe
samples: $(SAMPLES)
build:
	mkdir -p build
build/hello: samples/hello.c | build
	$(CC) $(CFLAGS) $< -o $@
build/file_io: samples/file_io.c | build
	$(CC) $(CFLAGS) $< -o $@
build/framework: samples/framework.c | build
	$(CC) $(CFLAGS) $< -framework CoreFoundation -o $@
build/metal_info: samples/metal_info.m | build
	$(CC) $(CFLAGS) -fobjc-arc $< -framework Foundation -framework Metal -o $@
build/machprobe: $(SOURCES) include/machprobe.hpp | build
	$(CXX) $(CXXFLAGS) $(SOURCES) -o $@
build/machprobe-sanitize: $(SOURCES) include/machprobe.hpp | build
	$(CXX) $(CXXFLAGS) -fsanitize=address,undefined -fno-omit-frame-pointer $(SOURCES) -o $@
run-samples: samples
	build/hello
	build/file_io build
	build/framework
	build/metal_info
test: all
	python3 -m unittest discover -s tests -v
test-sanitize: samples build/machprobe-sanitize
	MACHPROBE=build/machprobe-sanitize python3 -m unittest discover -s tests -v
evidence: all
	python3 scripts/evidence.py
clean:
	rm -rf build

# Optional, explicitly requested in-process loader experiment; separate from Phase 1.
.PHONY: test-loader test-loader-sanitize
LOADER_SOURCES := experiments/inprocess-hello/loader.c experiments/inprocess-hello/cli.c
build/hello-loader: $(LOADER_SOURCES) experiments/inprocess-hello/loader.h | build
	$(CC) $(CFLAGS) $(LOADER_SOURCES) -o $@
build/hello-loader-sanitize: $(LOADER_SOURCES) experiments/inprocess-hello/loader.h | build
	$(CC) $(CFLAGS) -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer $(LOADER_SOURCES) -o $@
test-loader: all build/hello-loader
	python3 -m unittest discover -s experiments/inprocess-hello/tests -v
test-loader-sanitize: all build/hello-loader-sanitize
	HELLO_LOADER=build/hello-loader-sanitize python3 -m unittest discover -s experiments/inprocess-hello/tests -v
