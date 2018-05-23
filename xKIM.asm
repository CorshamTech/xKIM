;*****************************************************
; Extended KIM monitor, written 2015 by Bob Applegate
; K2UT - bob@corshamtech.com
;
; This code was written as part of the Corsham Tech
; 60K RAM/EPROM board.  It provides a working area for
; an extended version of the KIM-1 monitor capabilities,
; mostly based on a TTY interface, not the keypad and
; hex display.
;
; This extensions contains an assortment of basic
; tools that are missing from the KIM-1's built in
; console monitor.  It has commands for loading hex
; files (as opposed to KIM format), accessing an SD
; card system, memory edit, hex dump, etc.  It also
; has the ability for user-defined extensions to be
; added.  And a number of common entry points have
; vectors so the monitor can be modified without
; breaking programs that use it.
;
; I'm not claiming copyright; I wrote most of this,
; but also borrowed from others (credit is given in
; those sections of code).  All of the portions I've
; written are free to use, but please keep my name
; in the comments somewhere.  Even better, consider
; buying a board from us: www.corshamtech.com
;
; 12/01/2015 - Bob Applegate
;              Initial development - V0.X
; 03/15/2016 - Bob Applegate
;              v1.0 - First official release
; 01/03/2017 - Bob Applegate
;              v1.1 - Added S command
;
;*****************************************************
; Version number
;
VERSION		equ	1
REVISION	equ	1
;
; Useful constants
;
false		equ	0
true		equ	~false
;
; Options.  If RAM_BASED is set then the code is put
; into RAM, else it's in ROM.  Very handy for testing
; new code; load the new code with the EPROM version
; and then test away.
;
RAM_BASED	equ	false
RAM_DATA_BASE	equ	$af80
RAM_CODE_BASE	equ	$b000
;
; Set the EPROM base addresses
;
ROM_START	equ	$e000
RAM_START	equ	$df80
;
; This is something that needs more investigation.
; If the SD system isn't reset enough then bad stuff
; happens after the RS button is pressed.  Set this to
; true to only reset the SD system on cold starts.
;
SD_ONLY_COLD	equ	false
;
; ASCII
;
NUL		equ	$00
BS		equ	$08
LF		equ	$0a
CR		equ	$0d
ESC		equ	$1b
SPC		equ	$20
;
; Intel HEX record types
;
DATA_RECORD	equ	$00
EOF_RECORD	equ	$01
;
; These are various buffer sizes
;
FILENAME_SIZE	equ	12
BUFFER_SIZE	equ	64
;
; Max number of bytes per line for hex dump
;
BYTESLINE	equ	16
;
; Flag values used to detect a cold start vs warm
;
COLD_FLAG_1	equ	$19
COLD_FLAG_2	equ	$62
;
;=====================================================
; This macro is used to verify that the current address
; meets a required value.  Used mostly to guarantee
; changes don't cause entry points to move.
;
VERIFY		macro	expected
		if * != expected
		fail	Not at requested address (expected)
		endif
		endm
;
;=====================================================
; KIM memory locations
;
		bss
		org	$00ef
PCL		ds	1
PCH		ds	1
PREG		ds	1
SPUSER		ds	1
ACC		ds	1
YREG		ds	1
XREG		ds	1
CHKHI		ds	1
CHKSUM		ds	1
INL	    	ds	1
INH		ds	1
POINTL		ds	1
POINTH		ds	1
TEMP		ds	1
TMPX		ds	1
CHAR		ds	1
MODE		ds	1
;
		org	$17e7
CHKL		ds	1
CHKH		ds	1
SAVX		ds	3
VEB	    	ds	6
CNTL30		ds	1
CNTH30		ds	1
TIMH		ds	1
SAL		ds	1
SAH	    	ds	1
EAL		ds	1
EAH	    	ds	1
ID  		ds	1
;
;=====================================================
; KIM I/O locations
;
SAD		    equ	$1740
PADD		equ	$1741
;
;=====================================================
; KIM subroutines located in the ROMs
;
NMIT		equ	$1c1c	;NMI handler
IRQT		equ	$1c1f	;IRQ handler
RST	    	equ	$1c22	;RESET handler
TTYKB		equ	$1c77	;do keyboard monitor
CRLF		equ	$1e2f	;print CR/LF
PRTPNT		equ	$1e1e	;print POINT
PRTBYT		equ	$1e3b	;print A as two hex digits
GETCH		equ	$1e5a	;get a key from tty into A
OUTSP		equ	$1e9e	;print a space
OUTCH		equ	$1ea0	;print A to TTY
SHOW		equ	$1dac
SHOW1		equ	$1daf
INCPT		equ	$1f63
;
;=====================================================
; I assume the RAM goes from 2000 to DFFF, so carve out
; a bit for use by the monitor.
;
		bss		;uninitialized data area
	if	RAM_BASED
		org     RAM_DATA_BASE
	else
		org	RAM_START
	endif
