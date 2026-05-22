# Pinout / Wiring

English | [Deutsch](pinout.de.md)

This patch is for the Radxa Cubie A7A with a Radxa Penta SATA HAT Top Board.

## Relevant 40-pin connections

If the HAT is stacked directly, these are physical pin-to-pin connections. If using Dupont wires, connect only what is needed.

| Cubie A7A 40-pin | Penta SATA HAT 40-pin | Purpose |
|---:|---:|---|
| 3 | 3 | OLED I2C SDA, TWI7 / PJ23 |
| 5 | 5 | OLED I2C SCL, TWI7 / PJ22 |
| 13 | 13 | Fan PWM, S-PWM0-4 / PL6 |
| 6 | 6 | GND |
| 39 | 39 | Optional second GND |

Power only from one side. Do not power the Cubie via USB-C and the HAT separately while the 5 V rails are tied.

## Power

For disks, prefer the Penta HAT power path recommended for the HAT and let it power the setup, or use a wiring/topology that avoids backfeeding. Thin Dupont wires are not recommended for SSD/HDD current.

## Tested signal path

- Fan PWM: Cubie pin 13 → HAT pin 13 → Top-Board PWM
- OLED SDA/SCL: Cubie pin 3/5 → HAT pin 3/5 → Top-Board OLED
- OLED address: I2C bus 7, address `0x3c`
