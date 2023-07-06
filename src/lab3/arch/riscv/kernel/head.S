.extern start_kernel
.extern _traps
.extern mm_init
.extern task_init

    .section .text.init
    .globl _start
_start:
    lla sp, _stack
    call setup_vm
    call relocate
    
    ...

    j start_kernel

relocate:
    # set ra = ra + PA2VA_OFFSET
    # set sp = sp + PA2VA_OFFSET (If you have set the sp before)
   
    ###################### 
    #   YOUR CODE HERE   #
    ######################

    # set satp with early_pgtbl‘s physical address
  
    ###################### 
    #   YOUR CODE HERE   #
    ######################
  
    # flush tlb
    sfence.vma zero, zero

    ret

