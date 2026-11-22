# User Manual — `game_completo.vhd`

*Laser-dodging game on a 16x2 LCD display, controlled by a PS/2 keyboard · Spartan-3A/3AN FPGA · Xilinx ISE*

## 1. Overview

`game_completo.vhd` brings the entire project together into a single file: a reflex game for character LCDs. A block (the character) stays on either the top or bottom row of the display. Periodically, a warning (`!`) appears on one of the rows, followed by a laser occupying that row. If the player is on that row, they lose.

The game has three screens that switch automatically:
*   **Start menu:** displays "Square Dash / Press Enter".
*   **Gameplay:** the character dodges the lasers.
*   **Game over:** displays "score:" and the score value.

## 2. Requirements

*   Board with a Spartan-3A or 3AN FPGA and a 50 MHz clock.
*   16x2 LCD display (HD44780-compatible controller) wired in 8-bit mode: data pins `LCD_DB[7:0]`, `RS`, `RW`, and `OE` (enable).
*   PS/2 keyboard (PS/2 connector with `ps2_clk` and `ps2_data` signals). *Note: A USB keyboard only works if the board or an adapter exposes it as PS/2.*
*   Xilinx ISE (synthesis with XST).

## 3. Code Structure

The file contains six design units, in the following order (compilation order matters):

| Order | Entity | Function |
| :---: | :--- | :--- |
| 1 | `ps2_keyboard` | Reads the serial signal from the keyboard and outputs the key's scan code |
| 2 | `top_keyboard` | Interprets the W, S, and Enter keys |
| 3 | `menu` | Controls the LCD on the menu screen |
| 4 | `game` | Game logic and LCD rendering |
| 5 | `gameover` | Controls the LCD on the game over screen |
| 6 | `main` | Top-level: connects everything and selects which screen is active |

**Hierarchy:** `main` -> (`menu`, `game`, `gameover`, `top_keyboard` -> `ps2_keyboard`).

Each screen has its own LCD state machine. `main` keeps only one active at a time and routes only its signals to the LCD.

## 4. Top-Level Ports (`main`)

| Port | Direction | Description |
| :--- | :---: | :--- |
| `CLK` | input | FPGA clock, 50 MHz |
| `LCD_DB[7:0]` | output | LCD data bus |
| `RS` | output | LCD register select (command/data) |
| `RW` | output | LCD read/write |
| `OE` | output | LCD enable |
| `ps2_clk` | input | PS/2 keyboard clock |
| `ps2_data` | input | PS/2 keyboard data |

*There is no external reset button: the keyboard `rst` is an internal signal tied to `'0'` (see Section 8).*

## 5. Step-by-Step in ISE

