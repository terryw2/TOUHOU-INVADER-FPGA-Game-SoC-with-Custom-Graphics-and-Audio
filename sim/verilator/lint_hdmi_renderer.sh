#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

verilator \
  --lint-only \
  -Wall \
  -Wno-fatal \
  -Wno-DECLFILENAME \
  +define+SIM_USE_BEHAVIORAL_ATLAS \
  --top-module hdmi_text_controller_v1_0 \
  "${PROJ_DIR}/src/hardware/VGA_controller.sv" \
  "${PROJ_DIR}/src/hardware/hdmi_text_controller_v1_0.sv"
