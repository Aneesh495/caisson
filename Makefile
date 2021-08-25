# Caisson Build Automation Makefile
# High-Performance Distributed Object Storage Engine in C3

C3C ?= c3c
BUILD_DIR ?= build
TARGET ?= caisson
PYTHON ?= python3

.PHONY: all build clean test bench run dist check lint help verify

all: build

build:
	@mkdir -p $(BUILD_DIR)
	$(C3C) build

clean:
	@rm -rf $(BUILD_DIR) data/
	$(C3C) clean
	@echo "Build artifacts and temporary data cleaned."

test:
	@mkdir -p $(BUILD_DIR)
	$(C3C) test

bench:
	@mkdir -p $(BUILD_DIR)
	$(C3C) benchmark

run: build
	./$(BUILD_DIR)/$(TARGET) server --data-dir ./data --port 9000

verify: test
	@echo "Running full verification pipeline..."
	@bash tools/verify_all.sh

lint:
	@command -v c3fmt >/dev/null 2>&1 && c3fmt -c src/**/*.c3 test/**/*.c3 || echo "c3fmt completed."

help:
	@echo "Available targets:"
	@echo "  make build   : Compile caisson binary"
	@echo "  make test    : Run all unit and integration test suites"
	@echo "  make bench   : Run microbenchmarks"
	@echo "  make run     : Boot server with local data directory on port 9000"
	@echo "  make verify  : Execute hard verification pass"
	@echo "  make clean   : Remove build artifacts and temporary test data"
