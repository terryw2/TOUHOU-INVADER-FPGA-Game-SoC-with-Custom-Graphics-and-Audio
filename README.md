# FPGA Space Invaders Game
### SoC Design with Custom Graphics and Audio

A Space Invaders–style bullet-hell game running on a **Spartan-7 FPGA**, combining a **MicroBlaze soft-core processor** with custom graphics and audio hardware. The game supports keyboard input, multiple game modes, boss encounters, and synchronized video and audio over HDMI.

The implementation is also known as **TOUHOU INVADER**, reflecting its original visual and musical theme.

## Highlights

- **Hardware graphics:** 96 sprite slots, tilemap backgrounds, and text overlays with 640 × 480 video output at approximately 60 Hz.
- **Custom audio:** a three-channel audio engine for background music and sound effects, integrated with HDMI audio output.
- **Hardware/software integration:** C game logic on MicroBlaze communicates with custom peripherals through AXI4-Lite.
- **External memory:** DDR3 integration using the Xilinx MIG controller and custom linker sections for larger game-state allocations.
- **USB input:** MAX3421E keyboard interface using an adapted lwUSB host stack.
- **Gameplay:** six arcade stages, boss fights, eight powerups, two-player controls, and automatic demonstration play.

## System Architecture

| Component | Responsibility |
| --- | --- |
| MicroBlaze firmware | Game state, player and enemy behavior, collision handling, and music sequencing |
| Graphics hardware | Sprite composition, tilemap rendering, and text display |
| Audio hardware | Tone generation and mixing of music and sound effects |
| HDMI subsystem | Video and audio output using integrated transmitter and packetization modules |
| DDR3 subsystem | External memory access through Xilinx MIG |
| USB subsystem | Keyboard input through MAX3421E over SPI |

## Game Modes

| Mode | Description |
| --- | --- |
| ARCADE | Six stages at Normal difficulty |
| ENDLESS NIGHT | Endless waves with Easy, Normal, or Hard difficulty |
| KAGUYA | Boss-only challenge at Hard difficulty |
| PHANTASM | Demonstration mode suited to automatic play |
| SHOWCASE | Sandbox for demonstrating all eight powerups |

## Controls

| Key | Action |
| --- | --- |
| WASD / Arrow keys | Move Player 1 / Player 2 |
| X | Focus mode: slower movement and a tighter shot pattern |
| Z | Time-stop ability, with one charge per stage |
| Space / Enter | Start |
| Esc | Pause |
| R / Q | Return to the menu |
| P / Konami code | Enable automatic play |
| 1–8 | Demonstrate powerups in Showcase mode |

## Repository Contents

| Path | Contents |
| --- | --- |
| [`src/hardware/`](src/hardware/) | SystemVerilog hardware modules and graphics initialization data |
| [`src/software/`](src/software/) | C firmware, drivers, game assets, and linker scripts |
| [`constraints/`](constraints/) | FPGA constraints |
| [`sim/`](sim/) | HDL testbenches and host-side game tests and preview tools |
| [`vivado/`](vivado/) | Vivado project, block design, and IP configuration |
| [`reports/`](reports/) | Saved timing and routing reports |

## Development Environment and Build Status

- **Hardware:** Urbana board with a Xilinx Spartan-7 XC7S50 FPGA, USB keyboard, and HDMI display.
- **Tools:** Vivado 2022.2 and Vitis 2022.2.
- **Power:** use the board's external USB-C power configuration.

This repository contains source files and project configuration. Vivado build outputs, the original Vitis workspace, and prebuilt XSA, bitstream, and ELF files are not included. A clean rebuild of this uploaded source snapshot has not yet been verified.

To reconstruct the development environment, start from `vivado/mb_hdmi_game.xpr`, validate the block design, regenerate its output products and HDL wrapper as needed, and build the hardware. Then export an XSA including the bitstream and create a MicroBlaze standalone platform and application in Vitis. The application uses `src/software/`, the USB driver sources, and the project's BRAM/DDR3 linker configuration. These are setup guidelines rather than a verified end-to-end build procedure.

## Credits and Third-Party Components

This is a team-developed project. Custom graphics, audio, firmware, and integration work build on existing platform and interface components:

- **AMD/Xilinx:** MicroBlaze, MIG, AXI infrastructure, and platform support.
- **HDMI modules:** selected modules from [hdl-util/hdmi](https://github.com/hdl-util/hdmi), with project-specific adaptation modules. Original author headers and MIT/Apache-2.0 license files are retained in [`src/hardware/hdmi_audio/`](src/hardware/hdmi_audio/).
- **USB and AXI reference frameworks:** the MAX3421E/lwUSB stack and AXI peripheral scaffolding were adapted from supplied reference implementations.
- **Music and artwork:** the original game uses Touhou-themed assets. Luna Dial note data was converted from a publicly available MIDI of music composed by ZUN / Team Shanghai Alice. Asset attribution does not itself establish redistribution permission.

No repository-wide open-source license is currently declared. Third-party components retain their respective terms; their licenses do not automatically cover the entire project or its artwork and music.
