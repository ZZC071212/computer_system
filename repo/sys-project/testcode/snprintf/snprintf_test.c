#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define CLOCKS_PER_SEC 1000000

#define RED "\e[31m"
#define REDH "\e[1;41m"
#define GREEN "\e[32m"
#define GREENH "\e[1;32m"
#define YELLOWH "\e[1;33m"
#define RESET "\e[0m"

#define STR0(x) #x
#define STR(x) STR0(x)

#define PASSFAIL(x, desc)                                                             \
  do {                                                                                \
    int _x = !!(x);                                                                   \
    const char *msg = _x ? GREENH "PASS" RESET GREEN : REDH "FAIL" RESET RED;         \
    printk("%s Test " STR(__COUNTER__) "/%d: %s" RESET "\n", msg, TOTAL_TESTS, desc); \
    passed_tests += _x;                                                               \
  } while (0)

typedef long clock_t;

static const int TOTAL_TESTS;
static int passed_tests;

struct sbiret {
  long error;
  long value;
};

struct sbiret sbi_ecall(uint64_t eid, uint64_t fid, uint64_t arg0, uint64_t arg1, uint64_t arg2, uint64_t arg3,
                        uint64_t arg4, uint64_t arg5);

void printk(const char *fmt, ...);

static clock_t clock(void) {
  uint64_t time;
  asm volatile("rdtime %0" : "=r"(time));
  return time / 10;
}

_Noreturn static void shutdown(void) {
  sbi_ecall(0x53525354, 0, 0, 0, 0, 0, 0, 0);
  __builtin_unreachable();
}

_Noreturn void self_destruct(void) {
  printk(REDH "TRAP" RESET " You might have a memory error!\n");
  shutdown();
}

static struct sbiret sbi_hart_start(unsigned long hartid, unsigned long start_addr, unsigned long opaque) {
  return sbi_ecall(0x48534d, 0, hartid, start_addr, opaque, 0, 0, 0);
}

static struct sbiret sbi_hart_stop(void) {
  return sbi_ecall(0x48534d, 1, 0, 0, 0, 0, 0, 0);
}

static struct sbiret sbi_hart_get_status(unsigned long hartid) {
  return sbi_ecall(0x48534d, 2, hartid, 0, 0, 0, 0, 0);
}

static struct sbiret sbi_set_timer(uint64_t stime_value) {
  return sbi_ecall(0x54494d45, 0, stime_value, 0, 0, 0, 0, 0);
}

static int strcmp_check(void) {
  return strcmp("xyz", "xyz") == 0 && strcmp("xyz", "xy") > 0 && strcmp("xy", "xyz") < 0 && strcmp("xyz", "xzz") < 0
         && strcmp("xzz", "xyz") > 0 && strcmp("x", "xyz") < 0 && strcmp("xyz", "x") > 0 && strcmp("", "xyz") < 0
         && strcmp("xyz", "") > 0 && strcmp("", "") == 0;
}

static int large_reordering(char *buf, char *fmt, char *gold, char ch, size_t len) {
  for (size_t i = 0; i < ((len - 1) / 4); i++) {
    fmt[4 * i] = '%';
    fmt[4 * i + 1] = '8' - (i % 8);
    fmt[4 * i + 2] = '$';
    fmt[4 * i + 3] = 'c';
    gold[i] = ch - 7 + (i % 8);
  }
  fmt[len - 1] = 0;
  gold[(len - 1) / 4] = 0;

  return sprintf(buf, fmt, ch, ch - 1, ch - 2, ch - 3, ch - 4, ch - 5, ch - 6, ch - 7) == (int)((len - 1) / 4)
         && !strcmp(buf, gold);
}

static _Atomic volatile int mt_lockharts = 1;
static _Atomic volatile int mt_total;
static _Atomic volatile int mt_pass;

static volatile clock_t duration;
static volatile int reorder_testing;
static volatile int traps_when_reordering;
static volatile int traps_reordering_pass = -1;

static void traps(void) __attribute__((interrupt("supervisor")));
static void traps(void) {
  if (reorder_testing) {
    traps_when_reordering = 1;

    printk("[" GREENH "+" RESET "]");
    if (traps_reordering_pass == -1) {
      traps_reordering_pass = 1;
    }

    char buf[0x8001];
    char fmt[0x8001];
    char gold[0x8001];

    traps_reordering_pass &= large_reordering(buf, fmt, gold, 0x61, sizeof(fmt));
  } else {
    printk("[" YELLOWH "-" RESET "]");
  }
  sbi_set_timer((uint64_t)-1);
  traps_when_reordering = 0;
}

void _start();