LowestAddress	equ	*
;
; Storage for registers for some monitor calls.
;
saveA		ds	1
saveX		ds	1
saveY		ds	1
;
; Pointer to the subroutine that gets the next input
; character.  Used for doing disk/console input.
;
inputVector	ds	2
;
; Same thing for output.
;
outputVector	ds	2
;
filename	ds	FILENAME_SIZE+1
buffer		ds	BUFFER_SIZE
diskBufOffset	ds	1
diskBufLength	ds	1
;
Temp16L		ds	1
Temp16H		ds	1
;
; The next group of memory are public and can be
; used by user programs, so don't modify where any
; of these are.  If you want to add new public data,
; put them here, always before existing items.  Be
; sure to adjust the ORG.
;
	if	RAM_BASED
		org	RAM_CODE_BASE-6
	else
		org	ROM_START-6
	endif
;
; ColdFlag is used to determine if the extended
; monitoring is doing a warm or cold start.
;
ColdFlag	ds	2
;
; Address of a command table for user-created
; extensions to the monitor.
;
ExtensionAddr	ds	2
;
; This is the higest location in RAM usable by user
; programs.  Nobody should go past this address.  If
; you are writing extentions to the monitor, it's
; okay to load before the address and then adjust
; this down to keep others from stomping on your
; extention.
;
; If your program modifies this value, it needs to
; set it back before terminating.
;
HighestAddress	ds	2
		page
;=====================================================
; Code starts at E000 and goes until FFFF, except for
; the 6502 vectors at the end of memory.
;
		code
	if	RAM_BASED
		org	RAM_CODE_BASE
	else
		org	ROM_START
	endif
;
; Vector table of useful and fun stuff!  These must
; not change or else existing code won't be calling
; the right functions.
;
BASE		equ	*
reentry		jmp	extKim	;extended monitor
		jmp	OUTCH	;output A to console
		jmp	GETCH	;get a key and echo
		jmp	GETCH	;no echo - KIM can't do it
		jmp	dummyRet	;future - console stat
		jmp	putsil	;print string after JSR
		jmp	getHex	;get hex value in A
		jmp	PRTBYT	;print A as hex
		jmp	getStartAddr
		jmp	getEndAddr
		jmp	getAddrRange
; future use
		VERIFY	BASE+$0021
		jmp	dummyRet
		jmp	dummyRet
		jmp	dummyRet
		jmp	dummyRet
		jmp	dummyRet
		jmp	dummyRet
;
; SD card functions
;
		VERIFY	BASE+$0033
		jmp	xParInit	;initialization
		jmp	xParSetWrite
		jmp	xParSetRead
		jmp	xParWriteByte
		jmp	xParReadByte
		jmp	DiskPing
		jmp	DiskDir
		jmp	DiskDirNext
		jmp	DiskOpenRead
		jmp	DiskRead
		jmp	DiskClose
		jmp	DiskOpenWrite
		jmp	DiskWrite
;
;		VERIFY	BASE+$0054
;=====================================================
;=====================================================
; Anything past this point can be moved in future
; releases so none of these functions nor data should
; be directly accessed by user programs!!!
;=====================================================
;=====================================================
; This is a dummy function for unimplemented functions
; that basically just clears carry and returns.
;
dummyRet	clc
		rts
;
defaultExt	db	0
		page
;=====================================================
; This is the start of the extended KIM monitor.
;
notty		jmp	TTYKB
extKim		ldx	#$ff
		txs
		lda	#$01	;see if in tty mode
		bit	SAD
		bne	notty	;branch if in keyboard mode

	if	~SD_ONLY_COLD
		jsr	xParInit
	endif
;
; Determine if this is a cold or warm start
;
		lda	ColdFlag
		cmp	#COLD_FLAG_1
		bne	coldStart
		lda	ColdFlag+1
		cmp	#COLD_FLAG_2
		bne	coldStart
		jmp	extKimLoop	;it's a warm start
;
; Cold start
;
coldStart	lda	#COLD_FLAG_1	;indicate we've done cold
		sta	ColdFlag
		lda	#COLD_FLAG_2
		sta	ColdFlag+1
;
; Point to an empty extension set by default.
;
		lda	#defaultExt&$ff	;set extension pointers
		sta	ExtensionAddr
		lda	#defaultExt/256
		sta	ExtensionAddr+1
;
; Set HighestAddress to just before our RAM area.
;
		lda	#(LowestAddress-1)&$ff
		sta	HighestAddress
		lda	#(LowestAddress-1)/256
		sta	HighestAddress+1
	if	SD_ONLY_COLD
;
; Initialize the interface to the SD card.  There seems to
; be a problem if this is done too often, so do it just once
; and be done.
;
		jsr	xParInit
	endif
;
; Display our welcome text
;
		jsr	putsil
		db	CR,LF,CR,LF
		db	"Extended KIM Monitor v"
		db	VERSION+'0','.',REVISION+'0',' '
		db	"by Corsham Technologies, LLC"
		db	CR,LF
		db	"www.corshamtech.com"
		db	CR,LF
	if	RAM_BASED
		db	CR,LF
		db	"*** RAM BASED VERSION ***"
		db	CR,LF
	endif
		db	0
;
; Main command loop.  Put out prompt, get command, etc.
; Prints a slightly different prompt for the RAM version.
;
extKimLoop	jsr	setInputConsole
		jsr	putsil	;output prompt
		db	CR,LF	;feel free to change it
	if	RAM_BASED
		db	"RAM"
	endif
		db	">",0
		jsr	GETCH
		cmp	#CR
		beq	extKimLoop
		cmp	#LF
		beq	extKimLoop
		sta	ACC	;save key
