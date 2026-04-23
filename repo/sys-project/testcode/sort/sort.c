#define N 20
#define DISP     0x10000000
typedef unsigned long long uint64;

int a[N] = {2, 12, 14, 6, 13, 15, 16, 10, 0, 18, 11, 19, 9, 1, 7, 5, 4, 3, 8, 17};
int b[N] = {7, 3, 0, 13, 2, 6, 5, 9, 10, 4, 18, 11, 14, 16, 1, 17, 19, 15, 8, 12};

void bubble_sort(int a[]) {
    int i, j, t;
    for(j = 0; j < N; j ++) {
        for(i = 0; i < N - 1 - j; i ++) {
            if(a[i] > a[i + 1]) {
                t = a[i];
                a[i] = a[i + 1];
                a[i + 1] = t;
            }
        }
    }
}

void select_sort(int a[]) {
    int i, j, k, t;
    for(i = 0; i < N - 1; i ++) {
        k = i;
        for(j = i + 1; j < N; j ++) {
            if(a[j] > a[k]) {
                k = j;
            }
        }

        t = a[i];
        a[i] = a[k];
        a[k] = t;
    }
}

void _sbi_console_putchar(uint64 c){
    volatile uint64* disp_addr=(uint64*)DISP;
    while(*(disp_addr));
    *(disp_addr)=c;
}

void _putch(char c) {
    _sbi_console_putchar(c);
}

void _puts(char *s) {
    while (*s) {
        _putch(*s);
        s++;
    }
}

void _puti(int n) {
    char s[20];
    int i = 0;
    if (n == 0) {
        _putch('0');
        return;
    }
    while (n > 0) {
        s[i] = n % 10 + '0';
        n = n / 10;
        i++;
    }
    for (i = i - 1; i >= 0; i--) {
        _putch(s[i]);
    }
}

void display(int a[]) {
    int i;
    for (i = 0; i < N; i++) {
        _puti(a[i]);
        _puts(" ");
    }
    _puts("\n");
}

void check(int b) {
    if (!b) {
        _puts("[-] sort test failed!\n");
        asm("unimp");
    }
}

int main() {
    display(a);
    bubble_sort(a);
    display(a);

    int i;
    for(i = 0; i < N; i++) {
        check(a[i] == i);
    }

    check(i == N);

    display(b);
    select_sort(b);
    display(b);

    for(i = 0; i < N; i++) {
        check(b[i] == N - i - 1);
    }

    check(i == N);

    _puts("[+] sort test succeed!\n");
    asm("unimp");

    return 0;
}