ASM_SRC := $(wildcard *.S)
C_SRC := $(wildcard *.c)

ASM_OBJ := $(ASM_SRC:.S=.o)
C_OBJ := $(C_SRC:.c=.o)
OBJ := $(ASM_OBJ) $(C_OBJ)
DEPS := $(ASM_SRC:.S=.d) $(C_SRC:.c=.d)

.PHONY: all clean

all: $(OBJ)

clean:
	rm -f *.o *.d

%.o: %.S
	$(GCC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -c $<

%.o: %.c
	$(GCC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -c $<

-include $(DEPS)