;
; Now cycle through the list of commands looking for
; what the user just pressed.
;
		lda	#commandTable&$ff
		sta	POINTL
		lda	#commandTable/256
		sta	POINTH
		jsr	searchCmd	;try to find it
;
; Hmmm... wasn't one of the built in commands, so
; see if it's an extended command.
;
		lda	ExtensionAddr
		sta	POINTL
		lda	ExtensionAddr+1
		sta	POINTH
		jsr	searchCmd
;
; If that returns, then the command was not found.
; Print that it's unknown.
;
		jsr	putsil
		db	" - Huh?",0
cmdFound	jmp	extKimLoop
;
;=====================================================
; Vector table of commands.  Each entry consists of a
; single ASCII character (the command), a pointer to
; the function which handles the command, and a pointer
; to a string that describes the command.
;
commandTable	db	'?'
		dw	showHelp
		dw	quesDesc
;
		db	'D'
		dw	doDiskDir
		dw	dDesc
;
		db	'E'	;edit memory
		dw	editMemory
		dw	eDesc
;
		db	'H'	;hex dump
		dw	hexDump
		dw	hDesc
;
		db	'J'	;jump to address
		dw	jumpAddress
		dw	jDesc
;
		db	'K'	;return to KIM monitor
		dw	returnKim
		dw	kDesc
;
		db	'L'	;load Intel HEX file
		dw	loadHex
		dw	lDesc
;
		db	'M'	;perform memory test
		dw	memTest
		dw	mDesc
;
		db	'P'	;ping remote disk
		dw	pingDisk
		dw	pDesc
;
		db	'S'	;save memory as hex file
		dw	saveHex
		dw	sDesc
;
		db	'T'	;type a file on SD
		dw	typeFile
		dw	tDesc
;
		db	'!'	;do cold restart
		dw	doCold
		dw	bangDesc
;
		db	0	;marks end of table
;
;=====================================================
; Descriptions for each command in the command table.
; This wastes a lot of space... I'm open for any
; suggestions to keep the commands clear but reducing
; the amount of space this table consumes.
;
quesDesc	db	"? ........... Show this help",0
dDesc		db	"D ........... Disk directory",0
eDesc		db	"E xxxx ...... Edit memory",0
hDesc		db	"H xxxx xxxx . Hex dump memory",0
jDesc		db	"J xxxx ...... Jump to address",0
kDesc		db	"K ........... Go to KIM monitor",0
lDesc		db	"L ........... Load HEX file",0
mDesc		db	"M xxxx xxxx . Memory test",0
pDesc		db	"P ........... Ping disk controller",0
sDesc		db	"S xxxx xxxx . Save memory to file",0
tDesc		db	"T ........... Type disk file",0
bangDesc	db	"! ........... Do a cold start",0
;
;=====================================================
; Return to KIM monitor.  Before returning, set the
; "open address" to the start of the extended monitor
; so the KIM monitor is pointing to it by default.
;
returnKim	jsr	putsil
		db	CR,LF
		db	"Returning to KIM..."
		db	CR,LF,0
		lda	#reentry&$0ff
		sta	POINTL	;point back to start...
		lda	#reentry/256
		sta	POINTH	;...of this code
		jmp	SHOW1	;return to KIM
;
;=====================================================
; Force a cold start.
;
doCold		inc	ColdFlag	;foul up flag
		jmp	extKim		;...and restart
;
;=====================================================
; Command handler for the ? command
;
showHelp	jsr	putsil
		db	CR,LF
		db	"Available commands:"
		db	CR,LF,LF,0
;
; Print help for built-in commands...
;
		lda	#commandTable&$ff
		sta	POINTL
		lda	#commandTable/256
		sta	POINTH
		jsr	displayHelp	;display help
;
; Now print help for the extension commands...
;
		lda	ExtensionAddr
		sta	POINTL
		lda	ExtensionAddr+1
		sta	POINTH
		jsr	displayHelp
		jsr	CRLF
		jmp	extKimLoop
;
;=====================================================
; This is a generic "not done yet" holder.  Any
; unimplemented commands should point here.
;
NDY		jsr	putsil
		db	CR,LF
		db	"Sorry, not done yet."
		db	CR,LF,0
NDYdone		jmp	extKimLoop
;
;=====================================================
; Do a hex dump of a region of memory.  This code was
; taken from MICRO issue 5, from an article by
; J.C. Williams.  I changed it a bit, but it's still
; basically the same code.
;
; Slight bug: the starting address is rounded down to
; a multiple of 16.  I'll fix it eventually.
;
hexDump		jsr	getAddrRange
		bcs	NDYdone
		jsr	CRLF
;
; Move start address to POINT but rounded down to the
; 16 byte boundary.
;
		lda	SAH
		sta	POINTH
		lda	SAL
		and	#$f0	;force to 16 byte
		sta	POINTL
;
; This starts each line.  Set flag to indcate we're
; doing the hex portion, print address, etc.
;
hexdump1	lda	#0	;set flag to hex mode
		sta	ID
		jsr	CRLF
		jsr	PRTPNT	;print the address
