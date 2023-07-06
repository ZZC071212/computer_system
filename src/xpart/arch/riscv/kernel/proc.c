//arch/riscv/kernel/proc.c

#include "printk.h"
#include "mm.h"
#include "proc.h"
#include "rand.h"
#include "defs.h"

extern void do_timer(void);
extern void schedule(void);
extern void __dummy();
extern void __switch_to(struct task_struct* prev, struct task_struct* next);
extern void set_priority();

struct task_struct* idle;           // idle process
struct task_struct* current;        // 指向当前运行线程的 `task_struct`
struct task_struct* task[NR_TASKS]; // 线程数组，所有的线程都保存在此

void task_init() {
    #ifdef DEBUG
    printk("[INIT] ...proc_init called!\n");
    #endif

    // 1. 调用 kalloc() 为 idle 分配一个物理页
    idle = (struct task_struct*)kalloc();

    // 2. 设置 state 为 TASK_RUNNING;
    idle->state = TASK_RUNNING;

    // 3. 由于 idle 不参与调度 可以将其 counter / priority 设置为 0
    idle->counter = 0;
    idle->priority = 0;

    // 4. 设置 idle 的 pid 为 0
    idle->pid = 0;
    idle->thread.sp = (uint64)idle + PGSIZE;

    // 5. 将 current 和 task[0] 指向 idle
    current = idle;
    task[0] = idle;

    // 1. 参考 idle 的设置, 为 task[1] ~ task[NR_TASKS - 1] 进行初始化
    // 2. 其中每个线程的 state 为 TASK_RUNNING, counter 为 0, priority 使用 rand() 来设置, pid 为该线程在线程数组中的下标。
    for (int i = 1; i < NR_TASKS; i++) {
        task[i] = (struct task_struct*)kalloc();
        task[i]->state = TASK_RUNNING;
        task[i]->counter = 0;
        task[i]->priority = rand();
        task[i]->pid = i;
    }

    // 3. 为 task[1] ~ task[NR_TASKS - 1] 设置 `thread_struct` 中的 `ra` 和 `sp`, 
    // 4. 其中 `ra` 设置为 __dummy （见 4.3.2）的地址， `sp` 设置为 该线程申请的物理页的高地址
    for (int i = 1; i < NR_TASKS; i++) {
        task[i]->thread.ra = (uint64)__dummy;
        task[i]->thread.sp = (uint64)task[i] + PGSIZE;
    }
    #ifdef DEBUG
    printk("[INIT] ...proc_init done!\n");
    #endif

    set_priority();

    return;
}

void dummy() {
    uint64 MOD = 1000000007;
    uint64 auto_inc_local_var = 0;
    int last_counter = -1; // 记录上一个counter
    int last_last_counter = -1; // 记录上上个counter
    while(1) {
        if (last_counter == -1 || current->counter != last_counter) {
            last_last_counter = last_counter;
            last_counter = current->counter;
            auto_inc_local_var = (auto_inc_local_var + 1) % MOD;
            #ifdef DEBUG
            printk("[PID = %d] is running. auto_inc_local_var = %d\n", current->pid, auto_inc_local_var); 
            printk("Thread space begin at %lx\n", current);
            #endif
        } else if((last_last_counter == 0 || last_last_counter == -1) && last_counter == 1) { // counter恒为1的情况
            // 这里比较 tricky，不要求理解。
            last_counter = 0; 
            current->counter = 0;
        }
        for(int i = 0;i<1000000000;i++);
        do_timer();
    }
}

// 更新当前线程的 counter，查看是否需要进行 schedule
void do_timer(void) {
    // printk ("[DEBUG] [do_timer] I am at do_timer, current->counter = %lu\n", current->counter);
    // 如果当前 counter 大于零，则减一
    if (current->counter > 0) {
        current->counter--;
    }else{
        // 如果当前 counter 小于等于零，则调用 schedule() 进行调度
        schedule();
        for (int i = 0; i < NR_TASKS; i++) {
            if (current == task[i]) {
                asm("addi gp, %0, 0x100" :: "r"(i));
            }
        }
    }
}

// 选择优先级最高的线程进行调度
void schedule(void) {
    // 遍历 task 数组，找到从1到 NR_TASKS中，优先级最高（数字最小）且 counter 大于零的线程
    uint64 min_priority = -1;
    int min_priority_index = -1;
    int all_zero = 1;
    for (int i = 1; i < NR_TASKS; i++) { // 遍历 task 数组
        if (task[i]->counter > 0 && task[i]->priority < min_priority) {
            all_zero = 0;
            min_priority = task[i]->priority;
            min_priority_index = i;
        }
    }
    // 如果所有线程的 counter 都为零，则将所有线程的 counter 重置为 priority
    if (all_zero) {
        for (int i = 1; i < NR_TASKS; i++) {
            task[i]->counter = task[i]->priority;
        }
        // 找到优先级最高的线程，打印每个进程的 pid, priority, counter
        for (int i = 1; i < NR_TASKS; i++) {
            // SET [PID = 1, PRIORITY = 1, COUNTER = 1]
            #ifdef DEBUG
            printk("[DEBUG] SET [PID = %lu, PRIORITY = %lu, COUNTER = %lu]\n", task[i]->pid, task[i]->priority, task[i]->counter);
            #endif
            if (task[i]->priority < min_priority) {
                min_priority = task[i]->priority;
                min_priority_index = i;
            }
        }
    }else{
    }
    switch_to(task[min_priority_index]);
}

// 切换到 next 线程
void switch_to(struct task_struct* next) {
    #ifdef DEBUG
    printk("[DEBUG] switch to [PID = %lu, PRIORITY = %lu, COUNTER = %lu]\n", next->pid, next->priority, next->counter);
    #endif
    //判断下一个执行的线程 next 与当前的线程 current 是否为同一个线程，如果是同一个线程，则无需做任何处理，
    //否则调用 __switch_to 进行线程上下文的切换。
    if (current->pid != next->pid) {
        //copy
        struct task_struct* temp = current;
        current = next;
        __switch_to(temp, next);
    }
    return;
}

void set_priority() {
    task[1]->priority = 1;
    task[2]->priority = 4;
    task[3]->priority = 5;
    #ifdef DEBUG
    printk("[INIT] ...set_priority done!\n");
    #endif
}