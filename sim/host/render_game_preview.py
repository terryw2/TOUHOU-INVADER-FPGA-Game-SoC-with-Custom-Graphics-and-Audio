#!/usr/bin/env python3
import argparse
import os
import struct
import subprocess
import zlib

WIDTH = 640
HEIGHT = 480
SPRITE_COUNT = 96
TEXT_LINES = 16

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
BUILD_DIR = os.path.join(PROJ_DIR, "build", "host_game_preview")
DUMPER = os.path.join(BUILD_DIR, "dump_game_frame")
ATLAS_MEM = os.path.join(PROJ_DIR, "src", "hardware", "sprite_atlas.mem")


def load_atlas():
    if not os.path.exists(ATLAS_MEM):
        return []
    with open(ATLAS_MEM, "r", encoding="ascii") as f:
        return [int(line.strip(), 16) for line in f if line.strip()]


ATLAS = load_atlas()


def run(cmd):
    subprocess.run(cmd, check=True)


def build_dumper():
    os.makedirs(BUILD_DIR, exist_ok=True)
    cc = os.environ.get("CC", "cc")
    run([
        cc,
        "-std=c99",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-DHDMI_BASE_ADDR=((uintptr_t)hdmi_test_regs)",
        "-DAUDIO_BASE_ADDR=((uintptr_t)audio_test_regs)",
        "-include",
        os.path.join(SCRIPT_DIR, "hdmi_mmio_mock.h"),
        "-I" + os.path.join(PROJ_DIR, "src", "software"),
        os.path.join(SCRIPT_DIR, "dump_game_frame.c"),
        os.path.join(PROJ_DIR, "src", "software", "game.c"),
        os.path.join(PROJ_DIR, "src", "software", "game_assets.c"),
        os.path.join(PROJ_DIR, "src", "software", "generated_gfx_assets.c"),
        os.path.join(PROJ_DIR, "src", "software", "audio_engine.c"),
        os.path.join(PROJ_DIR, "src", "software", "hdmi_text_controller.c"),
        "-o",
        DUMPER,
    ])


def capture_regs(mode):
    out = subprocess.check_output([DUMPER, mode], text=True)
    sprites = [0] * SPRITE_COUNT
    text_words = [0] * (TEXT_LINES * 4)
    text_pos = [0] * TEXT_LINES
    meta = {}

    for line in out.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] in ("MODE", "FRAMES", "STATE"):
            meta[parts[0].lower()] = parts[1]
        elif parts[0] == "SPRITE":
            sprites[int(parts[1])] = int(parts[2], 16)
        elif parts[0] == "TEXTWORD":
            text_words[int(parts[1])] = int(parts[2], 16)
        elif parts[0] == "TEXTPOS":
            text_pos[int(parts[1])] = int(parts[2], 16)
    return meta, sprites, text_words, text_pos


def nibbles(color):
    return ((color >> 8) & 0xF, (color >> 4) & 0xF, color & 0xF)


def pack_rgb(r, g, b):
    return (r * 17, g * 17, b * 17)


def palette(color_id, tint=0):
    colors = {
        0x0: 0x000, 0x1: 0x0CF, 0x2: 0x0F4, 0x3: 0xF43,
        0x4: 0xFC0, 0x5: 0xF0F, 0x6: 0xFFF, 0x7: 0x55F,
        0x8: 0xF8A, 0x9: 0x8FF, 0xA: 0x8F8, 0xB: 0xF88,
        0xC: 0xAA0, 0xD: 0x0AA, 0xE: 0xA0A, 0xF: 0xFFF,
    }
    r, g, b = nibbles(colors.get(color_id, 0xDDD))
    if tint == 1:
        g >>= 1
        b >>= 1
    elif tint == 2:
        r >>= 1
        b >>= 1
    elif tint == 3:
        r >>= 1
        g >>= 1
    elif tint == 4:
        r = min(15, r | 3)
        g = min(15, g | 3)
        b = min(15, b | 3)
    return pack_rgb(r, g, b)