hexdump2	lda	POINTL	;push start of line...
		pha		;...address onto stack
		lda	POINTH
		pha
		jsr	space2
		ldx	#BYTESLINE-1	;number of bytes per line
		jsr	space2	;space before data

hexdump3	ldy	#0	;get next byte...
		lda	(POINTL),y
		bit	ID	;hex or ASCII mode?
		bpl	hexptbt	;branch if hex mode
;
; Print char if printable, else print a dot
;
		cmp	#' '
		bcc	hexdot
		cmp	#'~'
		bcc	hexpr
hexdot		lda	#'.'
hexpr		jsr	OUTCH
		jmp	hexend
;
; Print character as hex.  
;
hexptbt 	jsr	PRTBYT	;print as hex
		jsr	space	;and follow with a space
;
; See if we just dumped the last address.  If not, then
; increment to the next address and continue.
;
hexend  	lda	POINTL	;compare first
		cmp	EAL
		lda	POINTH
		sbc	EAH
;
; Now increment to the next address
;
		php
		jsr	INCPT
		plp
		bcc	hexlntst
;
		bit	ID
		bmi	hexdone
		dex
		bmi	hexdomap
hexdump5	jsr	space3
		dex
		bpl	hexdump5
hexdomap	dec	ID
		pla
		sta	POINTH
		pla
		sta	POINTL
		jmp     hexdump2
hexlntst	dex
		bpl	hexdump3
		bit	ID
		bpl	hexdomap
		pla
		pla
		jmp	hexdump1
;
; Clean up the stack and we're done
;
hexdone		jsr	CRLF
		pla
		pla
;
cmdRet2		jmp	extKimLoop
;
;=====================================================
; This does a memory test of a region of memory.  One
; problem with the KIM is that there is no routine to
; see if a new character is starting, so this loop
; just runs forever unless the user presses RESET.
;
; Asks for the starting and ending locations.
;
; This cycles a rolling bit, then adds a ninth
; pattern to help detect shorted address bits.
; Ie: 01, 02, 04, 08, 10, 20, 40, 80, BA
;
pattern		equ	CHKL	;re-use some KIM locations
original	equ	CHKH
;
; Test patterns
;
PATTERN_0	equ	$01
PATTERN_9	equ	$ba
;
memTest		jsr	getAddrRange	;get range
		bcs	cmdRet2		;branch if abort
;
		jsr	putsil
		db	CR,LF
		db	"Testing memory.  Press RESET to abort"
		db	0
		lda	#PATTERN_0	;only set initial...
		sta	pattern		;..pattern once
;
; Start of loop.  This fills/tests one complete pass
; of memory.
;
memTestMain	lda	SAL	;reset pointer to start
		sta	POINTL
		lda	SAH
		sta	POINTH
;
; Fill memory with the rolling pattern until the last
; location is filled.
;
		ldy	#0
		lda	pattern
		sta	original
memTestFill	sta	(POINTL),y
		cmp	#PATTERN_9	;at last pattern?
		bne	memFill3
		lda	#PATTERN_0	;restart pattern
		jmp	memFill4
;
; Rotate pattern left one bit
;
memFill3	asl	a
		bcc	memFill4	;branch if not overflow
		lda	#PATTERN_9	;ninth pattern
;
; The new pattern is in A.  Now see if we've reached
; the end of the area to be tested.
;
memFill4	pha		;save pattern
		lda	POINTL
		cmp	EAL
		bne	memFill5
		lda	POINTH
		cmp	EAH
		beq	memCheck
;
; Not done, so move to next address and keep going.
;
memFill5	jsr	INCPT
		pla		;recover pattern
		jmp	memTestFill
;
; Okay, memory is filled, so now go back and test it.
; We kept a backup copy of the initial pattern to
; use, but save the current pattern as the starting
; point for the next pass.
;
memCheck	pla
		sta	pattern	;for next pass
		lda	SAL	;reset pointer to start
		sta	POINTL
		lda	SAH
		sta	POINTH
		lda	original	;restore initial pattern
		ldy	#0
memTest2	cmp	(POINTL),y
		bne	memFail
		cmp	#PATTERN_9
		bne	memTest3
;
; Time to reload the pattern
;
		lda	#PATTERN_0
		bne	memTest4
;
; Rotate pattern left one bit
;
memTest3	asl	a
		bcc	memTest4
		lda	#PATTERN_9
;
; The new pattern is in A.
;
memTest4	pha		;save pattern
		lda	POINTL
		cmp	EAL
		bne	memTest5	;not at end
		lda	POINTH
		cmp	EAH
		beq	memDone	;at end of pass
;
; Not at end yet, so inc pointer and continue
;
memTest5	jsr	INCPT
		pla
		jmp	memTest2
;
; Another pass has completed.
;
memDone		pla
		lda	#'.'
		jsr	OUTCH
		jmp	memTestMain
;
; Failure.  Display the failed address, the expected
; value and what was actually there.
;
memFail		pha		;save pattern for error report
		jsr	putsil
		db	CR,LF
		db	"Failure at address ",0
		lda	POINTH
		jsr	PRTBYT
		lda	POINTL
		jsr	PRTBYT
		jsr	putsil
		db	".  Expected ",0
		pla
		jsr	PRTBYT
		jsr	putsil
		db	" but got ",0
		ldy	#0
		lda	(POINTL),y
		jsr	PRTBYT
		jsr	CRLF
