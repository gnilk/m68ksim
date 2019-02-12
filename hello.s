	section code

test:
	move.l  #0, d0
	move.l  #0, d1

	move.l  #160, d2
	move.l  #90, d3
	jsr interpolate

	move.l	#4, d3
.loop:
	move.l	#1, d0
	move.l  #2, d1
	add.l   d1, d0
	dbf		d3, .loop
	rts
func1:
	move.l  #4, d0
	move.l  #4, d1
	add.l   d1, d0
	rts
;
;
; a0: first byte of chunky image, assumed width is 320 byte (pixel)
; TODO:
;   a1: coordinate 1 values -> 32bit
;   a2: coordinate 2 values -> 32bit
;
;
interpolate:
	move.l 	d2, d4
	move.l  d3, d5
	sub.l   d0, d4	;; dx, d4 = d2 - d0
	sub.l   d1, d5  ;; dy, d5 = d3 - d1


	cmp.l	d5, d4	;; dx > dy
	bgt		.x_greater	
	;; TODO implement this	
	rts
.x_greater:
	
	cmp		d1, d3	;; y1 > y0
	bgt		.noswap
	;; TODO: swap
	nop
.noswap:
	asl.l   #7, d5		; 8:8 fixpoint (not enough???)
	asl.l   #7, d1		; 8:8 fixpoint (not enough???)
	sub.l   d0, d2      ; d2 = dx, loop register
	divs	d4, d5	;; d5 = dy / dx
	;;
	;; d0 - x1 coord
	;; d1 - y1 coord
	;; d2 - x2 coord
	;; d3 - y2 coord
	;;
	;; d5 = dy/dx
	;;

.loop:
	move.l  d1, d4
	asr.l   #7, d4
	muls.w	#320, d4		;; y * 320

;	move.b  #1, (a0, d4)	;; store pixel

	add.l 	d5, d1
	addq    #1, a0
	dbf     d2, .loop
	rts