def background_pixel(x, y, frame):
    scroll_y = y + (frame & 0x1FF)
    cell_x = (x >> 5) & 0x1F
    cell_y = (scroll_y >> 5) & 0x1F
    cell_hash = ((cell_x * 37) ^ (cell_y * 71) ^ ((cell_x + cell_y) * 13)) & 0x3FF
    if x >= 488:
        color = 0x211 if ((x ^ y ^ (frame >> 3)) & 0x10) else 0x100
        if x in (488, 489):
            color = 0xF8A
        elif x in (636, 637):
            color = 0x8FF
        elif (y & 0x1F) in (0, 1):
            color = 0x322
        elif ((x * 3 + y * 5) & 0x3F) == 0:
            color = 0x433
        else:
            dx = x - 562
            dy = y - 286
            dist = abs(dx) + abs(dy)
            if 54 < dist < 70 and dx < 36:
                color = 0x474 if ((dist + frame) & 0x8) else 0x253
            if 24 < dist < 36 and dx < 0 and dy > -28:
                color = 0xF8A
    else:
        wave = ((scroll_y >> 3) & 0x3F)
        wave = wave if wave < 32 else 63 - wave
        path_center = 244 + wave - 16
        path_width = 74 + ((scroll_y >> 5) & 0x1F)
        path_dx = abs(x - path_center)
        color = 0x001
        if path_dx < path_width:
            color = 0x112 if ((x ^ scroll_y) & 0x10) else 0x223
            if ((x + scroll_y * 3) & 0x3F) < 2:
                color = 0x334
            if ((x * 5 + scroll_y) & 0x7F) == 3:
                color = 0x556
        else:
            color = 0x011 if (cell_hash & 0x20) else 0x020
            bamboo = (x + (scroll_y >> 2) + (cell_hash & 0x7)) % 42
            if bamboo < 3:
                color = 0x173 if (x & 0x8) else 0x062
            elif bamboo in (12, 13) and ((scroll_y >> 4) & 1):
                color = 0x041
            if (cell_hash & 0xF) == 0x7 and ((x ^ scroll_y) & 0x1F) < 6:
                color = 0x032
        if ((cell_hash & 0x1F) == (x & 0x1F)) and ((cell_hash >> 5) == (scroll_y & 0x1F)):
            color = 0x88F if (frame & 0x10) else 0x55A
        if (cell_hash & 0x100) and ((x + scroll_y) & 0x3F) == 0x17:
            color = 0xF8A
    return pack_rgb(*nibbles(color))


