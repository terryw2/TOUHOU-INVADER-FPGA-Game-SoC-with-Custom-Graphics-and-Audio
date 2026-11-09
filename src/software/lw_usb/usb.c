#include "keyboard.h"

#include "project_config.h"
#include "xil_printf.h"

extern BYTE usb_error;
extern BYTE last_usb_task_state;

static HIDKeyboardReport last_report;
static HIDKeyboardReport last_printed_report;
static uint8_t last_task_state = 0xFFU;
static uint32_t poll_counter;
static BYTE last_kbd_rcode;

static void clear_report(HIDKeyboardReport *report) {
    report->report_id = HID_KEYBOARD_REPORT_ID;
    report->modifiers = 0U;
    for (uint8_t i = 0U; i < HID_KEYBOARD_MAX_KEYS; i++) {
        report->keycodes[i] = 0U;
    }
}

static const char *usb_state_name(uint8_t state) {
    switch (state) {
    case USB_DETACHED_SUBSTATE_INITIALIZE:
        return "DETACHED_INIT";
    case USB_DETACHED_SUBSTATE_WAIT_FOR_DEVICE:
        return "WAIT_DEVICE";
    case USB_DETACHED_SUBSTATE_ILLEGAL:
        return "ILLEGAL_BUS";
    case USB_STATE_ATTACHED:
        return "ATTACHED";
    case USB_ATTACHED_SUBSTATE_SETTLE:
        return "SETTLE";
    case USB_ATTACHED_SUBSTATE_RESET_DEVICE:
        return "RESET_DEVICE";
    case USB_ATTACHED_SUBSTATE_WAIT_RESET_COMPLETE:
        return "WAIT_RESET_DONE";
    case USB_ATTACHED_SUBSTATE_WAIT_SOF:
        return "WAIT_SOF";
    case USB_ATTACHED_SUBSTATE_GET_DEVICE_DESCRIPTOR_SIZE:
        return "GET_DEV_DESC";
    case USB_ATTACHED_SUBSTATE_POST_RESET_SETTLE:
        return "POST_RESET_SETTLE";
    case USB_STATE_ADDRESSING:
        return "ADDRESSING";
    case USB_STATE_CONFIGURING:
        return "CONFIGURING";
    case USB_STATE_RUNNING:
        return "RUNNING";
    case USB_STATE_ERROR:
        return "ERROR";
    default:
        return "UNKNOWN";
    }
}

static void print_usb_state_if_changed(void) {
    uint8_t state = GetUsbTaskState();

    if (state == last_task_state) {
        return;
    }

    last_task_state = state;
    xil_printf("[USB] state 0x%02x %s", state, usb_state_name(state));
    if (state == USB_STATE_ERROR) {
        xil_printf(" last=0x%02x err=0x%02x", last_usb_task_state, usb_error);
    }
    xil_printf("\r\n");
}

static uint8_t reports_differ(const HIDKeyboardReport *a, const HIDKeyboardReport *b) {
    if (a->modifiers != b->modifiers) {
        return 1U;
    }

    for (uint8_t i = 0U; i < HID_KEYBOARD_MAX_KEYS; i++) {
        if (a->keycodes[i] != b->keycodes[i]) {
            return 1U;
        }
    }

    return 0U;
}

static void print_report(const HIDKeyboardReport *report) {
    xil_printf("[USB] report mod=0x%02x keys=%02x %02x %02x %02x %02x %02x\r\n",
               report->modifiers,
               report->keycodes[0],
               report->keycodes[1],
               report->keycodes[2],
               report->keycodes[3],
               report->keycodes[4],
               report->keycodes[5]);
}

static void print_usb_poll_snapshot(void) {
    uint8_t state = GetUsbTaskState();

    xil_printf("[USB] poll=%lu state=0x%02x %s last=0x%02x err=0x%02x kbd=0x%02x HIRQ=0x%02x HRSL=0x%02x USBIRQ=0x%02x IOP1=0x%02x keys=%02x %02x %02x %02x %02x %02x\r\n",
               (unsigned long)poll_counter,
               state,
               usb_state_name(state),
               last_usb_task_state,
               usb_error,
               last_kbd_rcode,
               MAXreg_rd(rHIRQ),
               MAXreg_rd(rHRSL),
               MAXreg_rd(rUSBIRQ),
               MAXreg_rd(rIOPINS1),
               last_report.keycodes[0],
               last_report.keycodes[1],
               last_report.keycodes[2],
               last_report.keycodes[3],
               last_report.keycodes[4],
               last_report.keycodes[5]);
}

void usb_init(void) {
    clear_report(&last_report);
    clear_report(&last_printed_report);
    poll_counter = 0U;
    last_kbd_rcode = 0U;
    last_task_state = 0xFFU;
    xil_printf("[USB] init begin\r\n");
    MAX3421E_init();
    print_usb_state_if_changed();
    USB_init();
    print_usb_state_if_changed();
    xil_printf("[USB] host stack initialized\r\n");
}

uint8_t usb_poll(void) {
    BOOT_KBD_REPORT boot_report;
    BYTE rcode;

    poll_counter++;
    MAX3421E_Task();

    if (GetUsbTaskState() == USB_DETACHED_SUBSTATE_WAIT_FOR_DEVICE &&
        (poll_counter & 0x0FU) == 0U) {
        MAXreg_wr(rHCTL, bmSAMPLEBUS);
        MAX_busprobe();
    }

    USB_Task();
    print_usb_state_if_changed();
    clear_report(&last_report);

    if ((GetUsbTaskState() & USB_STATE_MASK) != USB_STATE_RUNNING) {
        if ((poll_counter & 0x7FU) == 0U) {
            print_usb_poll_snapshot();
        }
        return 0U;
    }

    rcode = kbdPoll(&boot_report);
    last_kbd_rcode = rcode;
    if (rcode == 0U) {
        last_report.modifiers = boot_report.mod;
        for (uint8_t i = 0U; i < HID_KEYBOARD_MAX_KEYS; i++) {
            last_report.keycodes[i] = boot_report.keycode[i];
        }
        if (reports_differ(&last_report, &last_printed_report) != 0U) {
            print_report(&last_report);
            last_printed_report = last_report;
        }
    } else if ((poll_counter & 0xFFU) == 0U) {
        xil_printf("[USB] kbdPoll rcode=0x%02x state=0x%02x\r\n", rcode, GetUsbTaskState());
    }
    if ((poll_counter & 0x7FU) == 0U) {
        print_usb_poll_snapshot();
    }

    return 1U;
}

void usb_read_report(HIDKeyboardReport *report) {
    if (report == 0) {
        return;
    }
    *report = last_report;
}
