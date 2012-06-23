#include <stdlib.h>
#include "s2e_conf.h"
#include "s2e_def.h"
#include "s2e_validation.h"
#include "multi_uart_tx_conf.h"
#include "telnet_config.h"
#include "web_server.h"
#include "telnet_to_uart.h"

char s2e_validation_bad_parity_msg[] = "Invalid parity setting.";
char s2e_validation_bad_polarity_msg[] = "Invalid polarity setting.";
char s2e_validation_bad_baudrate_msg[] = "Invalid baud rate setting.";
char s2e_validation_bad_stop_bits_msg[] = "Invalid stop bits setting.";
char s2e_validation_bad_char_len_msg[] = "Invalid char length setting.";
char s2e_validation_bad_telnet_port_msg[] = "Invalid telnet port setting.";
char s2e_validation_bad_channel_id[] = "Invalid uart id.";



char *s2e_validate_channel_id(int channel_id)
{
  if (channel_id < 0 || channel_id > NUM_UART_CHANNELS)
    return s2e_validation_bad_channel_id;

  return NULL;
}

char *s2e_validate_uart_config(uart_config_data_t *config)
{
  char *err;
  err = s2e_validate_channel_id(config->channel_id);
  if (err)
    return err;

  if (config->parity <0 || config->parity > 4)
    return s2e_validation_bad_parity_msg;

  if (config->stop_bits<0 || config->stop_bits > 1)
    return s2e_validation_bad_stop_bits_msg;

  if (config->polarity<0 || config->polarity > 1)
    return s2e_validation_bad_polarity_msg;

  if (config->baud < 150 || config->baud > UART_TX_MAX_BAUD_RATE)
    return s2e_validation_bad_baudrate_msg;

  if (config->char_len < 5 || config->char_len > 9)
    return s2e_validation_bad_char_len_msg;

  return NULL;
}

#define MAX_PORT ((1<<16)-1)

char *s2e_validate_telnet_port(int id, int p)
{
  if (p < 0 ||
      p > MAX_PORT ||
      p == S2E_TELNET_CONFIG_PORT ||
      p == WEB_SERVER_PORT ||
      telnet_to_uart_port_used_elsewhere(id, p))
    return s2e_validation_bad_telnet_port_msg;

  return NULL;
}
