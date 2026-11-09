/* HID class support functions */

#include <stdio.h>
#include "project_config.h"
#include "xil_printf.h"

BYTE bigbuf[256];   //256 bytes
extern DEV_RECORD devtable[];

HID_DEVICE hid_device = { { 0 } };
EP_RECORD hid_ep[2] = { { 0 } }; //HID class endpoints, 1 control, 1 interrupt-IN
//the third endpoint is not implemented     

static BYTE descriptor_len_checked(const BYTE *ptr, const BYTE *end)
{
	if (ptr >= end || (WORD)(end - ptr) < 2U) {
		return 0U;
	}
	if (ptr[0] < 2U || (WORD)(end - ptr) < ptr[0]) {
		return 0U;
	}
	return ptr[0];
}

static BOOL advance_descriptor(BYTE **byte_ptr, USB_DESCR **data_ptr, const BYTE *end)
{
	BYTE len = descriptor_len_checked(*byte_ptr, end);
	if (len == 0U) {
		return FALSE;
	}
	*byte_ptr = *byte_ptr + len;
	*data_ptr = (USB_DESCR*)*byte_ptr;
	return TRUE;
}

static BOOL config_header_valid(const USB_DESCR *data_ptr)
{
	return (data_ptr->descr.config.bLength >= CONF_DESCR_LEN) &&
	       (data_ptr->descr.config.bDescriptorType == USB_DESCRIPTOR_CONFIGURATION) &&
	       (data_ptr->descr.config.wTotalLength >= CONF_DESCR_LEN);
}

static WORD read_le16(const BYTE *ptr)
{
	return (WORD)ptr[0] | ((WORD)ptr[1] << 8);
}

static BYTE endpoint_addr(const BYTE *endpoint)
{
	return endpoint[2];
}

static BYTE endpoint_attr(const BYTE *endpoint)
{
	return endpoint[3];
}

static WORD endpoint_max_packet(const BYTE *endpoint)
{
	return read_le16(endpoint + 4) & 0x07FFU;
}

static BYTE endpoint_interval(const BYTE *endpoint)
{
	return endpoint[6];
}

static BOOL endpoint_is_safe_boot_in(const BYTE *endpoint)
{
	WORD max_packet = endpoint_max_packet(endpoint);

	return ((endpoint_addr(endpoint) & EP_DIR_IN) != 0U) &&
	       ((endpoint_attr(endpoint) & bmUSB_TRANSFER_TYPE) == USB_TRANSFER_TYPE_INTERRUPT) &&
	       (max_packet != 0U) &&
	       (max_packet <= EP_MAX_PKT_INTR_FS);
}

static void print_endpoint_raw(const char *prefix, const BYTE *endpoint)
{
	xil_printf("%s raw=%02x %02x %02x %02x %02x %02x %02x addr=0x%02x attr=0x%02x max=%u interval=%u\r\n",
	           prefix,
	           endpoint[0], endpoint[1], endpoint[2], endpoint[3],
	           endpoint[4], endpoint[5], endpoint[6],
	           endpoint_addr(endpoint),
	           endpoint_attr(endpoint),
	           endpoint_max_packet(endpoint),
	           endpoint_interval(endpoint));
}

