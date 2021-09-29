# xKIM

xKIM is an extended monitor for KIM computer systems.  Commonly used in Corsham Technologies KIM-1 add-on boards.
It is a 6502 based monitor which has basic tools as well as some additional commands for working
with the Corsham Tech [SD Card](https://www.corshamtech.com/product/sd-card-system/) system.

## Features
* Pure 6502 code.
* Many subroutines available for external programs to use.
* Can auto-run Intel hex files upon loading.
* Can be placed in read-only memory.
* Has all low-level subroutines for talking to the SD Card.
* New commands can be added at run-time to the command handler.

## Command Summary (not a complete list)
* Exmine/edit memory.
* Jump to code.
* Load Intel hex file from console or SD card.
* Directory of SD card.
* Get clock from RTC.
* Memory test.
* Branch offset calculator, also within memory editor.
* Type SD file.
* Save memory to SD file.

## Branches
* master - Most people will want to use this branch, as this is the latest released code that we distribute with our products.  
* debugger - This is a short-lived branch for making more of xKIM as callable subroutines.  These changes are for support of a 65C02 debugger I am working on.

## License
[GNU GPLv3](https://choosealicense.com/licenses/gpl-3.0/)
