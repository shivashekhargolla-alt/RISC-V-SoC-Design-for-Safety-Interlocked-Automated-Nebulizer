# AXI-Lite Seven-Segment Display Controller

AXI4-Lite slave seven-segment display controller IP core for the NebuCore SoC.

## Overview

Drives a 4-digit, 7-segment front-panel display showing the current dose volume
or treatment countdown.  A hardware time-division multiplexer cycles through
the four digit positions at ~250 Hz (4 ms per digit), giving a flicker-free
appearance.  Optional blink mode blanks the display at ~1 Hz.  The BRIGHT
register provides a 4-bit brightness field for future PWM-dimmer integration.

## Register Map

| Offset | Name   | Access | Description                                             |
|--------|--------|--------|---------------------------------------------------------|
| 0x00   | DATA   | R/W    | [15:0] four packed BCD/hex nibbles (digit3..digit0)     |
| 0x04   | CTRL   | R/W    | [0] disp_en, [1] blink_en                               |
| 0x08   | STATUS | R      | [3:0] current active digit index (0–3)                  |
| 0x0C   | BRIGHT | R/W    | [3:0] brightness level (0=off, 15=max, for future PWM)  |

### DATA register layout

```
Bit 15 14 13 12 | 11 10  9  8 |  7  6  5  4 |  3  2  1  0
     digit3     |   digit2    |   digit1    |   digit0
   (leftmost)   |             |             | (rightmost)
```

Each nibble is a 4-bit hex value (0x0–0xF) decoded by the internal LUT.

## 7-Segment Encoding

Segment bits are ordered `{g, f, e, d, c, b, a}` (active-high):

| Nibble | Char | Pattern |   | Nibble | Char | Pattern |
|--------|------|---------|---|--------|------|---------|
| 0x0    |  0   | 0x3F    |   | 0x8    |  8   | 0x7F    |
| 0x1    |  1   | 0x06    |   | 0x9    |  9   | 0x6F    |
| 0x2    |  2   | 0x5B    |   | 0xA    |  A   | 0x77    |
| 0x3    |  3   | 0x4F    |   | 0xB    |  b   | 0x7C    |
| 0x4    |  4   | 0x66    |   | 0xC    |  C   | 0x39    |
| 0x5    |  5   | 0x6D    |   | 0xD    |  d   | 0x5E    |
| 0x6    |  6   | 0x7D    |   | 0xE    |  E   | 0x79    |
| 0x7    |  7   | 0x07    |   | 0xF    |  n   | 0x37    |

## Address in SoC

`0x1800_0000` (suggested, 4 KiB window) on Interconnect M05 per the NebuCore
SoC spec.

## Timing Parameters (100 MHz clock)

| Parameter           | Value         | Description              |
|---------------------|---------------|--------------------------|
| Mux prescaler       | 400,000 ticks | ~4 ms per digit          |
| Mux refresh rate    | ~250 Hz       | Full 4-digit scan rate   |
| Blink half-period   | 50,000,000    | ~500 ms on / 500 ms off  |
| Blink frequency     | ~1 Hz         | Visible blink rate       |

## Files

```
seg7/
├── README.md
├── project.config
├── scripts/
│   └── filelist
└── src/
    ├── include/
    │   └── seg7_defines.vh
    └── rtl/
        └── axi_seg7_top.v
```

## Signals

### AXI4-Lite Slave (32-bit data, 4-bit addr, 12-bit ID)

| Signal           | Dir | Width | Description                  |
|------------------|-----|-------|------------------------------|
| axi_aclk_i       | in  | 1     | System clock                 |
| axi_aresetn_i    | in  | 1     | Active-low reset             |
| axi_awid_i       | in  | 12    | Write address ID             |
| axi_awaddr_i     | in  | 4     | Write byte address           |
| axi_awvalid_i    | in  | 1     | Write address valid          |
| axi_awready_o    | out | 1     | Write address ready          |
| axi_wdata_i      | in  | 32    | Write data                   |
| axi_wstrb_i      | in  | 4     | Write byte strobes           |
| axi_wvalid_i     | in  | 1     | Write data valid             |
| axi_wready_o     | out | 1     | Write data ready             |
| axi_bid_o        | out | 12    | Write response ID            |
| axi_bresp_o      | out | 2     | Write response (always OKAY) |
| axi_bvalid_o     | out | 1     | Write response valid         |
| axi_bready_i     | in  | 1     | Write response ready         |
| axi_arid_i       | in  | 12    | Read address ID              |
| axi_araddr_i     | in  | 4     | Read byte address            |
| axi_arvalid_i    | in  | 1     | Read address valid           |
| axi_arready_o    | out | 1     | Read address ready           |
| axi_rid_o        | out | 12    | Read response ID             |
| axi_rdata_o      | out | 32    | Read data                    |
| axi_rresp_o      | out | 2     | Read response (always OKAY)  |
| axi_rvalid_o     | out | 1     | Read data valid              |
| axi_rready_i     | in  | 1     | Read data ready              |

### Display Physical Interface

| Signal        | Dir | Width | Description                          |
|---------------|-----|-------|--------------------------------------|
| seg_out_o     | out | 7     | Segment lines {g,f,e,d,c,b,a}, active-high |
| digit_sel_o   | out | 4     | One-hot digit select (bit3=leftmost) |
