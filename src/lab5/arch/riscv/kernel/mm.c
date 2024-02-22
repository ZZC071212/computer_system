#include "defs.h"
#include "string.h"
#include "mm.h"
#include "printk.h"

extern char _ekernel[];

#define VA2PA(x) ((x - (uint64)PA2VA_OFFSET))
#define PA2VA(x) ((x + (uint64)PA2VA_OFFSET))
#define PFN2PHYS(x) (((uint64)(x) << 12) + PHY_START)
#define PHYS2PFN(x) ((((uint64)(x) - PHY_START) >> 12))

struct {
    struct run *freelist;
} kmem;

// fine, write buddy system here

#define LEFT_LEAF(index) ((index) * 2 + 1)
#define RIGHT_LEAF(index) ((index) * 2 + 2)
#define PARENT(index) ( ((index) + 1) / 2 - 1)

#define IS_POWER_OF_2(x) (!((x)&((x)-1)))

#define MAX(a, b) ((a) > (b) ? (a) : (b))

extern char _ekernel[];
void *free_page_start = &_ekernel;
struct buddy buddy;

static uint64 fixsize(uint64 size) {
    size --;
    size |= size >> 1;
    size |= size >> 2;
    size |= size >> 4;
    size |= size >> 8;
    size |= size >> 16;
    size |= size >> 32;
    return size + 1;
}

void buddy_init() {
    uint64 buddy_size = (uint64)PHY_SIZE / PGSIZE;

    if (!IS_POWER_OF_2(buddy_size))
        buddy_size = fixsize(buddy_size);

    buddy.size = buddy_size;
    buddy.bitmap = free_page_start;
    free_page_start += 2 * buddy.size * sizeof(*buddy.bitmap);
    memset(buddy.bitmap, 0, 2 * buddy.size * sizeof(*buddy.bitmap));
    // alloc space for ref_cnt
    buddy.ref_cnt = free_page_start;
    free_page_start += buddy.size * sizeof(*buddy.ref_cnt);
    memset(buddy.ref_cnt, 0, buddy.size * sizeof(*buddy.ref_cnt));

    uint64 node_size = buddy.size * 2;
    for (uint64 i = 0; i < 2 * buddy.size - 1; ++i) {
        if (IS_POWER_OF_2(i + 1))
            node_size /= 2;
        buddy.bitmap[i] = node_size;
    }

    for (uint64 pfn = 0; (uint64)PFN2PHYS(pfn) < VA2PA((uint64)free_page_start); pfn++) {
        buddy_alloc(1);
    }

    printk("...buddy_init done!\n");
    return;
}

void page_ref_inc(uint64 pfn) {
    buddy.ref_cnt[pfn]++;
}

void page_ref_dec(uint64 pfn) {
    if (buddy.ref_cnt[pfn] > 0) {
        buddy.ref_cnt[pfn]--;
    }
    if (buddy.ref_cnt[pfn] == 0) {
        buddy_free(pfn);
    }
}

void buddy_free(uint64 pfn)
{
    // if ref_cnt is not zero, do nothing
    if (buddy.ref_cnt[pfn]) {
        return;
    }

    uint64 node_size, index = 0;
    uint64 left_longest, right_longest;

    node_size = 1;
    index = pfn + buddy.size - 1;

    for (; buddy.bitmap[index] ; index = PARENT(index)) {
    node_size *= 2;
    if (index == 0)
        break;
    }

    buddy.bitmap[index] = node_size;

    while (index) {
    index = PARENT(index);
    node_size *= 2;

    left_longest = buddy.bitmap[LEFT_LEAF(index)];
    right_longest = buddy.bitmap[RIGHT_LEAF(index)];

    if (left_longest + right_longest == node_size) 
        buddy.bitmap[index] = node_size;
    else
        buddy.bitmap[index] = MAX(left_longest, right_longest);
    }
}

uint64 buddy_alloc(uint64 nrpages) {

    uint64 index = 0;
    uint64 node_size;
    uint64 pfn = 0;

    if (nrpages <= 0)
        nrpages = 1;
    else if (!IS_POWER_OF_2(nrpages))
        nrpages = fixsize(nrpages);

    if (buddy.bitmap[index] < nrpages)
        return 0;

    for(node_size = buddy.size; node_size != nrpages; node_size /= 2 ) {
        if (buddy.bitmap[LEFT_LEAF(index)] >= nrpages)
            index = LEFT_LEAF(index);
        else
            index = RIGHT_LEAF(index);
    }

    buddy.bitmap[index] = 0;
    pfn = (index + 1) * node_size - buddy.size;
    // set ref_cnt to 1
    buddy.ref_cnt[pfn] = 1;

    while (index) {
        index = PARENT(index);
        buddy.bitmap[index] = 
            MAX(buddy.bitmap[LEFT_LEAF(index)], buddy.bitmap[RIGHT_LEAF(index)]);
    }
    
    return pfn;
}


uint64 alloc_pages(uint64 nrpages){
    uint64 pfn = buddy_alloc(nrpages);
    if (pfn == 0)
        return 0;
    return (PA2VA(PFN2PHYS(pfn)));
}

uint64 alloc_page(){
    uint64 pfn = buddy_alloc(1);
    if (pfn == 0)
        return 0;
    return (PA2VA(PFN2PHYS(pfn)));
}

void free_pages(uint64 va){
    buddy_free(PHYS2PFN(VA2PA(va)));
}

void mm_init(void) {
    buddy_init();
}

uint64 kalloc() {
    return alloc_page();
}

void kfree(uint64 addr) {
    free_pages(addr);
}

uint64 get_page(uint64 va) {
    uint64 pfn = PHYS2PFN(VA2PA(va));
    // check if the page is already allocated
    if (buddy.ref_cnt[pfn] == 0) {
        return 1;
    }
    page_ref_inc(pfn);
    return 0;
}

void put_page(uint64 va) {
    uint64 pfn = PHYS2PFN(VA2PA(va));
    page_ref_dec(pfn);
}
