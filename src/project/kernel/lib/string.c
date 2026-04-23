#include <string.h>

void *memset(void *restrict dst, int c, size_t n) {
    unsigned char * s = dst;
    for (size_t i = 0; i < n; i ++){
        s[i] = (unsigned char)c;
    }
    return dst;
}

size_t strnlen(const char *restrict s, size_t maxlen) {
    for (size_t len = 0; len < maxlen; len ++){
        if (!s[len]) return len;
    }
    return maxlen;
}
