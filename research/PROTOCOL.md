# Recovered Canyon Vigil USB protocol

Source: `payload/%AppFolder%/CANYON CND-SGM02RGB Gaming Mouse.exe`,
namespace `MyUSBControl`, class `USBCTL`. Full decoded CIL was retained locally
for inspection and is excluded from this repository. The original outer `setup.exe` produced a CRC warning
with macOS libarchive; the nested `x64/x64.exe` payload used for this analysis
extracted without such a warning and its Setup Factory payload decoded normally.

Every register request uses request 1, value `0x0100`. IN requests use type
`0xc0`, index=register, length=1. OUT uses type `0x40`,
index=`(byte << 8) | register`, length=0.

| Original method | Request / register |
| --- | --- |
| Enter_Sensor_Mode | OUT req=1 value=0 index=0 |
| Disable_Write_Protect | OUT index=0x5a09 |
| Enter_Sensor_Bank1 | OUT index=0x017f |
| InitPerformancePage, bank-1 sync | OUT index=0x2009 |
| Read/Write_Bank1_DPI1_Register through DPI4 | registers 2,3,4,5 |
| Read_Bank0_DPI_Gear_Register | bank0 reg2, low nibble=zero-based active slot |
| Write_Bank1_DPI_Sel_Register | bank1 reg9, value=(slot-1)*0x20 |
| Write_Bank1_RGB_LED_* | bank1 reg10, values 0x01/0x21/0x41/0x61/0x81/0xa1/0xe1 |
| Write_Bank1_RGB_Speed_Register | bank1 reg1 |
| Write_Bank1_CPI_Key_Fun_Register | bank1 reg11 |
| Write_Bank1_Rate_Fun_Register | bank1 reg14 |
| Enter_Sensor_Bank0 | OUT index=0x007f |
| Enable_Write_Protect | OUT index=0x0009 |
| Exit_Sensor_Mode | OUT req=6 value=0 index=0 |

DPI byte: high nibble=color preset 0–15; low nibble=(DPI/200)-1.
Original InitPerformancePage explicitly maps all 16 indices to 200…3200 DPI.
Rate values: 125=0xc2, 250=0x82, 500=0x42, 1000=0x02.
The Mac implementation preserves the low nibble of RGB mode rather than
overwriting it. USB writes are spaced by 20 ms. Bank reset, write protection,
and mode exit are attempted on failure as well as success.

## Hardware read on 2026-11-18

The new IOKit helper read the connected 093a:2533 device successfully:

```json
{"activeSlot":3,"speed":128,"mode":4,"action":232,"rate":500,
 "slots":[{"dpi":800,"color":0},{"dpi":1200,"color":8},
          {"dpi":2400,"color":4},{"dpi":3200,"color":10}],
 "raw":[128,3,133,75,175,39,111,67,32,65,232,69,36,66]}
```

No DPI, lighting, rate, or button settings were changed during this read.
The original Windows software implements the other five button mappings and
macros using its MouseService and virtual input driver. These cannot simply
be transferred into hardware registers; the Mac app implements a small set
of host-side shortcuts using a macOS event tap instead.
