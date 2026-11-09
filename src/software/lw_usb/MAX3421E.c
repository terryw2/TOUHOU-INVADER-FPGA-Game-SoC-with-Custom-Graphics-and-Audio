/* MAX3421E low-level functions                             */
/* reading, writing registers, reset, host transfer, etc.   */
/* GPIN, GPOUT are as per tutorial, reassign if necessary   */
/* USB power on is GPOUT7, USB power overload is GPIN7      */

#define _MAX3421E_C_

#include "stdlib.h"
#include "stdio.h"
#include "string.h"
#include "project_config.h"
#include "xparameters.h"
#include <unistd.h>
#include <xspi.h>
#include <xgpio.h>
#include <xtmrctr.h>
#include "xintc.h"

#ifndef XPAR_TIMER_USB_AXI_DEVICE_ID
# ifdef XPAR_TIMER_USB_DEVICE_ID
#  define XPAR_TIMER_USB_AXI_DEVICE_ID XPAR_TIMER_USB_DEVICE_ID
# elif defined(XPAR_TMRCTR_0_DEVICE_ID)
#  define XPAR_TIMER_USB_AXI_DEVICE_ID XPAR_TMRCTR_0_DEVICE_ID
# endif
#endif

/* variables and data structures */

/* External variables */

extern BYTE usb_task_state;
static XSpi SpiInstance;
static int Status;
static XGpio Gpio_rst;
static XGpio Gpio_int;
static XSpi_Config *ConfigPtr;	/* Pointer to Configuration data */
XTmrCtr Usb_timer;
static u32 max_int_low_count;
static BYTE last_printed_hirq = 0xFFU;
static u32 busprobe_print_count;
static BYTE last_busprobe_hrsl = 0xFFU;
static BYTE last_busprobe_sample = 0xFFU;
static BYTE last_busprobe_state = 0xFFU;

static void MAX3421E_debug_dump(const char *tag)
{
	xil_printf("[MAX] %s REV=0x%02x USBIRQ=0x%02x HIRQ=0x%02x HRSL=0x%02x MODE=0x%02x IOP1=0x%02x IOP2=0x%02x\r\n",
	           tag,
	           MAXreg_rd(rREVISION),
	           MAXreg_rd(rUSBIRQ),
	           MAXreg_rd(rHIRQ),
	           MAXreg_rd(rHRSL),
	           MAXreg_rd(rMODE),
	           MAXreg_rd(rIOPINS1),
	           MAXreg_rd(rIOPINS2));
}

//Initialization of SPI port is already done for you
void SPI_init() {

	xil_printf("[MAX] Initializing SPI\r\n");

	ConfigPtr = XSpi_LookupConfig(XPAR_SPI_USB_DEVICE_ID);
	if (ConfigPtr == NULL) {
		xil_printf("[MAX] SPI lookup failed\r\n");
		return;
	}

	Status = XSpi_CfgInitialize(&SpiInstance, ConfigPtr,
				  ConfigPtr->BaseAddress);
	if (Status != XST_SUCCESS) {
		xil_printf("[MAX] SPI cfg init failed %d\r\n", Status);
		return;
	}

	if (Status != XST_SUCCESS)
	{
		xil_printf ("[MAX] SPI device failed to initialize %d\r\n", Status);
	}
	Status = XSpi_SetOptions(&SpiInstance, XSP_MASTER_OPTION | XSP_MANUAL_SSELECT_OPTION);
	if (Status != XST_SUCCESS)
	{
		xil_printf ("[MAX] SPI device failed to go into master mode %d\r\n", Status);
	}

	XSpi_Start(&SpiInstance);
	XSpi_IntrGlobalDisable(&SpiInstance);
}

BYTE SPI_wr(BYTE data) {
	return 0; //This function is not needed
}


/* Functions    */
/* Single host register write   */
void MAXreg_wr(BYTE reg, BYTE val)
{
	u8 Status;
	u8 WriteBuffer[2];
	WriteBuffer[0] = reg + 2;
	WriteBuffer[1] = val;
	XSpi_SetSlaveSelect(&SpiInstance, 1);
	Status = XSpi_Transfer(&SpiInstance, WriteBuffer, NULL, 2);
}

