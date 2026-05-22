# Pinout / Verkabelung

[English](pinout.md) | Deutsch

Dieser Patch ist für den Radxa Cubie A7A mit Radxa Penta SATA HAT Top Board gedacht.

## Relevante 40-Pin-Verbindungen

Wenn der HAT direkt aufgesteckt ist, sind das physische Pin-zu-Pin-Verbindungen. Bei Dupont-Kabeln sollten nur die benötigten Pins verbunden werden.

| Cubie A7A 40-Pin | Penta SATA HAT 40-Pin | Zweck |
|---:|---:|---|
| 3 | 3 | OLED I2C SDA, TWI7 / PJ23 |
| 5 | 5 | OLED I2C SCL, TWI7 / PJ22 |
| 13 | 13 | Fan PWM, S-PWM0-4 / PL6 |
| 6 | 6 | GND |
| 39 | 39 | optionale zweite Masseleitung |

Nur von einer Seite versorgen. Den Cubie nicht per USB-C versorgen und gleichzeitig den HAT separat einspeisen, wenn die 5-V-Schienen verbunden sind.

## Stromversorgung

Für SSDs/HDDs sollte der für den Penta HAT empfohlene Strompfad genutzt werden, oder eine Topologie, die Backfeeding vermeidet. Dünne Dupont-Kabel sind für SSD-/HDD-Lastströme nicht empfohlen.

## Getesteter Signalpfad

- Fan PWM: Cubie Pin 13 → HAT Pin 13 → Top-Board PWM
- OLED SDA/SCL: Cubie Pin 3/5 → HAT Pin 3/5 → Top-Board OLED
- OLED-Adresse: I2C-Bus 7, Adresse `0x3c`