cmdRet4		jmp	extKimLoop
;
;=====================================================
; Edit memory.  This waits for a starting address to be
; entered.  It will display the current address and its
; contents.  Possible user inputs and actions:
;
;   Two hex digits will place that value in memory
;   RETURN moves to next address
;   BACKSPACE moves back one address
;
editMemory      jsr	space
		jsr	getStartAddr
		bcs	cmdRet4
		lda	SAL	;move address into...
		sta	POINTL	;...POINT
		lda	SAH
		sta	POINTH
;
; Display the current location
;
editMem1	jsr	CRLF
		jsr	PRTPNT	;print address
		jsr	space
		ldy	#0
		lda	(POINTL),y	;get byte
		jsr	PRTBYT	;print it
		jsr	space
;
		jsr	getHex
		bcs	editMem2	;not hex
		ldy	#0
		sta	(POINTL),y	;save new value
;
; Bump POINT to next location
;
editMem3	jsr	INCPT
		jmp	editMem1
;
; Not hex, so see if another command
;
editMem2	cmp	#CR
		beq	editMem3	;move to next
		cmp	#BS
		bne     cmdRet3		;else exit
;
; Move back one location
;
		sec
		lda	POINTL
		sbc	#1
		sta	POINTL
		bcs	editMem1
		dec	POINTH
		jmp	editMem1
;
;=====================================================
; This handles the Load hex command.
;
loadHex		jsr	putsil
		db	CR,LF
		db	"Enter filename, or Enter to "
		db	"load from console: ",0
;
		jsr	getFileName	;get filename
		lda	filename	;null?
		beq	loadHexConsole	;load from console
;
; Open the file
;
;		jsr	xParInit
		ldy	#filename&$ff
		ldx	#filename/256
		jsr	DiskOpenRead
		bcc	loadHexOk	;opened ok
;
openfail	jsr	putsil
		db	CR,LF
		db	"Failed to open file"
		db	CR,LF,0
cmdRet3		jmp	extKimLoop
;
loadHexOk	jsr	setInputFile	;redirect input
		jmp	loadStart
;
; They are loading from the console
;
loadHexConsole	jsr	putsil
		db	CR,LF
		db	"Waiting for file, or ESC to"
		db	" exit..."
		db	CR,LF,0
		jsr	setInputConsole
;
; The start of a line.  First character should be a
; colon, but toss out CRs, LFs, etc.  Anything else
; causes an abort.
;
loadStart	jsr	redirectedGetch	;get start of line
		cmp	#CR
		beq	loadStart
		cmp	#LF
		beq	loadStart
		cmp	#':'	;what we expect
		bne	loadAbort
;
; Get the header of the record
;
		lda	#0
		sta	CHKL	;initialize checksum
;
		jsr	getHex	;get byte count
		bcs	loadAbort
		sta	saveX	;save byte count
		jsr	updateCrc
		jsr	getHex	;get the MSB of offset
		bcs	loadAbort
		sta	POINTH
		jsr	updateCrc
		jsr	getHex	;get LSB of offset
		bcs	loadAbort
		sta	POINTL
		jsr	updateCrc
		jsr	getHex	;get the record type
		bcs	loadAbort
		jsr	updateCrc
;
; Only handle two record types:
;    00 = data record
;    01 = end of file record
;
		cmp	#DATA_RECORD
		beq	loadDataRec
		cmp	#EOF_RECORD
		beq	loadEof
;
; Unknown record type
;
loadAbort       jsr	putsil
		db	CR,LF
		db	"Aborting"
		db	CR,LF,0
loadExit	jsr	setInputConsole
		jmp	extKimLoop
;
; EOF is easy
;
loadEof		jsr	getHex	;get checksum
		jsr	putsil
		db	CR,LF
		db	"Success!"
		db	CR,LF,0
lExit1		jmp	loadExit
;
; Data records have more work.  After processing the
; line, print a dot to indicate progress.  This should
; be re-thought as it could slow down loading a really
; big file if the console speed is slow.
;
loadDataRec	ldx	saveX	;byte count
		ldy	#0	;offset
loadData1	stx	saveX
		sty	saveY
		jsr	getHex
		bcs	loadAbort
		jsr	updateCrc
		ldy	saveY
		ldx	saveX
		sta	(POINTL),y
		iny
		dex
		bne	loadData1
;
; All the bytes were read so get the checksum and see
; if it agrees.  The checksum is a twos-complement, so
; just add the checksum into what we've been calculating
; and if the result is zero then the record is good.
;
		jsr	getHex	;get checksum
		clc
		adc	CHKL
		bne	loadAbort	;non-zero is error
;
		lda	#'.'	;sanity indicator when
		jsr	OUTCH	;...loading from file
		jmp	loadStart
;
;=====================================================
; Handles the command to save a region of memory as a
; file on the SD.
;
saveHex		jsr	getAddrRange	;get range to dump
		bcs	lExit1	;abort on error
;
; Get the filename to save to
;
		jsr	putsil
		db	CR,LF
		db	"Enter filename, or Enter to "
		db	"load from console: ",0
