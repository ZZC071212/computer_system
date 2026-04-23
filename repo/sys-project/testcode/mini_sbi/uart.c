// /*
//  * SPDX-License-Identifier: BSD-2-Clause
//  *
//  * Copyright (c) 2019 Western Digital Corporation or its affiliates.
//  *
//  * Authors:
//  *   Anup Patel <anup.patel@wdc.com>
//  */

#include "uart.h"
#include "mcsr.h"

#define UART_BASE ((volatile uint8_t *)DISP)
#define UART_DATA_OFFSET 0
#define UART_STATE_OFFSET 1
#define TX_MASK 0b10
#define RX_MASK 0b01

char uart_rx(void) {
  while (!(UART_BASE[UART_STATE_OFFSET] & RX_MASK))
    ;
  return UART_BASE[UART_DATA_OFFSET];
}

void uart_tx(uint8_t c) {
  while (!(UART_BASE[UART_STATE_OFFSET] & TX_MASK))
    ;
  UART_BASE[UART_DATA_OFFSET] = c;
}
