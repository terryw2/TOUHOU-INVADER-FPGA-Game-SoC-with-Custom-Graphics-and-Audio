# HDMI Audio Support

This directory contains the MicroBlaze game's HDMI audio adaptation layer plus
selected HDMI packet, ECC, InfoFrame, and TERC4 modules vendored from
`hdl-util/hdmi`.

The vendored modules keep their original author headers. The upstream project is
dual-licensed under MIT or Apache-2.0:

https://github.com/hdl-util/hdmi

Project-specific glue modules:

- `audio_sample_bridge.sv`
- `audio_clock_regeneration_fixed.sv`
- `hdmi_packet_picker_strobe.sv`
- `hdmi_external_video_encoder.sv`

