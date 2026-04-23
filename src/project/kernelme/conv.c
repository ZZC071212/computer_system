#include "conv.h"
#pragma GCC optimize ("O2")

typedef unsigned long long int size_t;
volatile uint64_t* CONV_BASE = (uint64_t*)0x10001000L;
const size_t CONV_KERNEL_OFFSET = 0;
const size_t CONV_DATA_OFFSET = 1;
const size_t CONV_RESULT_LO_OFFSET = 0;
const size_t CONV_RESULT_HI_OFFSET = 1;
const size_t CONV_STATE_OFFSET = 2;
const unsigned char READY_MASK = 0b01;
const size_t CONV_ELEMENT_LEN = 4;

uint64_t* MISC_BASE = (uint64_t*)0x10002000L;
const size_t MISC_TIME_OFFSET = 0;

uint64_t get_time(void){
    return MISC_BASE[MISC_TIME_OFFSET];
}

void conv_kernel_init(const uint64_t* kernel_array, size_t kernel_len) {
    for (size_t i = 0; i < kernel_len; i++) {
        CONV_BASE[CONV_KERNEL_OFFSET] = kernel_array[i];
    }
}

void conv_compute_one_byte(uint64_t data, uint64_t* result_hi, uint64_t* result_lo) {
    CONV_BASE[CONV_DATA_OFFSET] = data;
    while (!(CONV_BASE[CONV_STATE_OFFSET] & READY_MASK)); //计算完成
    *result_lo = CONV_BASE[CONV_RESULT_LO_OFFSET];
    *result_hi = CONV_BASE[CONV_RESULT_HI_OFFSET];
}

void conv_compute(const uint64_t* data_array, size_t data_len, const uint64_t* kernel_array, size_t kernel_len, uint64_t* dest) {

    conv_kernel_init(kernel_array, kernel_len);

    size_t padded_len = data_len + 2 * (kernel_len - 1);
    for (size_t i = 0; i < padded_len; i++) {
        uint64_t data;
        if (i < kernel_len - 1 || i >= data_len + kernel_len - 1) {
            data = 0;
        } else {
            data = data_array[i - (kernel_len - 1)];
        }

        uint64_t result_hi, result_lo;
        conv_compute_one_byte(data, &result_hi, &result_lo);

        if (i >= kernel_len - 1) {
            size_t dest_idx = i - (kernel_len - 1);
            dest[dest_idx * 2] = result_hi;
            dest[dest_idx * 2 + 1] = result_lo;
        }
    }
}

void mul_compute(const uint64_t* data_array, size_t data_len, const uint64_t* kernel_array, size_t kernel_len,uint64_t* dest) {

    const size_t padded_len = data_len + 6;
    uint64_t padded_data[padded_len];
    for (size_t i = 0; i < padded_len; i++) {
        padded_data[i] = (i < 3 || i >= data_len + 3) ? 0 : data_array[i - 3];
    }

    for (size_t i = 0; i < data_len + 3; i++) {
        uint64_t sum_hi = 0; 
        uint64_t sum_lo = 0; 

        for (size_t j = 0; j < kernel_len; j++) {
            const uint64_t data = padded_data[i + j];
            const uint64_t kernel = kernel_array[j];

            uint64_t partial_hi = 0; 
            uint64_t partial_lo = 0; 

            for (int bit = 0; bit < 64; bit++) {
                if ((data >> bit) & 0x1) {
                    uint64_t shifted_kernel_hi = 0;
                    uint64_t shifted_kernel_lo = kernel;

                    if (bit >= 64) {
                        shifted_kernel_hi = kernel << (bit - 64);
                        shifted_kernel_lo = 0;
                    } else {
                        shifted_kernel_hi = (bit == 0) ? 0 : (kernel >> (64 - bit));
                        shifted_kernel_lo = kernel << bit;
                    }

                    uint64_t new_lo = partial_lo + shifted_kernel_lo;
                    uint64_t carry = (new_lo < partial_lo) ? 1 : 0;
                    partial_lo = new_lo;
                    partial_hi += shifted_kernel_hi + carry;
                }
            }
            uint64_t new_sum_lo = sum_lo + partial_lo;
            uint64_t carry = (new_sum_lo < sum_lo) ? 1 : 0;
            sum_lo = new_sum_lo;
            sum_hi += partial_hi + carry;
        }

        dest[i * 2] = sum_hi;
        dest[i * 2 + 1] = sum_lo;
    }
}