// Copyright (c) 2011, XMOS Ltd., All rights reserved
// This software is freely distributable under a derivative of the
// University of Illinois/NCSA Open Source License posted in
// LICENSE.txt and at <http://github.xcore.com/>

/*===========================================================================
Filename:
Project :
Author  :
Version :
Purpose
-----------------------------------------------------------------------------


===========================================================================*/

/*---------------------------------------------------------------------------
include files
---------------------------------------------------------------------------*/
#include "client_request.h"
#include "s2e_flash.h"
#include "common.h"
#include "debug.h"
#include <string.h>
#include <print.h>

/*---------------------------------------------------------------------------
constants
---------------------------------------------------------------------------*/
//#define CR_DEBUG 1

/*---------------------------------------------------------------------------
ports and clocks
---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
typedefs
---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
global variables
---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
static variables
---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
prototypes
---------------------------------------------------------------------------*/
static int get_marker_index(char gmi_data[],
                            int gmi_length,
                            char gmi_marker);

static void get_response_data(streaming chanend cWbSvr2AppMgr,
                              char grd_response[]);

static void send_to_channel(streaming chanend cWbSvr2AppMgr,
                            char stc_data[],
                            int stc_start,
                            int stc_end);

static void clear_char_array(char c[], int length);

static void replace_with_zero(char rwz_c[], int rwz_start, int rwz_end);

#ifndef FLASH_THREAD
static int get_flash_config_address();
#else //FLASH_THREAD
static int get_flash_config_address(chanend cPersData);
#endif //FLASH_THREAD

static void create_get_command(char cc_data[], int cc_channel);

static void create_set_command(char cc_data[], int cc_channel, int index);

static int exchange_data_with_am(streaming chanend cWbSvr2AppMgr,
                                 char data[],
                                 char response[],
                                 int start,
                                 int end);

/*---------------------------------------------------------------------------
implementation
---------------------------------------------------------------------------*/

/** =========================================================================
*  Description
*
*  \param xxx    description of xxx
*  \param yyy    description of yyy
*
**/
#pragma unsafe arrays
#ifndef FLASH_THREAD
int parse_client_request(streaming chanend cWbSvr2AppMgr,
                         char data[],
                         char response[],
                         int data_length)
#else //FLASH_THREAD
int parse_client_request(streaming chanend cWbSvr2AppMgr,
                         chanend cPersData,
                         char data[],
                         char response[],
                         int data_length)
