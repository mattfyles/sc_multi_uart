# The TARGET variable determines what target system the application is
# compiled for. It either refers to an XN file in the source directories
# or a valid argument for the --target option when compiling
#TARGET = MCB_UART
#TARGET = XK1_UART
TARGET = xp-skc-l2-single

# The APP_NAME variable determines the name of the final .xe file. It should
# not include the .xe postfix. If left blank the name will default to
# the project name
APP_NAME = multi_uart_demo

# The USED_MODULES variable lists other module used by the application.
USED_MODULES = module_multi_uart

XCC_FLAGS = -g -O3 -Wall -Wtiming -report -save-temps -Xmapper --map -Xmapper MAPFILE

XCC_FLAGS_Debug = $(XCC_FLAGS)
XCC_FLAGS_Release = $(XCC_FLAGS)

# The VERBOSE variable, if set to 1, enables verbose output from the make
# system.
VERBOSE = 0

#=============================================================================
# The following part of the Makefile includes the common build infrastructure
# for compiling XMOS applications. You should not need to edit below here.

XMOS_MAKE_PATH ?= ../..
include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common

runsim: generate_rx all
	xsim -t --trace-to uart_trace.log --vcd-tracing "-o uart_sim.vcd -ports -ports-detailed" bin/$(APP_NAME).xe

runsim_loop: generate_rx all
	xsim -t --trace-to uart_trace.log --plugin LoopbackPort.dll "-port stdcore[0] XS1_PORT_8A 8 0 -port stdcore[0] XS1_PORT_8B 8 0" --vcd-tracing "-o uart_sim.vcd -ports -ports-detailed" bin/Release/$(APP_NAME).xe
	
run: generate_rx all
	xrun --io bin/Release/multi_uart_demo.xe

run_xscope: generate_rx all
	xrun --xscope --io bin/multi_uart_demo.xe

generate_rx: ../module_multi_uart/gen/template ../module_multi_uart/gen/template_start ../module_multi_uart/gen/template_end
	cd ../module_multi_uart/gen; make all
