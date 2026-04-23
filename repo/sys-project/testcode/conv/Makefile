RISCV_PREFIX ?= riscv64-linux-gnu-
RISCV_GCC ?= $(RISCV_PREFIX)gcc
RISCV_GCC_OPTS ?= -march=rv64i -mabi=lp64 -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -DNOBRANCH
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump -Mno-aliases -D
RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy -O binary
RISCV_LD  	  ?= $(RISCV_PREFIX)ld

SRC_C	=	./main.c ../uart/uart.c ../kernel/conv.c
SRC_S	=	./head.S

INCLUDE_FLAG = -I ../uart -I ../kernel

SRC_OBJ =   $(SRC_C:.c=.o) $(SRC_S:.S=.o)

TESTCASE = testcase
TESTCASE_ELF := $(TESTCASE).elf
TESTCASE_ASM := $(TESTCASE).asm
TESTCASE_HEX := $(TESTCASE).hex

testcase.hex: testcase.elf
	${RISCV_OBJCOPY} $(TESTCASE_ELF) tmp
	od -v -An -tx8 tmp > $(TESTCASE_HEX)
	rm -f tmp $(TESTCASE_OBJ)

testcase.elf: $(SRC_OBJ)
	$(RISCV_LD) -T link.ld $(SRC_OBJ) -o $(TESTCASE_ELF)
	$(RISCV_OBJDUMP) $(TESTCASE_ELF) > $(TESTCASE_ASM)

%.o: %.S
	$(RISCV_GCC) $(RISCV_GCC_OPTS) $(INCLUDE_FLAG) -c $< -o $@

%.o: %.c
	$(RISCV_GCC) $(RISCV_GCC_OPTS) $(INCLUDE_FLAG) -c $< -o $@

clean:
	rm -rf *.o testcase.* 2> /dev/null
