#include <string.h>

void *memset(void *restrict dst, int c, size_t n) {
unsigned char *p = (unsigned char *)dst;
unsigned char uc = (unsigned char)c;

for(size_t i=0;i<n;i++){
    p[i] = uc;
}
return dst;
}

size_t strnlen(const char *restrict s, size_t maxlen) {
size_t len = 0;

while(len<maxlen&&s[len]!='\0'){
    len++;
}
return len;
}