def sprite_pixel(sprite_type, frame, row, col):
    atlas_id = None
    if sprite_type in (4, 19):
        atlas_id = 36
    elif sprite_type == 5:
        atlas_id = 37
    elif sprite_type == 9:
        atlas_id = frame % 7
    elif sprite_type == 10:
        atlas_id = 8 + (frame % 5)
    elif sprite_type == 11:
        atlas_id = 16 + (frame % 6)
    elif sprite_type == 13:
        atlas_id = 31
    elif sprite_type == 17:
        atlas_id = 38
    elif sprite_type == 18:
        atlas_id = 39
    elif sprite_type == 21:
        atlas_id = 32
    elif sprite_type == 22:
        atlas_id = 33
    elif sprite_type == 23:
        atlas_id = 34
    elif sprite_type == 24:
        atlas_id = 35
    if atlas_id is not None and row < 32 and col < 32 and ATLAS and (atlas_id * 1024 + row * 32 + col) < len(ATLAS):
        return ATLAS[atlas_id * 1024 + row * 32 + col]

    if sprite_type == 0:
        if (row in (0, 1)) and col in (7, 8):
            return 0x6
        if 2 <= row <= 5 and (7 - (row & 3)) <= col <= (8 + (row & 3)):
            return 0x6 if row == 2 else 0x3
        if ((5 <= row <= 8 and 3 <= col <= 12) or (row == 9 and 1 <= col <= 14)):
            return 0x6 if (row == 5 or col in (3, 12)) else 0x4
        if 10 <= row <= 12 and 0 <= col <= 15:
            return 0x3 if (col <= 2 or col >= 13) else 0x4
        if row == 13 and 4 <= col <= 11:
            return 0x3
        if row >= 14 and 6 <= col <= 9:
            return 0x4 if (frame & 1) else 0x8
        return 0
    if sprite_type == 1:
        if ((col <= 4 and 3 <= row <= 10 and col + row >= 6 and row >= col) or
                (col >= 11 and 5 <= row <= 13 and col + row <= 24)):
            return 0x6
        if 5 <= row <= 11 and 5 <= col <= 10:
            return 0x3 if (7 <= row <= 10 and 6 <= col <= 9) else 0x6
        if (frame & 1) and row == 12 and 6 <= col <= 9:
            return 0x4
        return 0
    if sprite_type == 2:
        ring_a = 2 <= row <= 13 and 4 <= col <= 11 and (row in (2, 13) or col in (4, 11))
        ring_b = 4 <= row <= 11 and 2 <= col <= 13 and (row in (4, 11) or col in (2, 13))
        if ring_a or ring_b:
            return 0x6
        if 5 <= row <= 10 and 5 <= col <= 10:
            return 0x6 if (7 <= row <= 8 and 7 <= col <= 8) else 0x3
        if (frame & 1) and row in (1, 14) and 7 <= col <= 8:
            return 0x4
        return 0
    if sprite_type == 3:
        body = ((4 <= row <= 11 and 3 <= col <= 12) or
                (6 <= row <= 9 and 1 <= col <= 14))
        if row in (7, 8) and 7 <= col <= 8:
            return 0x6
        if body:
            return 0x8 if row in (6, 9) and 6 <= col <= 9 else 0x5
        return 0
    if sprite_type == 4:
        if 1 <= row <= 13 and 6 <= col <= 9:
            return 0x6 if col in (7, 8) and row < 10 else 0x4
        if 10 <= row <= 14 and 5 <= col <= 10:
            return 0x8 if (frame & 1) else 0x4
        return 0
    if sprite_type == 5:
        if 2 <= row <= 12 and 6 <= col <= 9:
            return 0x4 if 4 <= row <= 9 and 7 <= col <= 8 else 0x3
        if 11 <= row <= 14 and 5 <= col <= 10:
            return 0x8
        return 0
    if sprite_type == 6:
        body = (row == col) or (row + col == 15) or (5 <= row <= 10 and 5 <= col <= 10) or \
            (row in (7, 8) or col in (7, 8))
        if body:
            return 0x3 if (frame & 2) else (0x4 if (frame & 1) else 0x6)
        return 0
    if sprite_type == 7:
        if (2 <= row <= 13 and 7 <= col <= 8) or (2 <= col <= 13 and 7 <= row <= 8):
            return 0xA
        if 6 <= row <= 9 and 6 <= col <= 9:
            return 0x6
        return 0
    if sprite_type == 8:
        if 0 <= row <= 15 and 7 <= col <= 8:
            return 0x9 if (row & 2) else 0x6
        if row in (0, 15) and 5 <= col <= 10:
            return 0x9
        return 0
    dx = abs(col - 15)
    dy = abs(row - 15)
    m = dx + dy
    if sprite_type == 9:
        dx16 = abs(col - 15)
        if 1 <= row <= 5 and 9 <= col <= 22 and (row in (1, 2) or col in (9, 10, 21, 22)):
            return 0x6
        if 4 <= row <= 11 and dx16 <= 5:
            return 0x4 if row <= 8 else 0x6
        if 8 <= row <= 14 and dx16 <= 4:
            return 0x8
        if 13 <= row <= 23 and dx16 <= (row - 9):
            return 0x3 if (row + col + frame) & 2 else 0x8
        if 12 <= row <= 21 and (3 <= col <= 9 or 22 <= col <= 28):
            return 0x6 if (row + frame) & 1 else 0x8
        if 20 <= row <= 27 and (10 <= col <= 14 or 17 <= col <= 21):
            return 0x6 if row <= 23 else 0x3
        if row >= 27 and 12 <= col <= 19:
            return 0xF if (frame & 1) else 0x4
        if 14 <= row <= 16 and 14 <= col <= 17:
            return 0x6
        return 0
    if sprite_type == 10:
        color = 0
        dx16 = abs(col - 15)
        if 5 <= row <= 14 and (3 <= col <= 10 or 21 <= col <= 28):
            color = 0x9 if ((row + col + frame) & 2) else 0x6
        if 4 <= row <= 10 and dx16 <= 4:
            color = 0x4
        if 10 <= row <= 22 and dx16 <= (row - 7):
            color = 0x5 if (frame & 1) else 0x8
        if 20 <= row <= 28 and 12 <= col <= 19:
            color = 0x6
        return color
    if sprite_type == 11:
        color = 0
        if 10 <= m <= 17:
            color = 0x6
        elif m < 10 and dx <= 11 and dy <= 11:
            color = 0x9 if m < 5 else 0x3
        if (row in (2, 29) or col in (2, 29)) and (dx <= 8 or dy <= 8):
            color = 0x4 if (frame & 1) else 0x8
        if (((row >> 1) == (col >> 1)) or (((row >> 1) + (col >> 1)) == 15)) and 7 < m < 21:
            color = 0xD if (frame & 2) else 0x5
        return color
    if sprite_type == 12:
        color = 0
        body = (8 <= row <= 23 and 5 <= col <= 26) or (12 <= row <= 19 and 1 <= col <= 30)
        if body:
            color = 0x8 if 11 <= row <= 14 and 12 <= col <= 19 else 0x5
        if 14 <= row <= 17 and 14 <= col <= 17:
            color = 0x6
        if (5 <= row <= 9 and 12 <= col <= 19) or (22 <= row <= 26 and 10 <= col <= 21):
            color = 0x9 if (frame & 1) else 0x8
        return color
    if sprite_type == 13:
        if 7 <= m <= 16:
            return 0xA
        if m < 8 or (13 <= row <= 18 and 13 <= col <= 18):
            return 0x6
        if (3 <= row <= 28 and 15 <= col <= 16) or (3 <= col <= 28 and 15 <= row <= 16):
            return 0x9 if (frame & 1) else 0xA
        return 0
    if sprite_type in (14, 15, 16):
        dx64 = abs(col - 31)
        dy64 = abs(row - 31)
        mm64 = dx64 + dy64
        color = 0
        if 6 <= row <= 24 and (5 <= col <= 22 or 41 <= col <= 58):
            color = 0x9 if ((row + col + frame) & 4) else 0x6
        if 8 <= row <= 18 and dx64 <= 7:
            color = 0x4 if sprite_type == 16 else 0xC
        if 18 <= row <= 42 and dx64 <= (row - 12):
            color = 0x8 if sprite_type == 14 else (0x5 if sprite_type == 15 else 0xE)
        if 28 <= row <= 50 and dx64 <= 13:
            color = 0x6 if ((row + frame) & 2) else color
        if 42 <= row <= 58 and (17 <= col <= 28 or 35 <= col <= 46):
            color = 0x6
        if dx64 <= 7 and 9 <= row <= 16:
            color = 0x6
        if (dx64 <= 18 and dy64 <= 25 and 38 <= mm64 <= 45):
            color = 0xF if (frame & 2) else 0x8
        if row <= 7 and 22 <= col <= 40:
            color = 0xF
        return color
    if sprite_type == 17:
        dx8 = abs(col - 7)
        dy8 = abs(row - 7)
        mm = dx8 + dy8
        if 5 <= mm <= 9:
            return 0x5 if (frame & 1) else 0x8
        if mm <= 3 or ((row & 3) == (frame & 3) and dx8 <= 6 and dy8 <= 6):
            return 0x6
        return 0
    if sprite_type == 18:
        dx8 = abs(col - 7)
        dy8 = abs(row - 7)
        mm = dx8 + dy8
        if (dx8 <= 1 and dy8 <= 6) or (dy8 <= 1 and dx8 <= 6):
            return 0x6
        if dx8 == dy8 and mm <= 10:
            return 0x4 if (frame & 1) else 0xE
        if mm <= 5:
            return 0xF
        return 0
    if sprite_type == 19:
        if (1 <= row <= 14 and 6 <= col <= 9) or (7 <= row <= 12 and 2 <= col <= 13):
            return 0x9 if col in (7, 8) else 0x4
        if ((row + col + frame) & 7) == 0:
            return 0x6
        return 0
    if sprite_type == 20:
        dx8 = abs(col - 7)
        dy8 = abs(row - 7)
        mm = dx8 + dy8
        body = (dx8 <= 5 and dy8 <= 3) or (dx8 <= 3 and dy8 <= 5) or (dx8 <= 4 and dy8 <= 4)
        color = 0xA if body else 0
        if dx8 <= 2 and dy8 <= 2:
            color = 0x6
        if mm in (6, 7) and (((row & 3) + (col & 3) + (frame & 3)) & 3) == 0:
            color = 0x9 if (frame & 1) else 0xF
        return color
    if sprite_type in (21, 22, 23, 24):
        color = 0
        orb = (dx <= 13 and dy <= 8) or (dx <= 8 and dy <= 13) or (dx <= 11 and dy <= 11)
        core = (dx <= 9 and dy <= 5) or (dx <= 5 and dy <= 9) or (dx <= 7 and dy <= 7)
        if orb:
            color = 0xA if sprite_type == 21 else (0x9 if sprite_type == 22 else (0xE if sprite_type == 23 else 0x4))
        if core:
            color = 0x6
        if sprite_type == 21 and ((8 <= row <= 24 and 11 <= col <= 20) or (20 <= row <= 25 and 14 <= col <= 17)):
            color = 0x2 if (frame & 1) else 0xA
        if sprite_type == 22 and ((9 <= row <= 13 and 5 <= col <= 26) or (18 <= row <= 24 and 8 <= col <= 23)):
            color = 0x8 if (frame & 1) else 0x9
        if sprite_type == 23 and ((7 <= row <= 10 and 9 <= col <= 22) or (21 <= row <= 24 and 9 <= col <= 22) or
                                  (11 <= row <= 20 and 14 <= col <= 17)):
            color = 0xC if (frame & 1) else 0xE
        if sprite_type == 24 and (((dx <= 2 and dy <= 11) or (dy <= 2 and dx <= 11) or
                                   (7 <= dx <= 10 and 7 <= dy <= 10)) and m <= 20):
            color = 0xF if (frame & 1) else 0x4
        return color
    return 0x6 if 4 <= row <= 11 and 4 <= col <= 11 else 0


