set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.Config.SPI_buswidth 4 [current_design]

set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports Clk]
create_clock -period 10.000 -name Clk [get_ports Clk]
set_property -dict {PACKAGE_PIN J2  IOSTANDARD LVCMOS25} [get_ports reset_rtl_0]
set_property PULLDOWN true [get_ports reset_rtl_0]

set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports uart_rtl_0_rxd]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports uart_rtl_0_txd]

set_property -dict {PACKAGE_PIN T13 IOSTANDARD LVCMOS33} [get_ports {gpio_usb_int_tri_i[0]}]
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports gpio_usb_rst_tri_o]
set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports usb_spi_miso]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports usb_spi_mosi]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports usb_spi_sclk]
set_property -dict {PACKAGE_PIN T12 IOSTANDARD LVCMOS33} [get_ports usb_spi_ss]

set_property -dict {PACKAGE_PIN U16 IOSTANDARD TMDS_33} [get_ports hdmi_tmds_clk_p]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD TMDS_33} [get_ports hdmi_tmds_clk_n]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_p[0]}]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_n[0]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_p[1]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_n[1]}]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_p[2]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD TMDS_33} [get_ports {hdmi_tmds_data_n[2]}]

set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports spkl]
set_property -dict {PACKAGE_PIN B14 IOSTANDARD LVCMOS33} [get_ports spkr]

set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

set_false_path -to [get_pins -quiet -hierarchical -regexp {.*ddr_ready_sync.*/sync_pipe_reg\[0\]/D}]
