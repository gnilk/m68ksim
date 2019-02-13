    section code

test:
    move.l  $1000,a0
    move.l  #160, d0
    move.l  #80, d1

    move.l  #160, d2
    move.l  #10, d3
    jsr interpolate


    move.l  $1000,a0
    move.l  #160, d0
    move.l  #80, d1

    move.l  #300, d2
    move.l  #80, d3
    jsr interpolate

    move.l  $1000,a0
    move.l  #160, d0
    move.l  #80, d1

    move.l  #260, d2
    move.l  #40, d3
    jsr interpolate


    move.l  #4, d3
.loop:
    move.l  #1, d0
    move.l  #2, d1
    add.l   d1, d0
    dbf     d3, .loop
    rts
func1:
    move.l  #4, d0
    move.l  #4, d1
    add.l   d1, d0
    rts
; ------------------------------------
;
; a0: first byte of chunky image, assumed width is 320 byte (pixel)
; TODO:
;   d0/d1: p1 coordinate 1 values -> 32bit
;   d2/d3: p2 coordinate 2 values -> 32bit
;
;
interpolate:
    move.l  d2, d4
    move.l  d3, d5
    sub.l   d0, d4  ;; dx, d4 = d2 - d0

    bpl     .x_positive ;; can do bpl.b +2, as neg.l d4 is two bytes
    neg.l  d4
.x_positive:

    sub.l   d1, d5  ;; dy, d5 = d3 - d1
    bpl     .y_positive
    neg.l   d5
.y_positive:
    cmp.l   d5, d4  ;; abs(dx) > abs(dy)
    bgt     .x_greater  
    ;; TODO dy == 0, leave
    cmp.l   d1, d3  ;; p1[1] > p2[2]
    bgt     .y2_greater
    exg     d0,d2       ;; swap x1 <-> x2
    exg     d1,d3       ;; swap y1 <-> y2
.y2_greater:
    move.l  d2, d4
    move.l  d3, d5
    
    sub.l   d0, d4  ;; dx, d4 = d2 - d0
    sub.l   d1, d5  ;; dy, d5 = d3 - d1
        
    asl.l   #7, d4      ; 8:8 fixpoint (not enough???)
    asl.l   #7, d0      ; 8:8 fixpoint (not enough???)
    sub.l   d1, d3      ; d3 = dy, loop register
    divs    d5, d4      ;; d4 = dx / dy
    ext.l   d4
    ;;
    ;; d0 = x1 (fix-point)
    ;; 
    ;; d4 = dx/dy
    ;;
    ;;

.loop_y:
    move.l  d0, d5          ;; this will not pipeline very well
    asr.l   #7, d5
    add.l   d4,d0
    move.b  #255,(a0, d5.l)
    add.l   #320, a0
    dbf     d3, .loop_y
    ;;  dxdya     
    rts
;
;  dx > dy
;
.x_greater:
    ;; make sure x2 > x1, we want dx positive
    cmp     d0, d2  ;; x1 > x2
    bgt     .noswap
    ;; TODO: swap
    exg     d0,d2       ;; swap x1 <-> x2
    exg     d1,d3       ;; swap y1 <-> y2
.noswap:
    move.l  d2, d4
    move.l  d3, d5

    sub.l   d0, d4  ;; dx, d4 = d2 - d0
    bne     .do_x   ;; dx == 0, leave (dx == dy == 0)
    rts
.do_x:

    sub.l   d1, d5  ;; dy, d5 = d3 - d1
    asl.l   #7, d5      ; 8:8 fixpoint (not enough???)
    asl.l   #7, d1      ; 8:8 fixpoint (not enough???)
    sub.l   d0, d2      ; d2 = dx, loop register
    divs    d4, d5      ;; d5 = dy / dx
    ext.l   d5
    ;;
    ;; d0 - x1 coord
    ;; d1 - y1 coord
    ;; d2 - x2 coord
    ;; d3 - y2 coord
    ;;
    ;; d5 = dy/dx
    ;;

.loop_x:
    move.l  d1, d4
    asr.l   #7, d4
    add.l   d5, d1        ;; try pipeline

    mulu    #320, d4        ;; y * 320, this can probably be removed. d4 & 0xffff00 + d4 >> 2    x*320 = (x<<8) + (x<<2)

    move.b  #255, (a0, d4.l)    ;; store pixel
                                ;; perhaps do "subq.l d2, 1"
    addq    #1, a0
    dbf     d2, .loop_x
    rts
