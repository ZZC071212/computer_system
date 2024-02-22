#ifndef _MM_H
#define _MM_H

#include "types.h"

struct run {
    struct run *next;
};

void mm_init();

uint64 kalloc();
void kfree(uint64);

struct buddy {
  uint64 size;
  uint64 *bitmap; 
};

void buddy_init();
uint64  buddy_alloc(uint64);
void buddy_free(uint64);

uint64 alloc_pages(uint64);
uint64 alloc_page();
void free_pages(uint64);

#endif