#endif //FLASH_THREAD
{
    char rtnval;
    char done = 0;
    char command;
    int i, j, k, ix_start, ix_end, config_address;
    char flash_data[FLASH_SIZE_PAGE];

    k = 0;

    // capture first config start marker
    ix_start = get_marker_index(data, data_length, MARKER_START);

    // capture end config marker
    ix_end = get_marker_index(data, data_length, MARKER_END);

    // command is char after first marker
    command = data[ix_start + 1];

    // clear array
    clear_char_array(flash_data, FLASH_SIZE_PAGE);
    clear_char_array(response, UI_COMMAND_LENGTH);

    switch(command)
    {
        case CMD_CONFIG_GET:
        {
#ifdef CR_DEBUG
            printstrln("CR: GET request");
#endif
            // exchange data with am
            exchange_data_with_am(cWbSvr2AppMgr, data, response, ix_start, ix_end);
#ifdef CR_DEBUG
            printstrln("CR: GET request completed");
#endif
            break;
        } // case CMD_CONFIG_GET:

        case CMD_CONFIG_SET:
        {
#ifdef CR_DEBUG
            printstrln("CR: SET request");
#endif
            // exchange data with am
            exchange_data_with_am(cWbSvr2AppMgr, data, response, ix_start, ix_end);
            /* Send SET command complete */
            cWbSvr2AppMgr <: UART_SET_END_FROM_APP_TO_UART;
#ifdef CR_DEBUG
            printstrln("CR: SET request completed");
#endif
            break;
        } // case CMD_CONFIG_SET:

        case CMD_CONFIG_SAVE:
        {
#ifdef CR_DEBUG
            printstrln("CR: SAVE request");
#endif
            // get flash config address
#ifndef FLASH_THREAD
            config_address = get_flash_config_address();
#else //FLASH_THREAD
            config_address = get_flash_config_address(cPersData);
#endif //FLASH_THREAD

            // get settings for each config from app_manager
            k = 0;
            flash_data[k] = FLASH_VALID_CONFIG_PRESENT; k++;

            for(i = 0; i < UART_APP_TX_CHAN_COUNT; i++)
            {
                // replace command and channel number to get data from app_manager
                create_get_command(data, i);
                // exchange data with am
                exchange_data_with_am(cWbSvr2AppMgr, data, response, 0, 6);
                // find marker positions in the response from app_manager
                ix_start = get_marker_index(response, UI_COMMAND_LENGTH, MARKER_START);
                ix_end = get_marker_index(response, UI_COMMAND_LENGTH, MARKER_END);
                // flash_data is one big char array that must be stored in flash
                // append response to flash_data
                for(j = ix_start; j <= ix_end; j++)
                {
                    flash_data[k] = response[j]; k++;
                }
            }

            // send this data to core 0 to write to flash
#ifndef FLASH_THREAD
            flash_write_config(config_address, flash_data);
#else //FLASH_THREAD
            flash_access(FLASH_CONFIG_WRITE,
                         flash_data,
                         config_address,
                         cPersData);
#endif //FLASH_THREAD
#ifdef CR_DEBUG
            printstrln("CR: completed SAVE");
#endif

            break;
        } // case CMD_CONFIG_SAVE:

        case CMD_CONFIG_RESTORE:
        {
#ifdef CR_DEBUG
            printstrln("CR: RESTORE request");
#endif
            // get flash config address
#ifndef FLASH_THREAD
            config_address = get_flash_config_address();
            // get the data from flash
            flash_read_config(config_address, flash_data);
#else //FLASH_THREAD
            config_address = get_flash_config_address(cPersData);
            // get the data from flash
            flash_access(FLASH_CONFIG_READ, flash_data, config_address, cPersData);
#endif //FLASH_THREAD

            // check for configuration present in flash
            if(flash_data[0] != FLASH_VALID_CONFIG_PRESENT)
            {
                response[0] = MARKER_END;
            }
            else
            {
                // decode data from flash and store this UART settings
                for(i = 0; i < UART_APP_TX_CHAN_COUNT; i++)
                {
                    // find markers stored in flash
                    ix_start = get_marker_index(flash_data, FLASH_SIZE_PAGE, MARKER_START);
                    ix_end = get_marker_index(flash_data, FLASH_SIZE_PAGE, MARKER_END);
                    // replace command and channel
                    create_set_command(flash_data, i, ix_start);
                    // exchange data with am
                    exchange_data_with_am(cWbSvr2AppMgr, flash_data, response, ix_start, ix_end);
                    // replace previous data with zero to avoid marker find above
                    replace_with_zero(flash_data, 0, ix_end);
                }
            }

            /* Send signal as Restore command complete */
            cWbSvr2AppMgr <: UART_RESTORE_END_FROM_APP_TO_UART;
#ifdef CR_DEBUG
            printstrln("CR: completed RESTORE");
#endif
            break;
        } // case CMD_CONFIG_RESTORE:

        default:
        {
            // should not get here
            // if we do get here, send error response - user entered wrong command
            return 0; break;
        } // default

    } // switch(command)

    return 1;
}

/** =========================================================================
*  Description
*
*  \param xxx    description of xxx
*  \param yyy    description of yyy
*
**/
#pragma unsafe arrays
static int exchange_data_with_am(streaming chanend cWbSvr2AppMgr,
                                 char data[],
                                 char response[],
                                 int start,
                                 int end)
{
    // send data to app_manager
    send_to_channel(cWbSvr2AppMgr, data, start, end);
    // get response from app_manager
    get_response_data(cWbSvr2AppMgr, response);
}

/** =========================================================================
*  Description
*
*  \param xxx    description of xxx
*  \param yyy    description of yyy
*
**/
#pragma unsafe arrays
static int get_marker_index(char gmi_data[], int gmi_length, char gmi_marker)
{
    int i;
    // capture marker
    for(i = 0; i < gmi_length; i++)
    {
        if(gmi_data[i] == gmi_marker)
        {
            break;
        }
    }
    if(i == gmi_length)
    {
        // Return error response
        return 0; // Must return error as no 'marker enclosed' config data found
    }
    return i;
}

