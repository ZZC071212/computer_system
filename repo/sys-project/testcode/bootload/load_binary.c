#include "load_binary.h"
uint64_t *binary_cpy(uint64_t *dest, uint64_t *src, uint64_t num) {
  while (num) {
    *dest = *src;
    if (*src != *dest) {
load_fail:
      goto load_fail;
    }
    --num;
    ++dest;
    ++src;
  }
  return src;
}

uint64_t *zero_set(uint64_t *dest, uint64_t *src, uint64_t num) {
  while (num) {
    *dest = 0;
    if (0 != *dest) {
load_fail:
      goto load_fail;
    }
    --num;
    ++dest;
  }
  return src;
}

void load_binary(Compress_elf_header header) {
  uint64_t segnum = header->segnum;
  Elf_binary segment = (Elf_binary)header->elf_binary;
  for (int i = 0; i < segnum; i++) {
    uint64_t target_addr = segment->target_addr;
    uint64_t binary_len = segment->binary_len;
    uint64_t iszero = segment->iszero;
    uint64_t *data = segment->inst;
    if (iszero) {
      segment = (Elf_binary)zero_set((uint64_t *)target_addr, data, binary_len);
    } else {
      segment = (Elf_binary)binary_cpy((uint64_t *)target_addr, data, binary_len);
    }
  }
}