FONT = {
    "0": [0x3C, 0x66, 0x6E, 0x76, 0x66, 0x66, 0x3C, 0x00],
    "1": [0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00],
    "2": [0x3C, 0x66, 0x06, 0x1C, 0x30, 0x60, 0x7E, 0x00],
    "3": [0x3C, 0x66, 0x06, 0x1C, 0x06, 0x66, 0x3C, 0x00],
    "4": [0x0C, 0x1C, 0x3C, 0x6C, 0x7E, 0x0C, 0x0C, 0x00],
    "5": [0x7E, 0x60, 0x7C, 0x06, 0x06, 0x66, 0x3C, 0x00],
    "6": [0x1C, 0x30, 0x60, 0x7C, 0x66, 0x66, 0x3C, 0x00],
    "7": [0x7E, 0x06, 0x0C, 0x18, 0x30, 0x30, 0x30, 0x00],
    "8": [0x3C, 0x66, 0x66, 0x3C, 0x66, 0x66, 0x3C, 0x00],
    "9": [0x3C, 0x66, 0x66, 0x3E, 0x06, 0x0C, 0x38, 0x00],
    "A": [0x18, 0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x00],
    "B": [0x7C, 0x66, 0x66, 0x7C, 0x66, 0x66, 0x7C, 0x00],
    "C": [0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00],
    "D": [0x7C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x7C, 0x00],
    "E": [0x7E, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x7E, 0x00],
    "F": [0x7E, 0x60, 0x60, 0x7C, 0x60, 0x60, 0x60, 0x00],
    "G": [0x3C, 0x66, 0x60, 0x6E, 0x66, 0x66, 0x3E, 0x00],
    "H": [0x66, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00],
    "I": [0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0x00],
    "K": [0x66, 0x6C, 0x78, 0x70, 0x78, 0x6C, 0x66, 0x00],
    "L": [0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x7E, 0x00],
    "M": [0x63, 0x77, 0x7F, 0x6B, 0x63, 0x63, 0x63, 0x00],
    "N": [0x66, 0x76, 0x7E, 0x7E, 0x6E, 0x66, 0x66, 0x00],
    "O": [0x3C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00],
    "P": [0x7C, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x60, 0x00],
    "R": [0x7C, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0x00],
    "S": [0x3E, 0x60, 0x60, 0x3C, 0x06, 0x06, 0x7C, 0x00],
    "T": [0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x00],
    "U": [0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x00],
    "V": [0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x18, 0x00],
    "W": [0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0x00],
    "X": [0x66, 0x66, 0x3C, 0x18, 0x3C, 0x66, 0x66, 0x00],
    "Y": [0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0x18, 0x00],
    "Z": [0x7E, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x7E, 0x00],
    ":": [0x00, 0x18, 0x18, 0x00, 0x18, 0x18, 0x00, 0x00],
    "/": [0x06, 0x0C, 0x0C, 0x18, 0x30, 0x30, 0x60, 0x00],
    "!": [0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x00],
    " ": [0x00] * 8,
}


