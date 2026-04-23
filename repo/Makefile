DIR_BUILD		:= $(CURDIR)/build
DIR_PATCH		:= $(CURDIR)/patch
DIR_UPSTREAM	:= $(CURDIR)/sys-project

# compile for the ip folder
SPIKE_DIR		:= $(CURDIR)/riscv-isa-cosim
SPIKE_SRC		:= $(shell find $(SPIKE_DIR) -name "*.cc" -o -name "*.h" -o -name "*.c")
SPIKE_LIB		:= $(addprefix $(SPIKE_BUILD)/,libcosim.a libriscv.a libdisasm.a libsoftfloat.a libfesvr.a libfdt.a)
SPIKE_INCLUDE	:= $(SPIKE_DIR) $(SPIKE_DIR)/cosim $(SPIKE_DIR)/fdt $(SPIKE_DIR)/fesvr \
			       $(SPIKE_DIR)/riscv $(SPIKE_DIR)/softfloat $(SPIKE_BUILD)
IP_BUILD		:= $(DIR_BUILD)/ip
DIR_COSIM_IP	:= $(DIR_UPSTREAM)/ip

export LD_LIBRARY_PATH=$(IP_BUILD)
$(IP_BUILD)/patch:
	mkdir -p $(IP_BUILD)
	cd $(SPIKE_DIR) ; git apply $(DIR_PATCH)/riscv-isa-cosim/*
	touch $(IP_BUILD)/patch

$(IP_BUILD)/Makefile:
	mkdir -p $(IP_BUILD)
	cd $(IP_BUILD); $(SPIKE_DIR)/configure --prefix=$(DIR_COSIM_IP)

ip_gen:$(SPIKE_SRC) $(IP_BUILD)/Makefile $(IP_BUILD)/patch
	mkdir -p $(DIR_COSIM_IP)
	make -C $(IP_BUILD) -j$(shell nproc) $(notdir $(SPIKE_LIB))
	make -C $(IP_BUILD) install

#compiler for verilator
VLT_DIR 	:= $(CURDIR)/verilator
VLT_BUILD	:= $(DIR_BUILD)/verilator
$(VLT_BUILD)/Makefile:
	mkdir -p $(VLT_BUILD)
	cd $(VLT_DIR); autoconf
	cd $(VLT_BUILD); $(VLT_DIR)/configure 

verilator:$(VLT_BUILD)/Makefile $(VLT_DIR)
	make -C $(VLT_BUILD) -j$(shell nproc)
	make -C $(VLT_BUILD) install
	verilator --version

#compiler for opensbi
OPENSBI_DIR		:=	$(CURDIR)/opensbi
OPENSBI_BUILD	:=  $(DIR_BUILD)/opensbi
FW_JUMP_BUILD	:=  $(OPENSBI_BUILD)/platform/generic/firmware/fw_jump.bin $(OPENSBI_BUILD)/platform/generic/firmware/fw_jump.elf
FW_JUMP			:=  $(DIR_UPSTREAM)/spike/fw_jump.bin $(DIR_UPSTREAM)/spike/fw_jump.elf

$(OPENSBI_BUILD)/patch:
	mkdir -p $(OPENSBI_BUILD)
	cd $(OPENSBI_DIR); git apply $(DIR_PATCH)/opensbi/*
	touch $(OPENSBI_BUILD)/patch

$(FW_JUMP_BUILD):$(OPENSBI_SRC) $(OPENSBI_BUILD)/patch
	make -C $(OPENSBI_DIR) O=$(OPENSBI_BUILD) \
		CROSS_COMPILE=riscv64-linux-gnu- \
		PLATFORM=generic

$(FW_JUMP):$(FW_JUMP_BUILD)
	cp $(FW_JUMP_BUILD) $(DIR_UPSTREAM)/spike/

fw_jump:$(FW_JUMP)

#compiler for spike
SPIKE_BUILD	:= $(DIR_BUILD)/spike

spike:$(SPIKE_DIR)
	mkdir -p $(SPIKE_BUILD)
	cd $(SPIKE_BUILD) ; $(SPIKE_DIR)/configure
	make -C $(SPIKE_BUILD) -j$(shell nproc)
	make -C $(SPIKE_BUILD) install

#compiler for openocd
OPENOCD_DIR 	:= $(CURDIR)/riscv-openocd
OPENOCD_BUILD	:= $(DIR_BUILD)/openocd

openocd:$(OPENOCD_DIR)
	mkdir -p $(OPENOCD_BUILD)
	cd $(OPENOCD_DIR); ./bootstrap;
	cd $(OPENOCD_BUILD); $(OPENOCD_DIR)/configure
	make -C $(OPENOCD_BUILD) -j$(shell nproc)
	make -C $(OPENOCD_BUILD) install
	openocd --version



