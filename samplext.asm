;=====================================================
; A sample extension for the Extended KIM monitor.
; This is a very simple example of how to write an
; extension (adding a new command) for the 
; Extended KIM monitor.
;
; How can you test this?  Easy.  First, use the "?"
; command in the extended monitor and verify the
; "Z" command is not listed, then load the binary
; version of this file.  Do "?" again and you'll see
; the new command has been added and can be used.
;
; 12/26/2015 - Bob Applegate, bob@corshamtech.com
; 09/29/2021 - Bob Applegate
;		Minor cleanup
;
; Consider buying a KIM-1 expansion board or a 
; KIM Clone computer from us:
;
;    www.corshamtech.com
;
;=====================================================
;
; First, define some common ASCII characters
;
LF		equ	$0a
CR		equ	$0d
;
		include	"xkim.inc"
;
; There are more vectors but I didn't need them
;
;=====================================================
; The actual sample
;
		code
		org	ExtensionAddr
;
; Set up the pointer to our sample extension...
;
		dw	Extension
;
; This is the table of commands being added.  Each
; entry has exactly five bytes:
;
;    Single character command
;    Address of code for this command
;    Descriptive text for this command
;
; After the last entry, the next byte must be zero
; to indicate the end of the table.
;
		org	$0400
Extension	db	'Z'	;adding the 'Z' command
		dw	zCode	;pointer to code
		dw	zHelp	;pointer to help
;
		db	0	;END OF EXTENSIONS
;
; The descriptive text...
;
zHelp		db	"Z ........... Describe a zoo",0
;
; And the actual code...
;
zCode		jsr	putsil	;call display function
		db	CR,LF
		db	"A Zoo is a place with "
		db	"lots of animals."
		db	CR,LF,0
		jmp	extKIM	;return to Extended KIM
