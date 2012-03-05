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
#ifndef FLASH_COMMON_H_
#define FLASH_COMMON_H_

/*---------------------------------------------------------------------------
constants
---------------------------------------------------------------------------*/
#define FLASH_SIZE_PAGE                 256
#define FLASH_INDEX_START_PAGE          800
#define FLASH_SIZE_FILE                 4541
#define WPAGE_NUM_FILES                 2

#define FLASH_DATA_READ		'@'
/*---------------------------------------------------------------------------
ports and clocks
---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
typedefs
---------------------------------------------------------------------------*/
#if 0
typedef enum flash_data_event_type_t {
	/* Read data from flash */
	FLASH_DATA_READ,
	/* No more channel data to send for the current transaction */
	FLASH_DATA_END,
} flash_data_event_type_t;
#endif

/*---------------------------------------------------------------------------
global variables
---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
static variables
---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
prototypes
---------------------------------------------------------------------------*/

/*---------------------------------------------------------------------------
implementation
---------------------------------------------------------------------------*/

#endif /* FLASH_COMMON_H_ */