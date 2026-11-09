TOUHOU INVADER
A Touhou-themed bullet-hell shoot-'em-up running on a Xilinx MicroBlaze
soft-core CPU with custom AXI peripherals (HDMI text controller, square-wave
audio engine, DDR3 memory controller, and lwUSB HID keyboard via MAX3421E).
Renders 96 hardware sprites at 60 Hz over HDMI, with synth music (Luna Dial)
and 8 collectible powerups.

Game modes

ARCADE — 6 stages, locked NORMAL difficulty
ENDLESS NIGHT — Endless waves, choose EASY/NORMAL/HARD
KAGUYA — Boss-only fight, locked HARD
PHANTASM — AI-friendly demo run, locked NORMAL
SHOWCASE — Sandbox to demo all 8 powerups (keys 1-8)

Controls

WASD / Arrows — move player (P1 / P2)
X — focus mode (slow movement, tighter shot pattern)
Z — Sakuya's time-stop (1 charge per stage)
SPACE / Enter — start
ESC — pause, R / Q — return to menu
P or Konami code — enable autoplay AI

How to run
You need Vivado 2022.2 and Vitis 2022.2 installed.

Use the mb_hdmi_platform.xsa in Vivado and 
Open Vitis IDE and switch the workspace to: vitis_ws_bram_ddr3_playfeel_v6
Right-click the project → Clean Project, then Build Project.
Right-click → Run As → Launch Hardware (or Debug As) to flash the bitstream and download the ELF.

For the FPGA, you must use external power mode which is powered by the USB-C

This project builds on standard course-provided and openly available components: the lwUSB host stack (lw_usb/ folder) is adapted from  MAX3421E reference driver as used in the ECE 385 USB lab framework; the MicroBlaze platform initialization (platform.c, main.c boot setup, UART output) follows the Xilinx Vitis template; and the AXI peripheral skeleton structure (hdmi_text_controller_v1_0_AXI.sv and surrounding wiring) follows the standard ECE 385 course scaffold. The Luna Dial background music note data was extracted from a publicly available MIDI of the Touhou 6 original soundtrack (composed by ZUN / Team Shanghai Alice) and played back through our custom audio engine.
For the C game logic in game.c, we used AI assistance for debugging, refactoring, and exploring design alternatives. All design decisions, gameplay tuning, hardware integration, and the SystemVerilog peripherals were authored and verified by the team.