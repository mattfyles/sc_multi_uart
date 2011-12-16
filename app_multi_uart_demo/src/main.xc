#include <xs1.h>
#include <platform.h>
#include <print.h>
#include "multi_uart_tx.h"
#include "multi_uart_rx.h"

s_multi_uart_tx_ports uart_tx_ports =
{    
    XS1_PORT_8A,
    XS1_PORT_1A,
    XS1_CLKBLK_1
};

s_multi_uart_rx_ports uart_rx_ports =
{    
    XS1_PORT_8B,
    XS1_PORT_1B,
    XS1_CLKBLK_2
};


void uart_tx_test(streaming chanend cUART)
{
    unsigned uart_char[8] = {0,0,0,0,0,0,0,0};
    unsigned temp = 0;
    int chan_id = 0;
    unsigned baud_rate = 100000;

    /* configure UARTs */
    for (int i = 0; i < 8; i++)
    {
        printintln(baud_rate);
       if (uart_tx_initialise_channel( i, even, sb_1, baud_rate, 8 ))
       {
           printstr("Invalid baud rate for tx channel ");
           printintln(i);
       }
       baud_rate /= 2;
       if ((int)baud_rate <= 3125)
           baud_rate = 3125;
    }
   
   while (temp != MULTI_UART_GO)
   {
       cUART :> temp;
   }
   cUART <: 1;

   while (1)
   {
               
       int buffer_space = uart_tx_put_char(chan_id, (unsigned int)uart_char[chan_id]);
       //printint(chan_id); printstr(" -> "); printhexln(uart_char[chan_id]);
       if (buffer_space < UART_TX_BUF_SIZE)
       {           
           uart_char[chan_id]++;
       }
       else chan_id++;
       chan_id &= UART_TX_CHAN_COUNT-1;
   }
}

void uart_rx_test(streaming chanend cUART)
{
    unsigned uart_char, temp;
    int buf_entries;
    unsigned baud_rate = 100000; 
    
    /* configure UARTs */
    for (int i = 0; i < 8; i++)
    {
        if (uart_rx_initialise_channel( i, even, sb_1, start_0, baud_rate, 8 ))
        {
            printstr("Invalid baud rate for rx channel ");
            printintln(i);
        }
        baud_rate /= 2;
        if ((int)baud_rate <= 3125)
            baud_rate = 3125;
    }
   
   /* wait for intialisation */
   while (temp != MULTI_UART_GO) cUART :> temp;
   cUART <: 1;
    
    /* main loop */
    while (1)
    {
        int chan_id;
        
        cUART :>  chan_id;
        cUART :> uart_char;
        
        for (int i = 0; i < chan_id; i++)
            printchar('\t');
        
        //if (chan_id == 0)
        {
            printint(chan_id); printstr(": "); printhex(uart_char); printstr(" -> ");
            uart_char >>= 2;
            uart_char &= 0xFF;
            printhexln(uart_char);
        }
        
        #if 0
        for (int i = 0; i < UART_RX_CHAN_COUNT; i++)
        {
            buf_entries = uart_rx_get_char( i, uart_char );
            if (buf_entries >= 0)
            {
                //printint(i); printstr(": "); printhex(uart_char); printstr(" -> ");
                uart_char >>= 1;
                uart_char &= 0xFF;
                //printcharln(uart_char);
            }
        }
        #endif
    }
}

void dummy()
{
    while (1);
}

/**
 * Top level main for multi-UART demonstration
 */
int main(void)
{
    streaming chan cTxUART;
    streaming chan cRxUART;
    
    par
    {
        //dummy();
        //dummy();
        dummy();
        dummy();
        
        /* TX Stuff */
        uart_tx_test(cTxUART);
        run_multi_uart_tx( cTxUART, uart_tx_ports );
        
        /* RX stuff */
        #if 1
        uart_rx_test(cRxUART);
        run_multi_uart_rx( cRxUART, uart_rx_ports );
        #else
        dummy();
        dummy();
        #endif
    }
    return 0;
}
