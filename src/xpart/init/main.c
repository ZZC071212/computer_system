#include "printk.h"
#include "types.h"
#include "sbi.h"

extern void test();

int start_kernel(uint64 input) {

    #ifdef DEBUG
    printk(" ZJU Computer System II\n");
    #endif

    test(); // DO NOT DELETE !!!

	return 0;
}

// void testLemon(uint64 input) {
//     printk("Well come to testLemon(), this will show the value of A0.\n");
//     printk("current a0: %lx \n", input);
// }