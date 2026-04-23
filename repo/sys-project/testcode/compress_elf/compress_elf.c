#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <stdint.h>
#include "elf.h"

#define write_hex(fp, data) fprintf((fp), "%016lx\n", (uint64_t)(data))
#define write_bin(fp, data) fwrite(&(data), 8, 1, (fp))
#define write_both(fp_hex, fp_bin, data) \
  write_hex(fp_hex, data);               \
  write_bin(fp_bin, data)
int main(int argc, char *argv[]) {
  if (argc < 4) {
    printf("compress_elf:the param num is too small, we need 3 param:\n");
    printf("input.elf output.hex output.bin\n");
    exit(-1);
  }
  char *input_elf_name = argv[1];
  char *output_hex_name = argv[2];
  char *output_bin_name = argv[3];
  FILE *input_elf = fopen(input_elf_name, "rb");
  FILE *output_hex = fopen(output_hex_name, "wt");
  FILE *output_bin = fopen(output_bin_name, "wb");
  Elf64_Ehdr elf_header;
  fread(&elf_header, sizeof(Elf64_Ehdr), 1, input_elf);
  fseek(input_elf, elf_header.e_shoff, SEEK_SET);

  assert(sizeof(Elf64_Shdr) == elf_header.e_shentsize);
  Elf64_Shdr *shdr = (Elf64_Shdr *)malloc(sizeof(Elf64_Shdr) * elf_header.e_shnum);
  fread(shdr, sizeof(Elf64_Shdr), elf_header.e_shnum, input_elf);
  uint64_t segnum = 0;
  for (int i = 0; i < elf_header.e_shnum; i++) {
    switch (shdr[i].sh_type) {
      case SHT_NULL:
        continue;
      case SHT_PROGBITS:
        segnum++;
        break;
      case SHT_NOBITS:
        segnum++;
        break;
      default:
        goto EXIT;
    }
  }
EXIT:
  write_both(output_hex, output_bin, segnum);

  for (int i = 0; i < elf_header.e_shnum; i++) {
    if (shdr[i].sh_type == SHT_NULL)
      continue;
    if (shdr[i].sh_type != SHT_PROGBITS && shdr[i].sh_type != SHT_NOBITS)
      break;

    write_both(output_hex, output_bin, shdr[i].sh_addr);
    uint64_t up_size = (shdr[i].sh_size + 8 - 1) >> 3;
    write_both(output_hex, output_bin, up_size);
    uint64_t iszero = shdr[i].sh_type == SHT_NOBITS;
    write_both(output_hex, output_bin, iszero);
    if (iszero)
      continue;

    fseek(input_elf, shdr[i].sh_offset, SEEK_SET);
    uint64_t down_size = (shdr[i].sh_size) & ~(uint64_t)0b111;
    for (size_t j = 0; j < down_size; j += 8) {
      uint64_t data;
      fread(&data, sizeof(uint64_t), 1, input_elf);
      write_both(output_hex, output_bin, data);
    }
    uint64_t remain = shdr[i].sh_size & 0b111;
    if (remain != 0) {
      unsigned char remain_data[8];
      fread(remain_data, sizeof(unsigned char), remain, input_elf);
      uint64_t data = 0;
      for (int i = remain - 1; i >= 0; i--) {
        data <<= 8;
        data += remain_data[i];
      }
      write_both(output_hex, output_bin, data);
    }
  }
  free(shdr);
  fclose(input_elf);
  fclose(output_hex);
  fclose(output_bin);
}