BYTE* MAXbytes_wr(BYTE reg, BYTE nbytes, BYTE* data)
{
	u8 Status;
	u8 WriteBuffer[nbytes + 1];
	WriteBuffer[0] = reg + 2;
	memcpy(WriteBuffer + 1, data, nbytes);
	XSpi_SetSlaveSelect(&SpiInstance, 1);
	Status = XSpi_Transfer(&SpiInstance, WriteBuffer, NULL, nbytes + 1);
	return (data + nbytes);
}

BYTE MAXreg_rd(BYTE reg)
{
	u8 Status;
	u8 WriteBuffer[2];
	u8 ReadBuffer[2];
	memset(WriteBuffer, 0, 2);
	WriteBuffer[0] = reg;
	XSpi_SetSlaveSelect(&SpiInstance, 1);
	Status = XSpi_Transfer(&SpiInstance, WriteBuffer, ReadBuffer, 2);
	return ReadBuffer[1];
}

BYTE* MAXbytes_rd(BYTE reg, BYTE nbytes, BYTE* data)
{
	u8 Status;
	u8 WriteBuffer[nbytes + 1];
	u8 ReadBuffer[nbytes + 1];
	memset(WriteBuffer, 0, nbytes + 1);
	WriteBuffer[0] = reg;
	XSpi_SetSlaveSelect(&SpiInstance, 1);
	Status = XSpi_Transfer(&SpiInstance, WriteBuffer, ReadBuffer, nbytes + 1);
	memcpy(data, ReadBuffer + 1, nbytes);
	return (data + nbytes);
}
/* reset MAX3421E using chip reset bit. SPI configuration is not affected   */
void MAX3421E_reset(void) {
	Status = XGpio_Initialize(&Gpio_rst, XPAR_GPIO_USB_RST_DEVICE_ID);
	XGpio_SetDataDirection(&Gpio_rst, 1, 0); //configure reset, and set reset to output
	Status = XGpio_Initialize(&Gpio_int, XPAR_GPIO_USB_INT_DEVICE_ID);
	XGpio_SetDataDirection(&Gpio_int, 1, 0x1); //configure int, and set int to input


	//hardware reset, then software reset
	XGpio_DiscreteClear(&Gpio_rst, 1, 0x1);
	xil_printf ("[MAX] Holding USB in reset\r\n");
	for (int delay = 0; delay < 0x7FFFF; delay ++){}
	XGpio_DiscreteSet(&Gpio_rst, 1, 0x1);
	xil_printf ("[MAX] Revision 0x%02x; 0x00 usually means SPI/reset is wrong\r\n", MAXreg_rd( rREVISION));
	BYTE tmp = 0;

	MAXreg_wr( rUSBCTL, bmCHIPRES);      //Chip (soft) reset. This stops the oscillator
	MAXreg_wr( rUSBCTL, 0x00);           //Remove the reset

	xil_printf("[MAX] Waiting for PLL to stabilize\r\n");
		while (!(MAXreg_rd( rUSBIRQ) & bmOSCOKIRQ)) { //wait until the PLL stabilizes
			tmp++;                                      //timeout after 256 attempts
			if ((tmp & 0x0FU) == 0U) {
				xil_printf("[MAX] PLL wait USBIRQ=0x%02x\r\n", MAXreg_rd(rUSBIRQ));
			}
			if (tmp == 0) {
				xil_printf("[MAX] reset timeout, check SPI/MAXreg_wr\r\n");
				break;
			}
		}
	MAX3421E_debug_dump("after reset");
	}
/* turn USB power on/off                                                */
/* ON pin of VBUS switch (MAX4793 or similar) is connected to GPOUT0    */
/* OVERLOAD pin of Vbus switch is connected to GPIN7                    */
/* OVERLOAD state low. NO OVERLOAD or VBUS OFF state high.              */
BOOL Vbus_power(BOOL action) {
#ifdef MB_USB_NO_VBUS_SWITCH
    xil_printf("[MAX] VBUS switch request ignored in MB_USB_NO_VBUS_SWITCH build\r\n");
    return TRUE;
#else
    BYTE tmp = MAXreg_rd( rIOPINS1 );       //copy of IOPINS2
    BYTE before = tmp;
    if( action ) {                              //turn on by setting GPOUT0
        tmp |= bmGPOUT0;
    }
    else {                                      //turn off by clearing GPOUT0
        tmp &= ~bmGPOUT0;
    }
    MAXreg_wr( rIOPINS1,tmp );                              //send GPOUT0
    for (int delay = 0; delay < 0xFFFFF; delay ++){}		//delay a couple MS
    xil_printf ("[MAX] VBUS %s IOPINS1 0x%02x -> 0x%02x readback 0x%02x USBIRQ=0x%02x\r\n",
                action ? "ON" : "OFF",
                before,
                tmp,
                MAXreg_rd(rIOPINS1),
                MAXreg_rd(rUSBIRQ));
    return( TRUE );                                         // power on/off successful
	return (1);
#endif
}

