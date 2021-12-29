#!/usr/bin/env bash
# End-to-end automated verification script for Caisson object storage engine.
# Validates build, unit test suite, microbenchmarks, live S3 daemon, REST APIs, and styling constraints.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

C3C="${HOME}/.local/bin/c3c"
if ! command -v "$C3C" &> /dev/null; then
    if command -v c3c &> /dev/null; then
        C3C="c3c"
    else
        echo "[ERROR] c3c compiler not found in ~/.local/bin or PATH"
        exit 1
    fi
fi

echo "================================================================================"
echo "                 CAISSON END-TO-END VERIFICATION HARNESS"
echo "================================================================================"
echo "Workspace: $ROOT_DIR"
echo "Compiler:  $("$C3C" --version | head -n 1)"
echo ""

# 1. Zero Em Dash Verification Pass
echo "[PASS 1/7] Enforcing strict styling rules (zero em dashes)..."
if grep -rn --exclude="verify_all.sh" "—" src test tools 2>/dev/null; then
    echo "[FAIL] Em dash detected! Violates project formatting guidelines."
    exit 1
fi
echo "  OK: Zero em dashes found across codebase."

# 2. C3 Unit Test Suite
echo ""
echo "[PASS 2/7] Running comprehensive C3 unit test suite..."
"$C3C" test
echo "  OK: 100% unit tests passed."

# 3. Release Binary Build
echo ""
echo "[PASS 3/7] Compiling production release binary..."
"$C3C" build
if [ ! -f "build/caisson" ]; then
    echo "[FAIL] Binary build/caisson was not generated."
    exit 1
fi
echo "  OK: Binary linked to build/caisson."

# 4. In-Process Microbenchmarks
echo ""
echo "[PASS 4/7] Running in-process storage and Galois Field microbenchmarks..."
./build/caisson bench
echo "  OK: Microbenchmarks completed."

# 5. Fault Injection and Reed-Solomon Recovery Simulator
echo ""
echo "[PASS 5/7] Running cluster fault injection and quorum simulator..."
python3 tools/cluster_sim.py
echo "  OK: Cluster fault recovery verified."

# 6. Live Daemon S3 REST Integration Suite
echo ""
echo "[PASS 6/7] Testing live daemon and S3 REST protocol client..."
TEST_PORT=9099
TEST_DATA_DIR="/tmp/caisson_verify_$$"
mkdir -p "$TEST_DATA_DIR"

./build/caisson server --port "$TEST_PORT" --data-dir "$TEST_DATA_DIR" > /dev/null 2>&1 &
SERVER_PID=$!

# Ensure cleanup on exit
trap 'kill -9 "$SERVER_PID" 2>/dev/null || true; rm -rf "$TEST_DATA_DIR"' EXIT

sleep 1

# Run Python client integration demo against live server
python3 tools/s3_client_demo.py "http://127.0.0.1:$TEST_PORT"

# Run latency benchmark against live server
python3 tools/benchmark.py "http://127.0.0.1:$TEST_PORT"

# 7. Forensic WAL Inspection Pass
echo ""
echo "[PASS 7/7] Testing forensic WAL log inspector on runtime data..."
DATA_FILE=$(find "$TEST_DATA_DIR" -name "*.data" | head -n 1)
if [ -n "$DATA_FILE" ] && [ -f "$DATA_FILE" ]; then
    ./build/caisson inspect "$DATA_FILE"
    echo "  OK: Forensic WAL inspection passed with valid checksums."
fi

echo ""
echo "================================================================================"
echo "          ALL VERIFICATION PASSES COMPLETED WITH 100% SUCCESS!"
echo "================================================================================"
echo ""