/* HID Mouse probe. Called from USB state machine.                          */
/* assumes configuration length is less than 256 bytes                      */
/* looks for Class:03, Subclass: 01, Protocol: 02 in interface descriptor   */
/* sets mouse in boot protocol                                              */
/* assumes single configuration and interface configuration 0               */
BOOL HIDMProbe(BYTE addr, DWORD flags) {
	BYTE tmpbyte;
	BYTE rcode;
	BYTE confvalue;
	WORD total_length;
	USB_DESCR* data_ptr = (USB_DESCR *) &bigbuf;
	BYTE* byte_ptr = bigbuf;
	rcode = XferGetConfDescr(addr, 0, CONF_DESCR_LEN, 0, bigbuf); //get configuration descriptor
	if (rcode) {   //error handling
		//printf("unable to get configuration descriptor");
		return (FALSE);
	}
	if (config_header_valid(data_ptr) == FALSE) {
		return (FALSE);
	}
	if (data_ptr->descr.config.wTotalLength > sizeof(bigbuf)) {
		total_length = 256;
	} else {
		total_length = data_ptr->descr.config.wTotalLength;
	}
	rcode = XferGetConfDescr(addr, 0, total_length, 0, bigbuf); //get the whole configuration
	if (rcode) {   //error handling
		//printf("unable to get configuration");
		return (FALSE);
	}
	if (config_header_valid(data_ptr) == FALSE) {
		return (FALSE);
	}
	confvalue = data_ptr->descr.config.bConfigurationValue;
	//printf("checking configuration value (length: %d): ",
	//		data_ptr->descr.config.wTotalLength);
	//for (int i = 0; i < data_ptr->descr.config.wTotalLength; i++) {
		//printf("%x ", (unsigned char) (bigbuf[i] & 0xff));
	//}
	while (byte_ptr < bigbuf + total_length) {
		BYTE desc_len = descriptor_len_checked(byte_ptr, bigbuf + total_length);
		if (desc_len == 0U) {
			return (FALSE);
		}
		if (data_ptr->descr.config.bDescriptorType != USB_DESCRIPTOR_INTERFACE) {
			if (advance_descriptor(&byte_ptr, &data_ptr, bigbuf + total_length) == FALSE) {
				return (FALSE);
			}
		} // if( data_ptr->descr.config.bDescriptorType != USB_DESCRIPTOR_INTERFACE
		else {
			if (desc_len < INTR_DESCR_LEN) {
				return (FALSE);
			}
			//printf("starting interface parsing at byte location %d\n",
			//		data_ptr->descr.config.bLength);
			BYTE class = data_ptr->descr.interface.bInterfaceClass;
			BYTE subclass = data_ptr->descr.interface.bInterfaceSubClass;
			BYTE protocol = data_ptr->descr.interface.bInterfaceProtocol;
			//printf("class %x, subclass %x, protocol %x,\n", class, subclass,
			//		protocol);
			//interface descriptor
			if (class == HID_INTF && subclass == BOOT_INTF_SUBCLASS
					&& protocol == HID_PROTOCOL_MOUSE) {
				//detected a mouse
				devtable[addr].devclass = HID_M;                  //device class
				tmpbyte = devtable[addr].epinfo->MaxPktSize;
				HID_init();                         //initialize data structures
				devtable[addr].epinfo = hid_ep; //switch endpoint information structure
				devtable[addr].epinfo[0].MaxPktSize = tmpbyte;
				hid_device.interface =
						data_ptr->descr.interface.bInterfaceNumber;
				hid_device.addr = addr;
					if (advance_descriptor(&byte_ptr, &data_ptr, bigbuf + total_length) == FALSE) {
						return (FALSE);
					}
					while (byte_ptr < bigbuf + total_length) {
						desc_len = descriptor_len_checked(byte_ptr, bigbuf + total_length);
						if (desc_len == 0U) {
							return (FALSE);
						}
						if (data_ptr->descr.config.bDescriptorType
								!= USB_DESCRIPTOR_ENDPOINT) { //skip to endpoint descriptor
							if (advance_descriptor(&byte_ptr, &data_ptr, bigbuf + total_length) == FALSE) {
								return (FALSE);
							}
						} else {
							if (desc_len < EP_DESCR_LEN ||
								endpoint_is_safe_boot_in(byte_ptr) == FALSE) {
								return (FALSE);
							}
							/* fill endpoint information structure */
						devtable[addr].epinfo[1].epAddr =
								endpoint_addr(byte_ptr);
						devtable[addr].epinfo[1].Attr =
								endpoint_attr(byte_ptr);
						devtable[addr].epinfo[1].MaxPktSize =
								endpoint_max_packet(byte_ptr);
						devtable[addr].epinfo[1].Interval =
								endpoint_interval(byte_ptr);
						// devtable[ addr ].epinfo[ 1 ].rcvToggle = bmRCVTOG0;
						/* configure device */
						rcode = XferSetConf(addr, 0, confvalue); //set configuration
						if (rcode) {   //error handling
							return (FALSE);
						}
						rcode = XferSetProto(addr, 0, hid_device.interface,
								BOOT_PROTOCOL);
						if (rcode) {   //error handling
							return (FALSE);
						} else {
							return (TRUE);
						}
					}
				}   //while( byte_ptr....
			}   //if (Class matches
			else { //if class don't match; die on first interface. Not really correct
				return (FALSE);
			}
		} //else if( data_ptr->
	} // while( byte_ptr < &buf + total_length
	return (FALSE);
}
/* HID Keyboard probe. Called from USB state machine.                           */
/* assumes configuration length is less than 256 bytes                          */
/* looks for Class:03, Subclass: 01, Protocol: 01 in interface descriptor       */
/* sets keyboard in boot protocol                                               */
/* assumes single configuration, single endpoint, and interface configuration 0 */
BOOL HIDKProbe(BYTE addr, DWORD flags) {
	BYTE tmpbyte;
	BYTE rcode;
	BYTE confvalue;
	WORD total_length;
	USB_DESCR* data_ptr = (USB_DESCR *) &bigbuf;
	BYTE* byte_ptr = bigbuf;
	rcode = XferGetConfDescr(addr, 0, CONF_DESCR_LEN, 0, bigbuf); //get configuration descriptor
	if (rcode) {   //error handling           
		xil_printf("[HIDK] get short config descriptor failed rcode=0x%02x\r\n", rcode);
		return (FALSE);
	}
	if (config_header_valid(data_ptr) == FALSE) {
		return (FALSE);
	}
	if (data_ptr->descr.config.wTotalLength > sizeof(bigbuf)) {
		total_length = 256;
	} else {
		total_length = data_ptr->descr.config.wTotalLength;
	}
	rcode = XferGetConfDescr(addr, 0, total_length, 0, bigbuf); //get the whole configuration
	if (rcode) {   //error handling
		xil_printf("[HIDK] get full config descriptor failed rcode=0x%02x len=%u\r\n",
		           rcode, total_length);
		return (FALSE);
	}
	if (config_header_valid(data_ptr) == FALSE) {
		xil_printf("[HIDK] invalid config descriptor header\r\n");
		return (FALSE);
	}
	confvalue = data_ptr->descr.config.bConfigurationValue; //save configuration value to use later
	xil_printf("[HIDK] config value=%u total_length=%u\r\n", confvalue, total_length);
	while (byte_ptr < bigbuf + total_length) {             //parse configuration
		BYTE desc_len = descriptor_len_checked(byte_ptr, bigbuf + total_length);
		if (desc_len == 0U) {
			xil_printf("[HIDK] invalid descriptor step\r\n");
			return (FALSE);
		}
		if (data_ptr->descr.config.bDescriptorType != USB_DESCRIPTOR_INTERFACE) { //skip to the next descriptor
			if (advance_descriptor(&byte_ptr, &data_ptr, bigbuf + total_length) == FALSE) {
				xil_printf("[HIDK] descriptor advance failed\r\n");
				return (FALSE);
			}
		} // if( data_ptr->descr.config.bDescriptorType != USB_DESCRIPTOR_INTERFACE
		else {
			if (desc_len < INTR_DESCR_LEN) {
				xil_printf("[HIDK] short interface descriptor len=%u\r\n", desc_len);
				return (FALSE);
			}
			//printf("starting interface parsing at byte location %d\n",
			//		data_ptr->descr.config.bLength);
			BYTE class = data_ptr->descr.interface.bInterfaceClass;
			BYTE subclass = data_ptr->descr.interface.bInterfaceSubClass;
			BYTE protocol = data_ptr->descr.interface.bInterfaceProtocol;
			xil_printf("[HIDK] interface class=0x%02x subclass=0x%02x protocol=0x%02x\r\n",
			           class, subclass, protocol);
			//printf("class %x, subclass %x, protocol %x,\n", class, subclass,
			//		protocol);
			//interface descriptor
			if (class == HID_INTF && subclass == BOOT_INTF_SUBCLASS
					&& protocol == HID_PROTOCOL_KEYBOARD) {
				//detected a keyboard
				devtable[addr].devclass = HID_K;             //fill device class
				tmpbyte = devtable[addr].epinfo->MaxPktSize; //save max.packet size
				HID_init();                         //initialize data structures
				devtable[addr].epinfo = hid_ep; //switch endpoint information structure
				devtable[addr].epinfo[0].MaxPktSize = tmpbyte; //fill in max.packet size
				hid_device.interface =
						data_ptr->descr.interface.bInterfaceNumber; //fill in interface number to be used in HID requests
				hid_device.addr = addr;                        //fill in address
					if (advance_descriptor(&byte_ptr, &data_ptr, bigbuf + total_length) == FALSE) {
						xil_printf("[HIDK] endpoint search advance failed\r\n");
						return (FALSE);
					}
					while (byte_ptr < bigbuf + total_length) {
						desc_len = descriptor_len_checked(byte_ptr, bigbuf + total_length);
						if (desc_len == 0U) {
							xil_printf("[HIDK] invalid endpoint descriptor step\r\n");
							return (FALSE);
						}
						if (data_ptr->descr.config.bDescriptorType
								!= USB_DESCRIPTOR_ENDPOINT) { //skip to endpoint descriptor
							if (advance_descriptor(&byte_ptr, &data_ptr, bigbuf + total_length) == FALSE) {
								xil_printf("[HIDK] endpoint descriptor advance failed\r\n");
								return (FALSE);
							}
						} else {
							if (desc_len < EP_DESCR_LEN ||
								endpoint_is_safe_boot_in(byte_ptr) == FALSE) {
								xil_printf("[HIDK] unsafe endpoint descriptor len=%u\r\n", desc_len);
								if (desc_len >= EP_DESCR_LEN) {
									print_endpoint_raw("[HIDK] endpoint", byte_ptr);
								}
								return (FALSE);
							}
							print_endpoint_raw("[HIDK] endpoint", byte_ptr);
							/* fill endpoint information structure */
						devtable[addr].epinfo[1].epAddr =
								endpoint_addr(byte_ptr);
						devtable[addr].epinfo[1].Attr =
								endpoint_attr(byte_ptr);
						devtable[addr].epinfo[1].MaxPktSize =
								endpoint_max_packet(byte_ptr);
						devtable[addr].epinfo[1].Interval =
								endpoint_interval(byte_ptr);
						xil_printf("[HIDK] endpoint addr=0x%02x attr=0x%02x maxpkt=%u interval=%u\r\n",
						           devtable[addr].epinfo[1].epAddr,
						           devtable[addr].epinfo[1].Attr,
						           devtable[addr].epinfo[1].MaxPktSize,
						           devtable[addr].epinfo[1].Interval);
						/* configure device */
						rcode = XferSetConf(addr, 0, confvalue); //set configuration
						if (rcode) {   //error handling
							xil_printf("[HIDK] set config failed rcode=0x%02x\r\n", rcode);
							return (FALSE);
						}
						rcode = XferSetProto(addr, 0, hid_device.interface,
								BOOT_PROTOCOL);
						if (rcode) {   //error handling
							xil_printf("[HIDK] set boot protocol failed rcode=0x%02x\r\n", rcode);
							return (FALSE);
						} else {
							xil_printf("[HIDK] keyboard ready addr=%u interface=%u\r\n",
							           hid_device.addr, hid_device.interface);
							return (TRUE);
						}
					}
				}   //while( byte_ptr....
			}   //if (Class matches
			else { //if class don't match; stop processing after first interface. Not really correct
				xil_printf("[HIDK] first interface is not boot keyboard\r\n");
				return (FALSE);
			}
		} //else if( data_ptr->
	} // while( byte_ptr < &buf + total_length
	return (FALSE);
}
/* HID data structures initialization */
void HID_init(void) {
	hid_ep[1].sndToggle = bmSNDTOG0;
	hid_ep[1].rcvToggle = bmRCVTOG0;
}
/* poll boot mouse */
BYTE mousePoll(BOOT_MOUSE_REPORT* buf) {
	BYTE rcode;
	MAXreg_wr( rPERADDR, hid_device.addr);    //set peripheral address
	rcode = XferInTransfer(hid_device.addr, 1, 8, (BYTE*) buf,
			devtable[hid_device.addr].epinfo[1].MaxPktSize);
	return (rcode);
}
/* poll boot keyboard */
BYTE kbdPoll(BOOT_KBD_REPORT* buf) {
	BYTE rcode;
	MAXreg_wr( rPERADDR, hid_device.addr);    //set peripheral address
	rcode = XferInTransfer(hid_device.addr, 1, 8, (BYTE*) buf,
			devtable[hid_device.addr].epinfo[1].MaxPktSize);
	return (rcode);
}
BOOL HIDMEventHandler(BYTE address, BYTE event, void *data, DWORD size) {
	return (FALSE);
}
BOOL HIDKEventHandler(BYTE address, BYTE event, void *data, DWORD size) {
	return (FALSE);
}
