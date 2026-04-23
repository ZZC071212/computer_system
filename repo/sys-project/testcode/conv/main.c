#include"uart.h"
#include"conv.h"

const uint64_t data[16] = {
    0x6b4d6751dfdce04c, 0x78fcc0533e3a968b, 0x16351ce76439e504, 0x7136316864aeab1d,
    0x51f81732140fd91c, 0x7a535be738ecc350, 0x7e71712b5a1a573c, 0x74dcd61d9a70a1c7,
    0xef57ec09ecfcf060, 0xf0e9ac148b47b525, 0xb615d8a600ab25b1, 0x657ade83d39783db,
    0x2fb4f2dd4fa50429, 0x336e54fbf8783c37, 0x311dddf42e319579, 0xd74761d9a97755b3,
};

const uint64_t kernel[4] = {
    0xf55d9d0a1680b66a,
    0x946b1f6531fac827,
    0x6cb756d5576cc9a0,
    0xc8b14a7d2222601b,
};

uint64_t result_conv[32+6];
uint64_t result_mul[32+6];

void print_hex(uint64_t data){
    char table[16] = "0123456789abcdef";
    for(int shift=60;shift>=0;shift-=4){
        char c = table[(data>>shift)&0xf];
        uart_tx(c);
    }
}

void print_str(const char* str){
    while(*str){
        uart_tx(*str);
        str++;
    }
}

void print_array(const uint64_t* array, size_t len){
    size_t index = 0;
    for(int i = 0; index < len;){
        for(int j=0;j<4&&index<len;j++,index++){
            print_hex(array[index]);
            uart_tx(',');
        }
        uart_tx('\n');
        uart_tx('\r');
    }
}

int main(){
    uint64_t begin;
    uint64_t end;
    print_str("kernel_array:\n\r");
    print_array(kernel, 4);
    print_str("data_array:\n\r");
    print_array(data, 16);

    begin = get_time();
    conv_compute(data, 16, kernel, 4, result_conv);
    end = get_time();
    print_str("conv time: ");
    print_hex(end-begin);
    print_str(" cycle\r\n");
    print_str("result_conv_array:\n\r");
    print_array(result_conv, 32+6);

    begin = get_time();
    mul_compute(data, 16, kernel, 4, result_mul);
    end = get_time();
    print_str("mul time: ");
    print_hex(end-begin);
    print_str(" cycle\r\n");
    print_str("result_mul_array:\n\r");
    print_array(result_mul, 32+6);
}