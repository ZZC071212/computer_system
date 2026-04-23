#ifndef __UART_H__
#define __UART_H__

typedef unsigned char uint8_t;

char uart_rx(void);
void uart_tx(uint8_t c);

#endif
