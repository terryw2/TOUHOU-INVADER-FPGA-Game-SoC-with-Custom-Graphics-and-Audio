#ifndef KEYBOARD_ADAPTER_H
#define KEYBOARD_ADAPTER_H

#include <stdint.h>

#define HID_KEYBOARD_REPORT_ID 0x01U
#define HID_KEYBOARD_MAX_KEYS  6U

typedef struct {
    uint8_t report_id;
    uint8_t modifiers;
    uint8_t keycodes[HID_KEYBOARD_MAX_KEYS];
} HIDKeyboardReport;

void usb_init(void);
uint8_t usb_poll(void);
void usb_read_report(HIDKeyboardReport *report);

#endif