;
		jsr	getFileName	;get filename
		lda	filename	;null?
		beq	saveHexConsole	;dump to console
;
; They selected a file, so try to open it.
;
		ldx	#filename>>8
		ldy	#filename&$ff
		jsr	DiskOpenWrite	;attempt to open file
		bcc	sopenok		;branch if opened ok
		jmp	openfail
;
sopenok		jsr	setOutputFile
		jmp	savehex2
;
; They are saving to the console.  Set up the output
; vector and do the job.
;
saveHexConsole	jsr	setOutputConsole
;
; Compute the number of bytes to dump
;
savehex2	sec
		lda	EAL
		sbc	SAL
		sta	Temp16L
		lda	EAH
		sbc	SAH
		sta	Temp16H
		bcc	SDone	;start > end
		ora	0
		bmi	SDone	;more than 32K seems wrong
;
; Add one to the count
;
		inc	Temp16L
		bne	slab1
		inc	Temp16H
;
; Move pointer to zero page
;
slab1		lda	SAL
		sta	POINTL
		lda	SAH
		sta	POINTH
;
; Top of each loop.  Start by seeing if there are any bytes
; left to dump.
;
Sloop1		lda	Temp16H
		bne	Sgo	;more to do
		lda	Temp16L
		bne	Sgo	;more to do
;
; At end of the region, so output an end record.  This
; probably looks like overkill but keep in mind this
; might be going to a file so we can't use the normal
; string put functions.
;
		lda	#':'
		jsr	redirectedOutch
		lda	#0
		jsr	HexToOutput
		jsr	HexToOutput
		jsr	HexToOutput
		lda	#1
		jsr	HexToOutput
		lda	#$ff
		jsr	HexToOutput
;
; If output to file, flush and close the file.
;
		lda	filename
		beq	SDone		;it's going to console
		jsr	CloseOutFile
SDone		jmp	extKimLoop	;back to the monitor
;
; This dumps the next line.  See how many bytes are left to do
; and if more than BYTESLINE, then just do BYTESLINE.
;
Sgo		lda	Temp16H
		bne	Sdef	;do default number of bytes
		lda	Temp16L
		cmp	#BYTESLINE
		bcc	Scnt	;more than max per line
Sdef		lda	#BYTESLINE
Scnt		sta	SAVX	;for decrementing
		sta	ID	;for subtracting
;
; Put out the header
;
		lda	#':'
		jsr	redirectedOutch
;
		lda	SAVX
		sta	CHKL	;start checksum
		jsr	HexToOutput
;
		lda	POINTH	;starting address
		jsr	updateCrc
		jsr	HexToOutput
		lda	POINTL
		jsr	updateCrc
		jsr	HexToOutput
;
		lda	#0	;record type - data
		jsr	HexToOutput
;
; Now print the proper number of bytes
;
Sloop2		ldy	#0
		lda	(POINTL),y	;get byte
		jsr	updateCrc
		jsr	HexToOutput
		jsr	INCPT	;increment pointer
;
sdec		dec	SAVX
		bne	Sloop2
;
; Now print checksum
;
		lda	CHKL
		eor	#$ff	;one's complement
		clc
		adc	#1	;two's complement
		jsr	HexToOutput
;
; Output a CR/LF
;
		lda	#CR
		jsr	redirectedOutch
		lda	#LF
		jsr	redirectedOutch
;
; If saving to disk, output a dot to indicate progress.
;
		lda	filename
		beq	shf2
;
		lda	#'.'
		jsr	OUTCH	;goes to console
;
shf2		sec
		lda	Temp16L
		sbc	ID
		sta	Temp16L
		lda	Temp16H
		sbc	#0
		sta	Temp16H
;
		jmp	Sloop1
;
;=====================================================
; Adds the character in A to the CRC.  Preserves A.
;
updateCrc	pha
		clc
		adc	CHKL
		sta	CHKL
		pla
		rts
;
;=====================================================
; Handles the command to prompt for an address and then
; jump to it.
;
jumpAddress     jsr	space
		jsr	getStartAddr
		bcs	cmdRet	;branch on bad address
		jsr	CRLF
		jmp	(SAL)	;else jump to address
;
cmdRet		jmp	extKimLoop
;
;=====================================================
; Ping the Arduno disk controller.  This just sends the
; PING command gets back one character, then returns.
; Not much of a test but is sufficient to prove the
; link is working.
;
pingDisk
;		jsr	xParInit	;init interface
		jsr	putsil
		db	"ing... ",0
		jsr	DiskPing
		jsr	putsil
		db	"success!"
		db	CR,LF,0
doDiskDirEnd    jmp	extKimLoop
;
;=====================================================
; Do a disk directory of the SD card.
;
doDiskDir	jsr	putsil
		db	"isk Directory..."
		db	CR,LF,0
;		jsr	xParInit
		jsr	DiskDir
;
; Get/Display each entry
;
doDiskDirLoop   ldx	#filename/256	;pointer to buffer
		ldy	#filename&$ff
		stx	INH		;save for puts
		sty	INL
		jsr	DiskDirNext	;get next entry
		bcs	doDiskDirEnd	;carry = end of list
		jsr	space3
		jsr	puts		;else print name
		jsr	CRLF
		jmp	doDiskDirLoop	;do next entry
