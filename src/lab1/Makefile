verilate_sort:$(VERILATOR_TOP)
	make -C $(DIR_TEST)/sort
	cp $(DIR_TEST)/sort/testcase.elf $(SIM_BUILD)/testcase.elf
	cp $(DIR_TEST)/rom/rom.hex $(SIM_BUILD)/rom.hex
	cp $(DIR_TEST)/dummy/dummy.hex $(SIM_BUILD)/elf.hex
	cp $(DIR_TEST)/sort/sort.hex $(SIM_BUILD)/mini_sbi.hex
	cd $(SIM_BUILD); ./$(VERILATOR_TOP)