/* probe bus to determine device presence and speed */
void MAX_busprobe(void) {
	BYTE bus_sample;
	BYTE hrsl;

//  MAXreg_wr(rHCTL,bmSAMPLEBUS);
	hrsl = MAXreg_rd( rHRSL);            //Get J,K status
	bus_sample = hrsl & ( bmJSTATUS | bmKSTATUS);      //zero the rest of the byte
	busprobe_print_count++;
	if ((hrsl != last_busprobe_hrsl) ||
	    (bus_sample != last_busprobe_sample) ||
	    (usb_task_state != last_busprobe_state) ||
	    ((busprobe_print_count & 0xFFU) == 1U)) {
		last_busprobe_hrsl = hrsl;
		last_busprobe_sample = bus_sample;
		last_busprobe_state = usb_task_state;
		xil_printf("[MAX] busprobe HRSL=0x%02x sample=0x%02x state=0x%02x\r\n",
		           hrsl, bus_sample, usb_task_state);
	}

	switch (bus_sample) {                   //start full-speed or low-speed host
	case ( bmJSTATUS):
		/*kludgy*/
		if (usb_task_state != USB_ATTACHED_SUBSTATE_WAIT_RESET_COMPLETE) { //bus reset causes connection detect interrupt
			if (!(MAXreg_rd( rMODE) & bmLOWSPEED)) {
				MAXreg_wr( rMODE, MODE_FS_HOST);         //start full-speed host
				xil_printf("Starting in full speed\n");
			} else {
				MAXreg_wr( rMODE, MODE_LS_HOST);    //start low-speed host
				xil_printf("Starting in low speed\n");
			}
			usb_task_state = ( USB_STATE_ATTACHED); //signal usb state machine to start attachment sequence
		}
		break;
	case ( bmKSTATUS):
		if (usb_task_state != USB_ATTACHED_SUBSTATE_WAIT_RESET_COMPLETE) { //bus reset causes connection detect interrupt
			if (!(MAXreg_rd( rMODE) & bmLOWSPEED)) {
				MAXreg_wr( rMODE, MODE_LS_HOST);   //start low-speed host
				xil_printf("Starting in low speed\n");
			} else {
				MAXreg_wr( rMODE, MODE_FS_HOST);         //start full-speed host
				xil_printf("Starting in full speed\n");
			}
			usb_task_state = ( USB_STATE_ATTACHED); //signal usb state machine to start attachment sequence
		}
		break;
	case ( bmSE1):              //illegal state
		usb_task_state = ( USB_DETACHED_SUBSTATE_ILLEGAL);
		break;
	case ( bmSE0):              //disconnected state
		if (!((usb_task_state & USB_STATE_MASK) == USB_STATE_DETACHED)) //if we came here from other than detached state
			usb_task_state = ( USB_DETACHED_SUBSTATE_INITIALIZE); //clear device data structures
		else {
			MAXreg_wr( rMODE, MODE_FS_HOST); //start full-speed host
			usb_task_state = ( USB_DETACHED_SUBSTATE_WAIT_FOR_DEVICE);
		}
		break;
	} //end switch( bus_sample )
}
/* MAX3421E initialization after power-on   */
void MAX3421E_init(void) {
	/* Configure full-duplex SPI, interrupt pulse   */
	SPI_init();
	MAXreg_wr( rPINCTL, (bmFDUPSPI + bmINTLEVEL + bmGPXB)); //Full-duplex SPI, level interrupt, GPX
	MAX3421E_debug_dump("after SPI/PINCTL");
	MAX3421E_reset();                                //stop/start the oscillator

	//start USB timer
	Status = XTmrCtr_Initialize(&Usb_timer, XPAR_TIMER_USB_AXI_DEVICE_ID);
	if (Status != XST_SUCCESS) {
			xil_printf ("[MAX] Timer instantiation failed\r\n");
	}
	XTmrCtr_Start(&Usb_timer, 0);

	xil_printf ("[MAX] Timer sanity ticks begin\r\n");
	//Test timer to make sure it is plausible
	for (int i = 0; i < 3; i++)
	{
		u32 current = XTmrCtr_GetValue(&Usb_timer, 0);
		while (XTmrCtr_GetValue(&Usb_timer, 0) - current < 100000000)
		{

		}
		xil_printf ("[MAX] tick\r\n");
	}

	/* configure power switch   */
	Vbus_power( OFF);                                      //turn Vbus power off
	//MAXreg_wr( rGPINIEN, bmGPINIEN7); //enable interrupt on GPIN7 (power switch overload flag)
	Vbus_power( ON);
	/* configure host operation */
	MAXreg_wr( rMODE, bmDPPULLDN | bmDMPULLDN | bmHOST | bmSEPIRQ); // set pull-downs, SOF, Host, Separate GPIN IRQ on GPX
	//MAXreg_wr( rHIEN, bmFRAMEIE|bmCONDETIE|bmBUSEVENTIE );                      // enable SOF, connection detection, bus event IRQs
	MAXreg_wr( rHIEN, bmCONDETIE);                        //connection detection
	/* HXFRDNIRQ is checked in Dispatch packet function */
	MAXreg_wr(rHCTL, bmSAMPLEBUS);        // update the JSTATUS and KSTATUS bits
	MAX_busprobe();                             //check if anything is connected
	MAXreg_wr( rHIRQ, bmCONDETIRQ); //clear connection detect interrupt                 
	MAXreg_wr( rCPUCTL, 0x01);                            //enable interrupt pin
	MAX3421E_debug_dump("init done");
}

