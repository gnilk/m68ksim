	section code

test:
	jsr func1

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
