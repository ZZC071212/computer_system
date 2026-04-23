#include <stdint.h>
#include <printk.h>
#include <proc.h>

void clock_set_next_event(void);

const uint64_t Exception_Code_Mask = 0x7FFFFFFFFFFFFFFF;
typedef enum Superviser_Interrupt {software = 1, timer = 5, external = 9} Superviser_Interrupt;

void trap_handler(uint64_t scause, uint64_t sepc) {
    // 根据 scause 判断 trap 类型
    // 如果是 Supervisor Timer Interrupt：(5)
    // - 打印输出相关信息
    // - 调用 clock_set_next_event 设置下一次时钟中断
    // 其他类型的 trap 可以直接忽略，推荐打印出来供以后调试
    (void)sepc; // Unused

    if ((scause >> 63)){ // Interrupt bit
        Superviser_Interrupt interrupt_type = scause & Exception_Code_Mask;
        switch (interrupt_type){
            case software:{
                // printk("[S] Supervisor software interrupt\n");
                break;
            }
            case timer:{
                // printk("[S] Supervisor timer interrupt\n");
                clock_set_next_event();
                do_timer();
                break;
            }
            case external:{
                // printk("[S] Supervisor external interrupt\n");
                break;
            }
            default:
                break;
        }
    }
}
