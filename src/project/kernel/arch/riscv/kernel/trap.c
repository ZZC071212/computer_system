#include <stdint.h>
#include <printk.h>
#include <proc.h>

void clock_set_next_event(void);

const uint64_t Exception_Code_Mask = 0x7FFFFFFFFFFFFFFF;
typedef enum Superviser_Interrupt {software = 1, timer = 5, external = 9} Superviser_Interrupt;

void trap_handler(uint64_t scause, uint64_t sepc) {
  // 根据 scause 判断 trap 类型
  // 如果是 Supervisor Timer Interrupt：
  // - 打印输出相关信息
  // - 调用 clock_set_next_event 设置下一次时钟中断
  // 其他类型的 trap 可以直接忽略，推荐打印出来供以后调试
  //printk("[trap] scause=%lx, sepc=%lx, current pid=%ld\n", scause, sepc, current->pid);
  sepc = sepc;
  //printk("scause = %lx\n",scause);
  if(((scause>>63)&&((scause & 0x7FFFFFFFFFFFFFFF) == 5))||(scause == 5)){
//  if(scause == 5){
//    ticks++;
//    printk("[S] Supervisor Mode Timer Interrupt\n");
    //printk("[trap] timer interrupt for pid %ld\n", current->pid);
    clock_set_next_event();
    do_timer();
    return;
  }
  else{
    printk("[trap] unexpected trap! scause=%lx, sepc=%lx\n", scause, sepc);
  }
}        
