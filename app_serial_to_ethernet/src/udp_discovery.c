#include <stdlib.h>
#include <string.h>
#include "udp_discovery.h"
#include "xtcp_client.h"
#include "xtcp_client_conf.h"
#include "itoa.h"

typedef enum
{
    UDP_CONFIG_CMD_IP_RESPOND = 1,
    UDP_CONFIG_CMD_IP_CHANGE = 2,
} udp_config_cmd_t;

typedef enum
{
    PARSING_START,
    PARSING_COMMON,
    PARSING_IP_PART,
    STORING_IP_PART,
    PARSING_TERM
} udp_config_parsing_state_t;

typedef enum
{
    REPLY_START,
    FRAME_COMMON_PART,
    FRAME_S2E_VERSION,
    FRAME_MAC_VERSION,
    FRAME_IP_VERSION,
    REPLY_TERM
} udp_disc_reply_state_t;

typedef struct connection_state_t
{
    int conn_id;
    int active;
    udp_config_cmd_t cmd;
    udp_config_parsing_state_t config_parsing_state;
    udp_disc_reply_state_t reply_state;
    int send_resp;
    int resp_conn;
    char *err;
} connection_state_t;

static connection_state_t udp_config_states[UIP_CONF_UDP_CONNS];
static char buf[UDP_RECV_BUF_SIZE + 1];

//UDP Response Format :: "XMOS S2E VER:a.b.c;MAC:xx:xx:xx:xx:xx:xx;IP:xxx.xxx.xxx.xxx";
static char *g_FirmwareVer = S2E_FIRMWARE_VER;
static char *g_UdpQueryString = UDP_QUERY_S2E_IP;
static char *g_UdpCmdIpChange = UDP_CMD_IP_CHANGE;

static char *g_RespString = "XMOS S2E VER:;MAC%;IP@";
static char invalid_ip_config[] = "Invalid IP config";
static char invalid_udp_request[] = "Invalid UDP Server request";

xtcp_ipconfig_t g_ipconfig;
unsigned char g_mac_addr[6];

static connection_state_t *get_new_state()
{
    for (int i = 0; i < UIP_CONF_UDP_CONNS; i++)
    {
        if (!udp_config_states[i].active)
        {
            udp_config_states[i].active = 1;
            return &udp_config_states[i];
        }
    }
    return NULL;
}

static connection_state_t *get_state_from_connection(xtcp_connection_t *conn)
{
    for (int i = 0; i < UIP_CONF_UDP_CONNS; i++)
    {
        if (udp_config_states[i].active && udp_config_states[i].conn_id == conn->id)
        {
            return &udp_config_states[i];
        }
    }
    return NULL;
}

static void xtcp_init_send_on_udp_response_port(chanend c_xtcp)
{
    xtcp_connection_t conn;

    for (int i = 0; i < UIP_CONF_UDP_CONNS; i++)
    {
        if (udp_config_states[i].active && udp_config_states[i].resp_conn == 1)
        {
            conn.id = udp_config_states[i].conn_id;
            xtcp_init_send(c_xtcp, &conn);
            return;
        }
    }
}

static void reset_connection_state(connection_state_t *st)
{
    st->config_parsing_state = PARSING_START;
    st->reply_state = REPLY_START;
}