/** =========================================================================
*  Description
*
*  \param xxx    description of xxx
*  \param yyy    description of yyy
*
**/
#pragma unsafe arrays
static void get_response_data(streaming chanend cWbSvr2AppMgr, char grd_response[])
{
    int done = 0;
    int i = 0;
#ifdef CR_DEBUG
    printstr("CR: Response from am: ");
#endif
    do
    {
        cWbSvr2AppMgr :> grd_response[i];
#ifdef CR_DEBUG
            printchar(grd_response[i]);
#endif
        if(grd_response[i] == MARKER_END)
        {
            done = 1;
        }
        else
        {
            i++;
        }
    } while(done == 0);
#ifdef CR_DEBUG
    printstrln("");
#endif
}

/** =========================================================================
*  Description
*
*  \param xxx    description of xxx
*  \param yyy    description of yyy
*
**/
#pragma unsafe arrays
static void send_to_channel(streaming chanend cWbSvr2AppMgr,
                            char stc_data[],
                            int stc_start,
                            int stc_end)
{
    int i;
	cWbSvr2AppMgr <: UART_CMD_FROM_APP_TO_UART;
#ifdef CR_DEBUG
    printstr("CR: Sending  to   am: ");
#endif
    for(i = stc_start; i <= stc_end; i++)
    {
        cWbSvr2AppMgr <: stc_data[i];
#ifdef CR_DEBUG
        printchar(stc_data[i]);
#endif
    }
#ifdef CR_DEBUG
    printstrln("");
#endif
}

/** =========================================================================
 *  clear_char_array
 *
 *  \param char    character array to clear
 *  \param int     length of character array
 *
 **/
#pragma unsafe arrays
static void clear_char_array(char c[], int length)
{
    int i;
    for (i = 0; i < length; i++)
    {
        c[i] = '\0';
    }
}

/** =========================================================================
 *  replace part with zero
 *
 *  \param char    character array to clear
 *  \param int     start index to clear
 *  \param int     end index to clear
 *
 **/
#pragma unsafe arrays
static void replace_with_zero(char rwz_c[], int rwz_start, int rwz_end)
{
    int i;
    for (i = rwz_start; i <= rwz_end; i++)
    {
        rwz_c[i] = '0';
    }
}

/** =========================================================================
 *  clear_char_array
 *
 *  \param char    character array to clear
 *  \param int     length of character array
 *
 **/
#pragma unsafe arrays
#ifndef FLASH_THREAD
static int get_flash_config_address()
#else //FLASH_THREAD
static int get_flash_config_address(chanend cPersData)
#endif //FLASH_THREAD
{
    int flash_index_page_config, flash_length_config;
    int config_address = 0;

    // get the location of last file
    flash_index_page_config = fsdata[WPAGE_NUM_FILES - 1].page;
    flash_length_config = fsdata[WPAGE_NUM_FILES - 1].length;

    // get the config address. config data will be stored in a new sector above the fs file system
    // this way the sector can be erased an re-written on 'save' request
#ifndef FLASH_THREAD
    config_address = flash_get_config_address(flash_index_page_config,
                                              flash_length_config);
#else //FLASH_THREAD
    config_address = get_config_address(flash_index_page_config,
                                        flash_length_config,
                                        cPersData);
#endif //FLASH_THREAD
#ifdef CR_DEBUG
    printstr("CR: Config Address: "); printintln(config_address);
#endif

    return config_address;
}

/** =========================================================================
 *  clear_char_array
 *
 *  \param char    character array to clear
 *  \param int     length of character array
 *
 **/
#pragma unsafe arrays
static void create_get_command(char cc_data[], int cc_channel)
{
    cc_data[0] = MARKER_START;
    cc_data[1] = CMD_CONFIG_GET;
    cc_data[2] = MARKER_START;
    cc_data[3] = MARKER_START;
    cc_data[4] = (char)(cc_channel + 48);
    cc_data[5] = MARKER_START;
    cc_data[6] = MARKER_END;
}

/** =========================================================================
 *  clear_char_array
 *
 *  \param char    character array to clear
 *  \param int     length of character array
 *
 **/
#pragma unsafe arrays
static void create_set_command(char cc_data[], int cc_channel, int index)
{
    cc_data[index + 1] = CMD_CONFIG_SET;
    cc_data[index + 4] = (char)(cc_channel + 48);
}

/*=========================================================================*/