def font_bits(ch, row):
    return FONT.get(ch, [0x7E, 0x42, 0x0C, 0x18, 0x00, 0x18, 0x18, 0x00])[row & 7]


def font_sample(ch, row, col):
    return (font_bits(ch, row) & (1 << (7 - col))) != 0


def put_pixel(buf, x, y, rgb):
    if 0 <= x < WIDTH and 0 <= y < HEIGHT:
        off = (y * WIDTH + x) * 3
        buf[off:off + 3] = bytes(rgb)


def render_frame(meta, sprites, text_words, text_pos):
    frame = int(meta.get("frames", "0"))
    buf = bytearray(WIDTH * HEIGHT * 3)

    for y in range(HEIGHT):
        row_off = y * WIDTH * 3
        for x in range(WIDTH):
            rgb = background_pixel(x, y, frame)
            off = row_off + x * 3
            buf[off:off + 3] = bytes(rgb)

    for word in sprites:
        if ((word >> 31) & 1) == 0:
            continue
        tint = (word >> 29) & 0x3
        sprite_type = (word >> 24) & 0x1F
        sprite_frame = (word >> 20) & 0xF
        sy = (word >> 10) & 0x3FF
        sx = word & 0x3FF
        size = 64 if 14 <= sprite_type <= 16 else (
            32 if (9 <= sprite_type <= 13 or 21 <= sprite_type <= 24) else 16
        )
        for row in range(size):
            py = sy + row
            if py >= HEIGHT:
                continue
            for col in range(size):
                px = sx + col
                if px >= WIDTH:
                    continue
                color_id = sprite_pixel(sprite_type, sprite_frame, row, col)
                if color_id != 0:
                    put_pixel(buf, px, py, palette(color_id, tint))

    for line in range(TEXT_LINES):
        pos = text_pos[line]
        if ((pos >> 27) & 1) == 0:
            continue
        tx = pos & 0x3FF
        ty = (pos >> 10) & 0x3FF
        char_count = (pos >> 20) & 0x7F
        color = (pos >> 28) & 0xF
        rgb = palette(color, 0)
        glow_rgb = palette(color, 3)
        for char_index in range(char_count):
            word = text_words[line * 4 + (char_index >> 2)]
            ch = chr((word >> ((char_index & 3) * 8)) & 0xFF)
            for rel_y in range(16):
                font_row = rel_y >> 1
                py = ty + rel_y
                if py >= HEIGHT:
                    continue
                for rel_x in range(8):
                    core = font_sample(ch, font_row, rel_x)
                    glow = False
                    if rel_x > 0 and font_sample(ch, font_row, rel_x - 1):
                        glow = True
                    if font_row > 0 and font_sample(ch, font_row - 1, rel_x):
                        glow = True
                    if rel_x > 0 and font_row > 0 and font_sample(ch, font_row - 1, rel_x - 1):
                        glow = True
                    if core:
                        put_pixel(buf, tx + char_index * 8 + rel_x, py, rgb)
                    elif glow:
                        put_pixel(buf, tx + char_index * 8 + rel_x, py, glow_rgb)

    return buf


def write_png(path, rgb):
    raw = bytearray()
    stride = WIDTH * 3
    for y in range(HEIGHT):
        raw.append(0)
        raw.extend(rgb[y * stride:(y + 1) * stride])

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data +
                struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--modes", nargs="+", default=["menu", "game", "hard2p"])
    parser.add_argument("--out-dir", default=os.path.join(PROJ_DIR, "build", "host_game_preview"))
    args = parser.parse_args()

    build_dumper()
    os.makedirs(args.out_dir, exist_ok=True)
    for mode in args.modes:
        meta, sprites, text_words, text_pos = capture_regs(mode)
        image = render_frame(meta, sprites, text_words, text_pos)
        out_path = os.path.join(args.out_dir, f"{mode}.png")
        write_png(out_path, image)
        print(out_path)


if __name__ == "__main__":
    main()