static void parse_udp_buffer(chanend c_xtcp,
                             xtcp_connection_t *conn,
                             char *buf,
                             int len,
                             connection_state_t *st)
{
    int j = 0;
    int k = 0;
    unsigned char ip_cfg_char_recd[4];
    xtcp_ipconfig_t ipconfig_to_flash;
    char *end = buf + len;

    for (int i = 0; i < 2; i++)
    {
        if (!g_ipconfig.ipaddr[i])
        {
            st->err = invalid_ip_config;
            xtcp_init_send_on_udp_response_port(c_xtcp);
            reset_connection_state(st);
            return;
        }
    }

    while (buf < end)
    {
        switch (st->config_parsing_state)
        {
            case PARSING_START:
                st->config_parsing_state = PARSING_COMMON;
                break;
            case PARSING_COMMON:
                if ((*g_UdpQueryString == *buf) && (*g_UdpCmdIpChange == *g_UdpQueryString))
                {
                    buf++;
                    g_UdpQueryString++;
                    g_UdpCmdIpChange++;
                }
                else if (*g_UdpQueryString == *buf)
                {
                    buf++;
                    g_UdpQueryString++;

                    if ('\0' == *g_UdpQueryString)
                    {
                        st->config_parsing_state = PARSING_TERM;
                        st->cmd = UDP_CONFIG_CMD_IP_RESPOND;
                    }
                }
                else if (*g_UdpCmdIpChange == *buf)
                {
                    buf++;
                    g_UdpCmdIpChange++;

                    if ('\0' == *g_UdpCmdIpChange)
                        st->config_parsing_state = PARSING_IP_PART;
                }
                else
                {
                    st->err = invalid_udp_request;
                    xtcp_init_send_on_udp_response_port(c_xtcp);
                    reset_connection_state(st);
                }
                break;
            case PARSING_IP_PART:
                if (('.' != *buf) && (j < 3))
                {
                    ip_cfg_char_recd[j] = *buf;
                    j++;
                    buf++;
                }
                else if (('.' == *buf) && (j < 3))
                {
                    buf++;
                    ip_cfg_char_recd[j] = '\0';
                    st->config_parsing_state = STORING_IP_PART;
                }
                else if (j >= 3)
                {
                    st->err = invalid_ip_config;
                    xtcp_init_send_on_udp_response_port(c_xtcp);
                    reset_connection_state(st);
                }
                break;
            case STORING_IP_PART:
                ipconfig_to_flash.ipaddr[k] = (unsigned char) atoi(ip_cfg_char_recd);
                j = 0;
                k++;

                if (4 == k)
                {
                    st->cmd = UDP_CONFIG_CMD_IP_CHANGE;
                    st->config_parsing_state = PARSING_TERM;
                }
                else
                    st->config_parsing_state = PARSING_IP_PART;

                break;
            case PARSING_TERM:
                break;
        }
    }

    if (st->cmd == UDP_CONFIG_CMD_IP_RESPOND)
    {
        st->send_resp = 1;
        if (st->resp_conn)
        {
            xtcp_init_send_on_udp_response_port(c_xtcp);
        }
    }
    else if (st->cmd == UDP_CONFIG_CMD_IP_CHANGE)
    {
        for (k = 0; k < 4; k++)
        {
            g_ipconfig.ipaddr[k] = ipconfig_to_flash.ipaddr[k];
        }
        //Call chip reset function
    }
}

static int construct_udp_response(chanend c_xtcp,
                                  xtcp_connection_t *conn,
                                  char *buf,
                                  connection_state_t *st)
{
    int i = 0;
    int len = 0;

    while (1)
    {
        switch (st->reply_state)
        {
            case REPLY_START:
                st->reply_state = FRAME_COMMON_PART;
                break;
            case FRAME_COMMON_PART:
                *buf = *g_RespString;
                buf++;
                g_RespString++;
                i = 0;

                if (':' == *g_RespString)
                {
                    *buf = *g_RespString;
                    buf++;
                    st->reply_state = FRAME_S2E_VERSION;
                }
                else if ('%' == *g_RespString)
                {
                    *buf = ':';
                    buf++;
                    st->reply_state = FRAME_MAC_VERSION;
                }
                else if ('@' == *g_RespString)
                {
                    *buf = ':';
                    buf++;
                    st->reply_state = FRAME_IP_VERSION;
                }
                break;
            case FRAME_S2E_VERSION:
                *buf = *g_FirmwareVer;
                buf++;
                g_FirmwareVer++;

                if ('\0' == *g_FirmwareVer)
                {
                    st->reply_state = FRAME_COMMON_PART;
                }
                break;
            case FRAME_MAC_VERSION:
                len = itoa((int) g_mac_addr[i], buf, 10, 0);
                i++;
                buf += len;

                if (i < 6)
                {
                    *buf = ':';
                    buf++;
                }
                else
                {
                    st->reply_state = FRAME_COMMON_PART;
                }
                break;
            case FRAME_IP_VERSION:
                len = itoa((int) g_ipconfig.ipaddr[i], buf, 10, 0);
                i++;
                buf += len;

                if (i < 4)
                {
                    *buf = '.';
                    buf++;
                }
                else
                {
                    buf++;
                    *buf = '\0';
                    st->reply_state = REPLY_TERM;
                }
                break;
            case REPLY_TERM:
                reset_connection_state(st);
                return strlen(buf);
                break;
        }
    }
    return strlen(buf);
}