/* MAX3421 state change task and interrupt handler */
void MAX3421E_Task(void) {
	if ((XGpio_DiscreteRead(&Gpio_int, 1) & 0x01) == 0) {
		max_int_low_count++;
		if ((max_int_low_count & 0x3FFU) == 1U) {
			xil_printf("[MAX] INT low count=%lu\r\n", max_int_low_count);
		}
		MaxIntHandler();
	}
	//if ( IORD_ALTERA_AVALON_PIO_DATA(USB_GPX_BASE) == 1) {
	//	xil_printf("GPX interrupt\n\r");
	//	MaxGpxHandler();
	//}
}

void MaxIntHandler(void) {
	BYTE HIRQ;
	BYTE HIRQ_sendback = 0x00;
	HIRQ = MAXreg_rd( rHIRQ);                  //determine interrupt source
	if (HIRQ != last_printed_hirq) {
		last_printed_hirq = HIRQ;
		xil_printf("[MAX] HIRQ=0x%02x\r\n", HIRQ);
	}
	/* Leave FRAMEIRQ set here; USB_Task polls and clears SOF when needed. */

	if (HIRQ & bmCONDETIRQ) {
		MAX_busprobe();
		HIRQ_sendback |= bmCONDETIRQ;      //set sendback to 1 to clear register
	}
	if (HIRQ & bmSNDBAVIRQ) //if the send buffer is clear (previous transfer completed without issue)
	{
		MAXreg_wr(rSNDBC, 0x00);//clear the send buffer (not really necessary, but clears interrupt)
	}
	if (HIRQ & bmBUSEVENTIRQ) {           //bus event is either reset or suspend
		if (usb_task_state == USB_ATTACHED_SUBSTATE_WAIT_RESET_COMPLETE) {
			MAXreg_wr(rMODE, MAXreg_rd(rMODE) | bmSOFKAENAB);
			MAXreg_wr(rHIRQ, bmFRAMEIRQ);
			usb_task_state = USB_ATTACHED_SUBSTATE_WAIT_SOF;
		} else {
			xil_printf("[MAX] bus event ignored state=0x%02x\r\n", usb_task_state);
		}
		HIRQ_sendback |= bmBUSEVENTIRQ;
	}
	/* End HIRQ interrupts handling, clear serviced IRQs    */
	MAXreg_wr( rHIRQ, HIRQ_sendback); //write '1' to CONDETIRQ to ack bus state change
}

void MaxGpxHandler(void) {
	BYTE GPINIRQ;
	GPINIRQ = MAXreg_rd( rGPINIRQ);            //read both IRQ registers
}
