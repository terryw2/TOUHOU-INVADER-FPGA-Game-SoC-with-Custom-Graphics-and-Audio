#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJ_DIR}/build/host_game_autoplay"
CC_BIN="${CC:-cc}"

mkdir -p "${BUILD_DIR}"

"${CC_BIN}" \
  -std=c99 \
  -Wall \
  -Wextra \
  -Werror \
  -DMB_NO_USB \
  -DMB_NO_STDOUT \
  -DGAME_TEST_HOOKS \
  -DHDMI_BASE_ADDR='((uintptr_t)hdmi_test_regs)' \
  -DAUDIO_BASE_ADDR='((uintptr_t)audio_test_regs)' \
  -include "${SCRIPT_DIR}/hdmi_mmio_mock.h" \
  -I"${PROJ_DIR}/src/software" \
  "${SCRIPT_DIR}/test_game_autoplay.c" \
  "${PROJ_DIR}/src/software/game.c" \
  "${PROJ_DIR}/src/software/game_assets.c" \
  "${PROJ_DIR}/src/software/generated_gfx_assets.c" \
  "${PROJ_DIR}/src/software/audio_engine.c" \
  "${PROJ_DIR}/src/software/hdmi_text_controller.c" \
  -o "${BUILD_DIR}/test_game_autoplay"

"${BUILD_DIR}/test_game_autoplay"
