#include <string.h>
#include <stdint.h>

void *memset(void *restrict dst, int c, size_t n) {
    unsigned char *s = dst;
    unsigned char byte = (unsigned char)c;
    uint64_t word = byte;
    word |= word << 8;
    word |= word << 16;
    word |= word << 32;

    while (n && ((uintptr_t)s & (sizeof(uint64_t) - 1))) {
        *s++ = byte;
        n--;
    }
    uint64_t *w = (uint64_t *)s;
    while (n >= sizeof(uint64_t)) {
        *w++ = word;
        n -= sizeof(uint64_t);
    }
    s = (unsigned char *)w;
    while (n) {
        *s++ = byte;
        n--;
    }
    return dst;
}

void *memcpy(void *restrict dst, const void *restrict src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    if ((((uintptr_t)d ^ (uintptr_t)s) & (sizeof(uint64_t) - 1)) == 0) {
        while (n && ((uintptr_t)d & (sizeof(uint64_t) - 1))) {
            *d++ = *s++;
            n--;
        }
        uint64_t *dw = (uint64_t *)d;
        const uint64_t *sw = (const uint64_t *)s;
        while (n >= sizeof(uint64_t)) {
            *dw++ = *sw++;
            n -= sizeof(uint64_t);
        }
        d = (unsigned char *)dw;
        s = (const unsigned char *)sw;
    }
    while (n) {
        *d++ = *s++;
        n--;
    }
    return dst;
}

size_t strlen(const char *s) {
    size_t len = 0;
    while (s[len]) {
        len++;
    }
    return len;
}

size_t strnlen(const char *restrict s, size_t maxlen) {
    for (size_t len = 0; len < maxlen; len ++){
        if (!s[len]) return len;
    }
    return maxlen;
}
