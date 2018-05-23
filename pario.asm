;*****************************************************
; These are the low-level I/O routines to talk to the
; Arduino processor connected to the KIM's I/O port.
;
; August 2014, Bob Applegate K2UT, bob@corshamtech.com
;
; Which port bits are used for what:
;
; A0 = Data 0, alternates input/output
; A1 = Data 1, alternates input/output
; A2 = Data 2, alternates input/output
; A3 = Data 3, alternates input/output
; A4 = Data 4, alternates input/output
; A5 = Data 5, alternates input/output
; A6 = Data 6, alternates input/output
; A7 = Data 7, alternates input/output
;
; B0 = Direction bit, always output
; B1 = Write strobe or ACK, always output
; B2 = Read stroke or ACK, always input
;
;----------------------------------------------------
; Bits in the B register
;
DIRECTION	equ	%00000001
PSTROBE		equ	%00000010
ACK		equ	%00000100
;
;----------------------------------------------------
; The KIM has a 6530 with the two I/O ports at $1700.
;
; Addresses of 6530 registers
;
PIABASE		equ	$1700
PIAREGA		equ	PIABASE		;data reg A
PIADDRA		equ	PIABASE+1	;data dir reg A
PIAREGB		equ	PIABASE+2	;data reg B
PIADDRB		equ	PIABASE+3	;data dir reg B
		code
		page
;*****************************************************
; This is the initialization function.  Call before
; doing anything else with the parallel port.
;
xParInit
;
; Set up the data direction register for port B so that
; the DIRECTION and PSTROBE bits are output.  Only touch
; the bits we're using; leave the rest as-is.
;
		lda	PIADDRB	;get current value
		and	#~ACK
		ora	#DIRECTION | PSTROBE
		sta	PIADDRB
;
		lda	#$ff
		sta	PIADDRA	;set data for write
;
; Now that the data is set, set the direction
; registers.  This prevents weird problems like
; driving lines to the wrong state.
;
		lda	PIAREGB
		and	#~(PSTROBE | ACK)
		ora	#DIRECTION
		sta	PIAREGB
		rts
		page
;*****************************************************
; This sets up for writing to the Arduino.  Sets up
; direction registers, drives the direction bit, etc.
;
xParSetWrite    lda	#$ff	;set bits for output
		sta	PIADDRA
;
; Set direction flag to output, clear ACK bit
;
		lda	PIAREGB
		and	#~(PSTROBE | ACK)
		ora	#DIRECTION
		sta	PIAREGB
		rts
		page
;*****************************************************
; This sets up for reading from the Arduino.  Sets up
; direction registers, clears the direction bit, etc.
;
xParSetRead     lda	#$00	;set bits for input
		sta	PIADDRA
;
; Set direction flag to input, clear ACK bit
;
		lda	PIAREGB
		and	#~(DIRECTION | PSTROBE | ACK)
		sta	PIAREGB
		rts
		page
;*****************************************************
; This writes a single byte to the Arduino.  On entry,
; the byte to write is in A.  This assumes ParSetWrite
; was already called.
;
; Destroys A, all other registers preserved.
;
; Write cycle:
;
;    1. Wait for other side to lower ACK.
;    2. Put data onto the bus.
;    3. Set DIRECTION and PSTROBE to indicate data
;       is valid and ready to read.
;    4. Wait for ACK line to go high, indicating the
;       other side has read the data.
;    5. Lower PSTROBE.
;    6. Wait for ACK to go low, indicating end of
;       transfer.
;
xParWriteByte	pha		;save data
Parwl22		lda	PIAREGB	;check status
		and	#ACK
		bne	Parwl22	;wait for ACK to go low
;
; Now put the data onto the bus
;
		pla
		sta	PIAREGA
;
; Raise the strobe so the Arduino knows there is
; new data.
;
		lda	PIAREGB
		ora	#PSTROBE
		sta	PIAREGB
;
; Wait for ACK to go high, indicating the Arduino has
; pulled the data and is ready for more.
;
Parwl33		lda	PIAREGB
		and	#ACK
		beq	Parwl33
;
; Now lower the strobe, then wait for the Arduino to
; lower ACK.
;
		lda	PIAREGB
		and	#~PSTROBE
		sta	PIAREGB
Parwl44		lda	PIAREGB
		and	#ACK
		bne	Parwl44
		rts
		page
;*****************************************************
; This reads a byte from the Arduino and returns it in
; A.  Assumes ParSetRead was called before.
;
; This does not have a time-out.
;
; Preserves all other registers.
;
; Read cycle:
;
;    1. Wait for other side to raise ACK, indicating
;       data is ready.
;    2. Read data.
;    3. Raise PSTROBE indicating data was read.
;    4. Wait for ACK to go low.
;    5. Lower PSTROBE.
;
xParReadByte    lda	PIAREGB
		and	#ACK	;is their strobe high?
		beq	xParReadByte	;nope, no data
;
; Data is available, so grab and save it.
;
		lda	PIAREGA
		pha
;
; Now raise our strobe (their ACK), then wait for
; them to lower their strobe.
;
		lda	PIAREGB
		ora	#PSTROBE
		sta	PIAREGB
Parrlp1		lda	PIAREGB
		and	#ACK
		bne	Parrlp1	;still active
;
; Lower our ack, then we’re done.
;
		lda	PIAREGB
		and	#~PSTROBE
		sta	PIAREGB
		pla
		rts