;
;=====================================================
; Type the contents of an SD file to console.
;
typeFile	jsr	putsil
		db	" - Enter filename: ",0
		jsr	getFileName
		ldy	#filename&$ff
		ldx	#filename/256
;		jsr	xParInit
		jsr	DiskOpenRead
		bcc	typeFile1	;opened ok
;
		jsr	putsil
		db	CR,LF
		db	"Failed to open file"
		db	CR,LF,0
		jmp	extKimLoop
;
; Now just keep reading in bytes and displaying them.
;
typeFile1	jsr	setInputFile	;reading from file
typeFileLoop	jsr	getNextFileByte
		bcs	typeEof
		jsr	OUTCH	;display character
		jmp	typeFileLoop
;
typeEof		jsr	DiskClose
		jmp	extKimLoop
;
; Add new commands here...
;
		page
;
;=====================================================
; This subroutine will search for a command in a table
; and call the appropriate handler.  See the command
; table near the start of the code for what the format
; is.  If a match is found, pop off the return address
; from the stack and jump to the code.  Else, return.
;
searchCmd	ldy	#0
cmdLoop		lda	(POINTL),y
		beq	cmdNotFound
		cmp	ACC	;compare to user's input
		beq	cmdMatch
		iny		;start of function ptr
		iny
		iny		;start of help
		iny
		iny		;move to next command
		bne	cmdLoop
;
; It's found!  Load up the address of the code to call,
; pop the return address off the stack and jump to the
; handler.
;
cmdMatch	iny
		lda	(POINTL),y	;handler LSB
		pha
		iny
		lda	(POINTL),y	;handler MSB
		sta	POINTH
		pla
		sta	POINTL
		pla		;pop return address
		pla
		jmp	(POINTL)
;
; Not found, so just return.
;
cmdNotFound	rts
;
;=====================================================
; Given a pointer to a command table in POINT, display
; the help text for all commands in the table.
;
displayHelp	ldy	#0	;index into command table
showHelpLoop	lda	(POINTL),y	;get command
		beq	showHelpDone	;jump if at end
;
; Display this entry's descriptive text
;
		iny		;skip over command
		iny		;skip over function ptr
		iny
		lda	(POINTL),y
		sta	INL
		iny
		lda	(POINTL),y
		sta	INH
		tya
		pha
		jsr	OUTSP
		jsr	OUTSP
		jsr	puts	;print description
		jsr	CRLF
		pla
		tay
		iny		;point to next entry
		bne	showHelpLoop
showHelpDone	rts
;
;=====================================================
; Print some spaces.
;
space3		jsr	space
space2		jsr	space
space   	jmp	OUTSP
;
;=====================================================
; This prints the null-terminated string that
; immediately follows the JSR to this function.  This
; version was written by Ross Archer and is at:
;
;    www.6502.org/source/io/primm.htm
;
putsil		pla
		sta	INL
		pla
		sta	INH
		ldy	#1
		jsr	putsy
		inc	INL
		bne	puts2
		inc	INH
puts2		jmp	(INL)
;
;=====================================================
; This prints the null terminated string pointed to by
; INL and INH.  Modifies those locations to point to
; the end of the string.
;
puts		ldy	#0
putsy		lda	(INL),y
		inc	INL
		bne	puts1
		inc	INH
puts1		ora	#0
		beq	putsdone
		sty	saveY
		jsr	OUTCH	;print character
		ldy	saveY
		jmp	putsy
putsdone	rts
;
;=====================================================
; This gets two hex characters and returns the value
; in A with carry clear.  If a non-hex digit is
; entered, then A contans the offending character and
; carry is set.
;
getHex		jsr	getNibble
		bcs	getNibBad
		asl	a
		asl	a
		asl	a
		asl	a
		and	#$f0
		sta	saveA
		jsr	getNibble
		bcs	getNibBad
		ora	saveA
		clc
		rts
;
; Helper.  Gets next input char and converts to a
; value from 0-F in A and returns C clear.  If not a
; valid hex character, return C set.
;
getNibble	jsr	redirectedGetch
		ldx	#nibbleHexEnd-nibbleHex-1
getNibble1	cmp	nibbleHex,x
		beq	getNibF	;got match
		dex
		bpl	getNibble1
getNibBad	sec
		rts

getNibF		txa		;index is value
		clc
		rts
;
nibbleHex	db	"0123456789ABCDEF"
nibbleHexEnd	equ	*
;
;=====================================================
; Gets a four digit hex address amd places it in
; SAL and SAH.  Returns C clear if all is well, or C
; set on error and A contains the character.
;
getStartAddr	jsr	getHex
		bcs	getDone
		sta	SAH
		jsr	getHex
		bcs	getDone
		sta	SAL
		clc
getDone		rts
;
;=====================================================
; Gets a four digit hex address amd places it in
; EAL and EAH.  Returns C clear if all is well, or C
; set on error and A contains the character.
;
getEndAddr	jsr	getHex
		bcs	getDone
		sta	EAH
		jsr	getHex
		bcs	getDone
		sta	EAL
		clc
		rts