void udp_discovery_init(chanend c_xtcp)
{
    for (int i = 0; i < UIP_CONF_UDP_CONNS; i++)
    {
        udp_config_states[i].active = 0;
        udp_config_states[i].conn_id = -1;
    }

    // Listen on the configured UDP port
    xtcp_listen(c_xtcp, INCOMING_UDP_PORT, XTCP_PROTOCOL_UDP);

}

void udp_discovery_event_handler(chanend c_xtcp,
                                 chanend c_uart_config,
                                 xtcp_connection_t *conn)
{
    int len;
    switch (conn->event)
    {
        case XTCP_IFUP:
            xtcp_get_ipconfig(c_xtcp, &g_ipconfig);
            xtcp_get_mac_address(c_xtcp, g_mac_addr);
        case XTCP_IFDOWN:
        case XTCP_ALREADY_HANDLED:
            return;
        default:
            break;
    }

    if ((INCOMING_UDP_PORT == conn->local_port) ||
        (OUTGOING_UDP_PORT == conn->local_port) ||
        (OUTGOING_UDP_PORT == conn->remote_port))
    {
        connection_state_t *st = get_state_from_connection(conn);

        switch (conn->event)
        {
            case XTCP_NEW_CONNECTION:
                st = get_new_state();
                if (!st)
                {
                    xtcp_abort(c_xtcp, conn);
                    break;
                }
                st->conn_id = conn->id;
                reset_connection_state(st);

                if (INCOMING_UDP_PORT == conn->local_port)
                {
                    /* Establish broadcast response connection */
                    xtcp_connect(c_xtcp,
                                 OUTGOING_UDP_PORT,
                                 conn->remote_addr,
                                 XTCP_PROTOCOL_UDP);
                }
                else if (OUTGOING_UDP_PORT == conn->remote_port)
                {
                    st->resp_conn = 1;
                    if (st->send_resp)
                    {
                        xtcp_init_send_on_udp_response_port(c_xtcp);
                    }
                }
                break;
            case XTCP_RECV_DATA:
                len = xtcp_recv(c_xtcp, buf);
                //len = xtcp_recv_count(c_xtcp, buf, UDP_RECV_BUF_SIZE);
                if (!st || !st->active)
                    break;

                parse_udp_buffer(c_xtcp, conn, buf, len, st);
                break;
            case XTCP_REQUEST_DATA:
            case XTCP_RESEND_DATA:
                if (!st || !st->active)
                    break;

                if (st->send_resp)
                {
                    int len = construct_udp_response(c_xtcp, conn, buf, st);
                    xtcp_send(c_xtcp, buf, len);
                }
                else if (st->err)
                {
                    int len = strlen(st->err);
                    strcpy(buf, st->err);
                    buf[len] = '\n';
                    xtcp_send(c_xtcp, buf, len + 1);
                }
                else
                {
                    xtcp_complete_send(c_xtcp);
                }

                break;
            case XTCP_SENT_DATA:
                xtcp_complete_send(c_xtcp);
                xtcp_close(c_xtcp, conn);
                if (st)
                {
                    st->send_resp = 0;
                    st->err = NULL;
                }
                break;
            case XTCP_CLOSED:
            case XTCP_ABORTED:
            case XTCP_TIMED_OUT:
                if (st)
                {
                    st->active = 0;
                    st->conn_id = -1;
                    st->resp_conn = 0;
                }
                break;
            default:
                break;
        }
        conn->event = XTCP_ALREADY_HANDLED;
    }
}
