create_clock -period 10.000 -name sys_clk [get_ports sys_clk]
create_clock -period 5.000 -name ddr_clk [get_ports ddr_clk_p]

set_property PACKAGE_PIN E3 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property PACKAGE_PIN U18 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

set_property PACKAGE_PIN E17 [get_ports ddr_clk_p]
set_property IOSTANDARD DIFF_SSTL135 [get_ports ddr_clk_p]
set_property PACKAGE_PIN E18 [get_ports ddr_clk_n]
set_property IOSTANDARD DIFF_SSTL135 [get_ports ddr_clk_n]

set_property PACKAGE_PIN M19 [get_ports {hdmi_tx_clk_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_clk_p[0]}]
set_property PACKAGE_PIN L20 [get_ports {hdmi_tx_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_p[0]}]
set_property PACKAGE_PIN J19 [get_ports {hdmi_tx_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_p[1]}]
set_property PACKAGE_PIN H17 [get_ports {hdmi_tx_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_p[2]}]
set_property PACKAGE_PIN J18 [get_ports {hdmi_tx_data_p[3]}]
set_property IOSTANDARD TMDS_33 [get_ports {hdmi_tx_data_p[3]}]

set_property PACKAGE_PIN T13 [get_ports gpio_usb_int]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_usb_int]
set_property PACKAGE_PIN V13 [get_ports gpio_usb_rst]
set_property IOSTANDARD LVCMOS33 [get_ports gpio_usb_rst]
set_property PACKAGE_PIN T12 [get_ports spi_ss]
set_property IOSTANDARD LVCMOS33 [get_ports spi_ss]
set_property PACKAGE_PIN V14 [get_ports spi_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports spi_sclk]
set_property PACKAGE_PIN V15 [get_ports spi_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports spi_mosi]
set_property PACKAGE_PIN U12 [get_ports spi_miso]
set_property IOSTANDARD LVCMOS33 [get_ports spi_miso]

set_property PACKAGE_PIN R18 [get_ports audio_pwm]
set_property IOSTANDARD LVCMOS33 [get_ports audio_pwm]

set_property DCI_CASCADE {32 34} [get_iobanks 33]

set_property INTERNAL_VREF 0.750 [get_iobanks 34]

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets gpio_usb_int_IBUF]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property PROHIBIT true [get_sites U5]
set_property PROHIBIT true [get_sites U6]

config_timing_summary -prefix timing_summary.rpt -no_effort medium