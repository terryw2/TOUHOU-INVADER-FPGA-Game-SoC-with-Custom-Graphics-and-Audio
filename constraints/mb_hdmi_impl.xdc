## The AXI/MicroBlaze domain updates display/audio registers at software speed.
## The HDMI pixel/serial clocks scan those registers continuously; keep the two
## HDMI clocks related to each other, but do not close timing across that CDC.
set_clock_groups -asynchronous \
    -group [get_clocks -quiet {clk_out1_mb_system_clk_wiz_1_0 clk_out2_mb_system_clk_wiz_1_0 clk_out3_mb_system_clk_wiz_1_0}] \
    -group [get_clocks -quiet -of_objects [get_pins -quiet {clocking_i/mmcm_i/CLKOUT0 clocking_i/mmcm_i/CLKOUT1}]]