;
;=====================================================
; Get an address range and leave them in SAL and EAL.
;
getAddrRange    jsr	space
		jsr	getStartAddr
		bcs	getDone
		lda	#'-'
		jsr	OUTCH
		jsr	getEndAddr
		rts
;
;=====================================================
; Get a disk filename.  The KIM's behavior of echoing
; even key prevents this from being too fancy, but it's
; good enough.
;
getFileName	ldx	#0
getFilename1	jsr	GETCH	;get next key
		cmp	#CR	;end of the input?
		beq	getFnDone
		cmp	#BS	;backspace?
		beq	getFnDel
		cpx	#FILENAME_SIZE	;check size
		beq	getFilename1	;at length limit
		sta	filename,x	;else save it
		inx
		bne	getFilename1
;
getFnDel	dex		;back up one
		bpl	getFilename1
		inx		;can't go past start
		beq	getFilename1
getFnDone       lda	#0	;terminate line
		sta	filename,x
		jsr	CRLF
		rts
;
;=====================================================
; This gets the next byte from an open disk file.  If
; there are no more bytes left, this returns C set.
; Else, C is clear and A contains the character.
;
getNextFileByte ldx 	diskBufOffset
		cpx	diskBufLength
		bne	hasdata		;branch if still data
;
; There is no data left in the buffer, so read a
; block from the SD system.
;
		lda	#BUFFER_SIZE
		ldx	#buffer>>8
		ldy	#buffer&$ff
		jsr	DiskRead
		bcs	getNextEof
;
; A contains the number of bytes actually read.
;
		sta	diskBufLength	;save length
		cmp	#0		;shouldn't happen
		beq	getNextEof
;
		ldx	#0
hasdata		lda	buffer,x
		inx
		stx	diskBufOffset
		clc
		rts
;
getNextEof	lda	#0
		sta	diskBufOffset
		sta	diskBufLength
		sec
		rts
		page
;
;=====================================================
; This is a helper function used for redirected I/O.
; It simply does a jump through the input vector
; pointer to get the next input character.
;
redirectedGetch	jmp	(inputVector)
;
;=====================================================
; Set up the input vector to point to the normal
; console input subroutine.
;
setInputConsole	lda	#GETCH&$ff
		sta     inputVector
		lda	#GETCH/256
		sta	inputVector+1
		rts
;
;=====================================================
; Set up the input vector to point to a file read
; subroutine.
;
setInputFile    lda	#getNextFileByte&$ff
		sta     inputVector
		lda	#getNextFileByte/256
		sta	inputVector+1
;
; Clear counts and offsets so the next read will
; cause the file to be read.
;
		lda	#0
		sta	diskBufOffset
		sta	diskBufLength
		rts
;
;=====================================================
; Print character in A as two hex digits to the
; current output device (console or file).
;
HexToOutput	pha		;save return value
		pha
		lsr	a	;move top nibble to bottom
		lsr	a
		lsr	a
		lsr	a
		jsr	hexta	;output nibble
		pla
		jsr	hexta
		pla		;restore
		rts
;
hexta		and	#%0001111
		cmp	#$0a
		clc
		bmi	hexta1
		adc	#7
hexta1		adc	#'0'	;then fall into...
;
;=====================================================
; This is a helper function used for redirected I/O.
; It simply does a jump through the output vector
; pointer to send the character in A to the proper
; device.
;
redirectedOutch	jmp	(outputVector)
;
;=====================================================
; Set up the output vector to point to the normal
; console output subroutine.
;
setOutputConsole
		lda	#OUTCH&$ff
		sta     outputVector
		lda	#OUTCH/256
		sta	outputVector+1
		rts
;
;=====================================================
; Set up the output vector to point to a file write
; subroutine.
;
setOutputFile    lda	#putNextFileByte&$ff
		sta     outputVector
		lda	#putNextFileByte/256
		sta	outputVector+1
;
; Clear counts and offsets so the next read will
; cause the file to be read.
;
		lda	#0
		sta	diskBufOffset
		rts
;
;=====================================================
; Add the byte in A to the output buffer.  If the
; buffer is full, flush it to disk.
;
putNextFileByte	ldx	diskBufOffset
		cpx	#BUFFER_SIZE	;buffer full?
		bne	pNFB		;no
;
; The buffer is full, so write it out.
;
		pha			;save byte
		lda	#BUFFER_SIZE
		ldx	#buffer>>8
		ldy	#buffer&$ff
		jsr	DiskWrite
;
		ldx	#0		;reset index
		pla
pNFB		sta	buffer,x
		inx
		stx	diskBufOffset
		rts
;
;=====================================================
; This flushes any data remaining in the disk buffer
; and then closes the file.
;
CloseOutFile	lda	diskBufOffset
		beq	closeonly
		ldx	#buffer>>8
		ldy	#buffer&$ff
		jsr	DiskWrite
;
closeonly	jmp	DiskClose
;
		include	"pario.asm"
		include	"parproto.inc"
		include	"diskfunc.asm"
		page
;
;=====================================================
; These are the 6502 vectors.  On the Corsham
; Technologies RAM/ROM board the user can select
; whether or not to use these based on a switch
; setting on the board.
;
		org	$fffa
NMI		dw	NMIT	;in KIM
RESET		dw	RST	;in KIM
IRQ		dw	IRQT	;in KIM
;
		end