1. Create a new project (*File -> New Project*), selecting your Spartan-3A or 3AN FPGA (the exact family, device, package, and speed grade of your board) and VHDL as the language.
2. Add the `game_completo.vhd` file (*Project -> Add Source*).
3. Select `main` as the top module. If ISE does not select it automatically, right-click `main` and choose *Set as Top Module*.
4. Create the pinout file (UCF) as shown in Section 6.
5. Run *Synthesize – XST*, then *Implement Design*, and finally *Generate Programming File*.
6. Program the `.bit` file onto the FPGA using iMPACT (or your board's programming tool).

> **Warning:** ISE will emit non-dedicated clock warnings because a counter bit is used as a clock (`clkCount(5)`, approximately 0.78 MHz). These warnings do not prevent synthesis.

## 6. Pinout File (UCF)

Pin assignments depend on your board. Replace `<pin>` using your board's reference manual. Template:

```ucf
NET "CLK"         LOC = "<pin>" | IOSTANDARD = LVCMOS33;
NET "CLK"         PERIOD = 20 ns HIGH 50%;

NET "LCD_DB<0>"   LOC = "<pin>" | IOSTANDARD = LVCMOS33;
# ... repeat for LCD_DB<1> through LCD_DB<7>
NET "RS"          LOC = "<pin>" | IOSTANDARD = LVCMOS33;
NET "RW"          LOC = "<pin>" | IOSTANDARD = LVCMOS33;
NET "OE"          LOC = "<pin>" | IOSTANDARD = LVCMOS33;

NET "ps2_clk"     LOC = "<pin>" | IOSTANDARD = LVCMOS33 | PULLUP;
NET "ps2_data"    LOC = "<pin>" | IOSTANDARD = LVCMOS33 | PULLUP;
```

**Attention:** The code drives the LCD in **8-bit** mode. If your board wires the LCD in 4-bit mode (such as the Spartan-3A Starter Kit), this project will not work without adapting the LCD interface.

## 7. How to Play

### Keys

| Key | Effect |
| :---: | :--- |
| **Enter** | Starts the game (on the menu) and begins a new match (on game over) |
| **W** | Character moves up (top row) |
| **S** | Character moves down (bottom row) |

*Upon power-up, the character starts on the top row.*

### Screen Flow

1. **Menu:** Displays "Square Dash" and "Press Enter". Press Enter to play.
2. **Gameplay:** The character stays in the second column. Each cycle consists of:
   * Clear screen, approximately 1 second at the start.
   * Warning `!` on one of the rows (randomly chosen), approximately 1 second.
   * Laser (solid blocks) across that row, approximately 1 second.
   * **How to avoid losing:** When the `!` appears, move to the other row before the laser fires. If you are on the same row as the laser, the game ends.
   * **Difficulty:** With each cycle, the phases get slightly shorter (about 4 ms less per cycle), so the game gradually speeds up.
3. **Game over:** Displays "score:" and the score. Press Enter to play again. To return to the menu, you must reprogram or reset the FPGA.

*Tip: Release Enter after pressing it so you don't accidentally start new matches.*

## 8. How `rst` Works

There are two types:

*   **Screen `rst` (`menu`, `game`, `gameover`):** Controlled by `main`. Only the active screen has `rst = '0'`. When a screen becomes active again, it re-runs the LCD initialization sequence and restarts from scratch. In `game`, this also resets the timers, acceleration, and laser state, so every match starts at the initial difficulty.
*   **Keyboard `rst`:** Internal signal fixed at `'0'`, so it is never asserted. If you want an external keyboard reset button, change `signal rst` in `main` to a port `rst : in std_logic` and map it to a button in the UCF.

## 9. Customization

| What to change | Where |
| :--- | :--- |
| **Phase duration (1 s)** | Constant `"10111110101111000010000000"` (50,000,000 cycles) in `game` |
| **Acceleration rate** | Value `"00000000110000000000000000"` added to `accelerate` in `game` |
| **Menu text** | `LCD_CMDS` array in the `menu` entity |
| **Game over text** | `LCD_CMDS` array in the `gameover` entity |
| **Displayed score** | Constant `number` in `gameover` (currently hardcoded to 63) |
| **Control keys** | Scan codes in `top_keyboard`: `1D` = W, `1B` = S, `5A` = Enter |
| **Clock other than 50 MHz** | Timings scale with the clock frequency; adjust the counter constants accordingly |

## 10. Troubleshooting

| Symptom | Likely Cause |
| :--- | :--- |
| **Blank LCD** | Poor contrast adjustment, power issue, or swapped LCD pins in the UCF |
| **Garbled characters** | Wrong `LCD_DB` pin order or LCD wired in 4-bit mode |
| **Keyboard unresponsive** | Wrong PS/2 pins, missing pull-ups, or a keyboard that does not support the PS/2 protocol |
| **Game restarts on its own** | Enter key stuck or repeating on the keyboard |
| **Clock warning in ISE** | Expected (counter-derived clock); does not prevent bitstream generation |
| **Compilation order error** | Keep the design units in the order listed in Section 3 |

## 11. Known Limitations

*   The game over score is hardcoded (value 63, displayed as 063) and does not reflect actual gameplay performance.
*   There is no external reset button, and no option to return to the menu from the game over screen.
*   The file was verified with GHDL (analysis and elaboration with no errors), but has not been tested on physical hardware. Pinout and LCD interface adjustments may be required for your specific board.