_Noreturn void main(void) {
  (void)__COUNTER__;
  char buf[0x8001];
  char fmt[0x8001];
  char gold[0x8001];
  long n = -1;

  if (!strcmp_check()) {
    printk(REDH "[-]" RESET " " RED "strcmp not working!" RESET "\n");
    shutdown();
  }

  PASSFAIL(sprintf(buf, "sanity%ln check", &n) == 12 && !strcmp(buf, "sanity check") && n == 6, "sanity check");

  PASSFAIL(sprintf(buf, "%n%i%c%lu=%lld %s %hd-%hhu=%u", (int *)&n, 1, '+', 2UL, 3LL, ", ", 4, 5, (unsigned)-1) == 23
               && !strcmp(buf, "1+2=3 ,  4-5=4294967295") && n == 0,
           "basic format specifiers 1");

  PASSFAIL(sprintf(buf, "%x %X %o %p %n%s %c ", 0xabc, 0xabc, 0644, (const void *)0xdeadbeef, (int *)&n, "test", '!')
                   == 30
               && !strcmp(buf, "abc ABC 644 0xdeadbeef test ! ") && n == 23,
           "basic format specifiers 2");

  PASSFAIL(sprintf(buf, "%-5sz%3sz%.2sz%*.*sz%5uz%05dz%-5uz%+5dz% dz%*dz%-*xz%.*dz%-*.*d", "abcd", "abcd", "abcd", 5, 2,
                   "abcd", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 4, 3, 2)
                   == 78
               && !strcmp(buf, "abcd zabcdzabz   abz    1z00002z3    z   +4z 5z     7z9       z0000000011z002 "),
           "width, precision and flags 1");

  PASSFAIL(sprintf(buf, "%.dy%.*dy%.0iy%.oy%.*oy%.0oy%#oy%#.0oy%.Xy%.0xy%#Xy%#.0xy%#xy%.uy%.0uy%%d", 0, 0, 0, 0, 0, 0,
                   0, 0, 0755, 0, 0, 0, 0xabc, 0, 0, 0, 0)
                   == 28
               && !strcmp(buf, "yyyyyy0755y0yyy0XABCyy0yyy%d"),
           "width, precision and flags 2");

  PASSFAIL(snprintf(0, 0, "%d%ln", 0x12345678, &n) == 9 && n == 9, "null buffer");

  PASSFAIL(snprintf(buf, 4, "%d%ln", 0xabcd, &n) == 5 && n == 5 && !strcmp(buf, "439"), "truncation 1");

  PASSFAIL(snprintf(buf, 1, "%d%ln", 0x123, &n) == 3 && n == 3 && !strcmp(buf, ""), "truncation 2");

  memset(fmt, 'A', sizeof(fmt) - 1);
  fmt[sizeof(fmt) - 1] = 0;
  PASSFAIL(sprintf(buf, fmt) == sizeof(fmt) - 1 && !strcmp(buf, fmt), "large format string");

  PASSFAIL(sprintf(buf, "%2$d %1$d", 1, 2) == 3 && !strcmp(buf, "2 1"), "reordering 1");

  PASSFAIL(sprintf(buf, "%9$d %8$d %7$d %6$d %5$d %4$d %3$d %2$d %1$d", 1, 2, 3, 4, 5, 6, 7, 8, 9) == 17
               && !strcmp(buf, "9 8 7 6 5 4 3 2 1"),
           "reordering 2");

  PASSFAIL(sprintf(buf, "%2$d %2$d %2$d %2$d %2$d %2$d %1$d", 1, 2) == 13 && !strcmp(buf, "2 2 2 2 2 2 1"),
           "reordering 3");

  PASSFAIL(large_reordering(buf, fmt, gold, 0x41, sizeof(fmt)), "large reordering");

  int harts = 0;
  for (size_t i = 0; i < 16; i++) {
    struct sbiret ret = sbi_hart_get_status(i);
    if (ret.error == 0 && ret.value == 1) {
      sbi_hart_start(i, (unsigned long)_start, 0);
      harts++;
    }
  }

  while (mt_total < harts)
    ;

  mt_total = 0;
  asm volatile("fence" ::: "memory");
  mt_lockharts = 0;

  while (mt_total < harts)
    ;

  mt_lockharts = 1;
  PASSFAIL(mt_pass == mt_total, "thread-safety");

  duration = clock();
  for (int i = 0; i < 8; i++) {
    large_reordering(buf, fmt, gold, 70 ^ i, sizeof(fmt));
  }
  duration = (clock() - duration) / 8;

  for (int i = 2; i <= 23; i++) {
    asm volatile("csrw stvec, %0\n"
                 "csrs sie, %1\n"
                 "csrsi sstatus, %2\n" ::"r"(traps),
                 "r"(0x20), "i"(2));
    sbi_set_timer(10 * (clock() + (i / 2) * (duration / 10)));

    reorder_testing = 1;
    traps_reordering_pass &= large_reordering(buf, fmt, gold, 79 ^ i, sizeof(fmt));
    reorder_testing = 0;

    sbi_set_timer((uint64_t)-1);
    asm volatile("csrci sstatus, %2\n"
                 "csrc sie, %1\n"
                 "csrw stvec, %0\n" ::"r"(self_destruct),
                 "r"(0x20), "i"(2));

    if (traps_reordering_pass == 0) {
      printk(RED "[-]" RESET);
      break;
    }
  }
  printk("\n");
  PASSFAIL(traps_reordering_pass == 1, "reentrancy");
  if (traps_reordering_pass == -1) {
    printk(YELLOWH "=== READ THIS ==="
                   "\nYou are seeing this message because the reentrancy test wasn't run properly on your plaform.\n"
                   "Please zip your code and send to: " GREENH "45gfg9@zju.edu.cn" YELLOWH "\n=================" RESET
                   "\n");
  }

  printk(YELLOWH "Tests passed: %s%d/%d" RESET "\n", passed_tests == TOTAL_TESTS ? GREEN : RED, passed_tests,
         TOTAL_TESTS);
  shutdown();
}

_Noreturn void mt_test(unsigned long hartid, unsigned long opaque) {
  (void)opaque;
  char buf[0x8001];
  char fmt[0x8001];
  char gold[0x8001];

  mt_total++;
  while (mt_lockharts)
    ;

  char ch = 126 - 2 * hartid;

  mt_pass += large_reordering(buf, fmt, gold, ch, sizeof(fmt));
  mt_total++;

  // give harts enough time to propagate the result
  do
    asm volatile("fence" ::: "memory");
  while (!mt_lockharts);

  while (1) {
    sbi_hart_stop();
  }
}

static const int TOTAL_TESTS = __COUNTER__ - 1;
