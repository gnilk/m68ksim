    section code

test:
    move.l  #$1000,a0
    move.l  #$deadbeef, d0
    move.l  #320*180,d6
    jsr     memset


    rts
.end_test:
    move.l  #$1000, a3
    move.l  #$1001, a4

    move.b   #1, (a3)
    move.b   #2, (a4)

    move.b   (a3), (a4)

    cmp.b   (a3), d7
    beq     .apa
    move.b  (a3),(a4)
.apa:

    move.l  #0, d7
.pointlp:
    move    d7,d0
    lsl.l   #3, d0
    move.l  #$1000,a0
    lea     p1, a1
    add.l   d0, a1
    lea     p2, a2
    add.l   d0, a2
    jsr     interpolate


    addq    #1, d7
    cmp     #32,d7
    bne     .pointlp
    rts
; ------------------------------------
;
; Version 1
;
; clear screen 320x180, 060 optimized
;
; a0: pointer to memory
; d0: value 
; d7: bytes
;
; ------------------------------------
memset:
    ;; setup address regs's so they occupy one complete cache line each
    lea.l   (16,a0),a1
    move.l  d0,d1
    lea.l   (32,a0),a2
    move.l  d0,d2
    lea.l   (48,a0),a3
    move.l  d0,d3

    lsr.l   #4, d6

    ;;
    ;;
    ;; pre-fetch and clear all cache lines
    ;;
    ;; 16 byte in four lines
    ;;
.loop:
    ;; clear 4 * 4 bytes
    move.l  d0,(a0)+
    move.l  d1,(a1)+
    move.l  d2,(a2)+
    move.l  d3,(a3)+
    ;; clear 4 * 4 bytes
    move.l  d0,(a0)+
    move.l  d1,(a1)+
    move.l  d2,(a2)+
    move.l  d3,(a3)+
    ;; clear 4 * 4 bytes
    move.l  d0,(a0)+
    move.l  d1,(a1)+
    move.l  d2,(a2)+
    move.l  d3,(a3)+
    ;; clear 4 * 4 bytes
    move.l  d0,(a0)+
    move.l  d1,(a1)+
    move.l  d2,(a2)+
    move.l  d3,(a3)+

    ;;
    ;; Advance four cache lines for each...
    ;;
    add.l   #64-16,a0
    add.l   #64-16,a1
    add.l   #64-16,a2
    add.l   #64-16,a3
    ;;
    ;; we have cleared 4*4*4 bytes -> 64 bytes
    ;;
    subq    #1, d6
    bne     .loop
    rts

; ------------------------------------
;
; Interpolate - DDA Line Drawer (without anything fancy)
;
;   a0: first byte of chunky image, assumed width is 320 byte (pixel)
;   a1: p1 coordinate [x,y] values -> 32bit
;   a2: p2 coordinate [x,y] values -> 32bit
;
; Considering keeping it fixpoint to this level!!
; We need some info in order to do subpixeling and stuff
;
; TODO:
;    - Make interface compatible with GOA
;      void drawline(GOA_PIXMAP8 *pixmap, float *p1, float *p2, int size, void *context)
;    - Need to figure out how to declare a struct
;   
;
interpolate:
    move.l  (a1)+,d0
    move.l  (a2)+,d2
    move.l  (a1)+,d1
    move.l  (a2)+,d3

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

    mulu    #320, d1
    add.l   d1, a0
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

    add.l   d0, a0      ;; smarter to use lea???
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

;
; Some data, 32 points
;
p1:
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
    dc.l    160, 90
p2:
    dc.l    200, 90
    dc.l    199, 97
    dc.l    196, 105
    dc.l    193, 112
    dc.l    188, 118
    dc.l    182, 123
    dc.l    175, 126
    dc.l    167, 129
    dc.l    160, 130
    dc.l    152, 129
    dc.l    144, 126
    dc.l    137, 123
    dc.l    131, 118
    dc.l    126, 112
    dc.l    123, 105
    dc.l    120, 97
    dc.l    120, 90
    dc.l    120, 82
    dc.l    123, 74
    dc.l    126, 67
    dc.l    131, 61
    dc.l    137, 56
    dc.l    144, 53
    dc.l    152, 50
    dc.l    160, 50
    dc.l    167, 50
    dc.l    175, 53
    dc.l    182, 56
    dc.l    188, 61
    dc.l    193, 67
    dc.l    196, 74
    dc.l    199, 82
