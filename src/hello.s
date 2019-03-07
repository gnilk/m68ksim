
;
; core GOA assembler definitions
;
GOA_PIXMAP_PALETTESIZE equ 256

;
; GOA_RGBA, see pixmap.h
;
;typedef struct
;{
;    BYTE r,g,b,a;
;} GOA_RGBA;
;

        rsreset
goa_rgba_r          rs.b 1  
goa_rgba_g          rs.b 1  
goa_rgba_b          rs.b 1  
goa_rgba_a          rs.b 1  

;
; GOA_PIXMAP8, see pixmap.h
;
;typedef struct
;{
;    int  width,height;
;    int  flags;
;    int  *ytab;
;    GOA_ZTYPE  *zbuffer;
;    BYTE *image;    // 8bit index palette image
;    void *reserved;
;    int num_refs;    
;    // Moved to the end as this makes the general header fully transparent between types...
;    GOA_RGBA palette[GOA_PIXMAP_PALETTESIZE];
;} GOA_PIXMAP8;
;
;
        rsreset
goa_pixmap_width    rs.l 1
goa_pixmap_height   rs.l 1
goa_pixmap_flags    rs.l 1
goa_pixmap_ytab     rs.l 1  ; pointer
goa_pixmap_zbuffer  rs.l 1  ; pointer
goa_pixmap_image    rs.l 1  ; pointer
goa_pixmap_reserved rs.l 1  ; pointer
goa_pixmap_num_refs rs.l 1  ; pointer
goa_pixmap_palette  rs.l GOA_PIXMAP_PALETTESIZE  ; array of GOA_RGBA

    section code

test:
;    move.l #$12345678,d0
;    move16 (a1)+,(a0)+


    lea     backbuffer,a0
    move.l  goa_pixmap_width(a0),d0
    move.l  goa_pixmap_height(a0),d1

    move.l  #$123, d0
    asr.l   #8, d0

    move.l  #$1000,a0
    move.l  #$1010,a1
    move.l  #$1,d4
    move.l  #$2,d0


    move.b  #1,$1000
    move.b  #2,$1001
    move.b  #0,$1010
    move.b  #0,$1011
    move.b  (a0,d4), (a1,d0)

    move.l    #$ff,d5
    add.b   (a0,d4),d5

filltest:
    move.l  #$1000,a0
    move.l  #$deadbeef, d0
    move.l  #256,d6
    jsr     memset

    move.l  #$1100,a0
    move.l  #$1000,a1
    move.l  #$deadbeef, d0
    move.l  #256,d6
    jsr     memcpy32

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
; Fill Poly
;
;
; a0: pointer to pixmap
; a1: v1, fp: 24:8
; a2: v2, fp: 24:8
; a3: v3, fp: 24:8
;
; ------------------------------------
drawflat:
    ;
    ; NOTE: this can be pre-calculated for poly streaming
    ;
    move.l (4,a1), d1
    cmp.l  (4,a2), d1
    bgt     .no_swap_y1_y2
    exg    a1,a2
    move.l (4,a1), d1
.no_swap_y1_y2:
    cmp.l  (4,a3), d1
    bgt     .no_swap_y1_y3
    exg    a1,a3
.no_swap_y1_y3:
    move.l (4,a2), d1
    cmp.l  (4,a3), d1
    bgt     .no_swap_y2_y3
    exg    a2, a3
.no_swap_y2_y3:
    ;
    ; coordinates sorted
    ;

    ;
    ; slope calculation, this should be pipelined ok
    ;

    move.l (0,a2),d1
    move.l (0,a3),d2
    sub.l  (0,a1),d1    ;; d1 = (x2 - x1)
    move.l (0,a3),d3
    sub.l  (0,a1),d2    ;; d2 = (x3 - x1)
    sub.l  (0,a2),d3    ;; d3 = (x3 - x2)

    move.l (4,a2), d4
    move.l (4,a3), d5   
    sub.l  (4,a1), d4   ;; y2-y1
    sub.l  (4,a2), d5   ;; y3-y2
    move.l (4,a3), d6
    divs   d4, d1       ;; d1 = (x2 - x1) / (y2 - y1)
    sub.l  (4,a1),d6
    divs   d5, d3       ;; d3 = (x3 - x2) / (y3 - y2)
    divs   d6, d2       ;; d2 = (x3 - x1) / (y3 - y1)

    

    rts


; ------------------------------------
;
; Version 2
;
; clear screen 320x180, 060 optimized
;
; a0: pointer to memory
; d0: value 
; d7: bytes
;
; ------------------------------------
memcpy32:
    lsr.l   #4, d7
.loop:
    move16 (a1)+,(a0)+
    subq.l #1, d7
    bne    .loop


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

    lsr.l   #6, d6

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
        
    asl.l   #8, d4      ; 8:8 fixpoint (not enough???)
    asl.l   #8, d0      ; 8:8 fixpoint (not enough???)
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
    asr.l   #8, d5
    add.l   d4,d0
    move.b  #255,(a0, d5.l)
    add.l   #320, a0
    subq.l  #1, d3
    bne     .loop_y
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
    asl.l   #8, d5      ; 8:8 fixpoint (not enough???)
    asl.l   #8, d1      ; 8:8 fixpoint (not enough???)
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
    asr.l   #8, d4
    add.l   d5, d1        ;; try pipeline

    mulu    #320, d4        ;; y * 320, 

    move.b  #255, (a0, d4.l)    ;; store pixel
                                ;; perhaps do "subq.l d2, 1"
    addq    #1, a0
    subq.l  #1, d2
    bne     .loop_x
    rts

;
; declare a texture
;
MakePixmap  Macro ;
\1:          
\1_width    dc.l    \2
\1_height   dc.l    \3
\1_flags    dc.l    0
\1_ytab     dc.l    0
\1_zbuffer  dc.l    0
\1_image    dc.l    \4     
\1_reserved dc.l    0     
\1_num_refs dc.l    0
\1_palette  ds.b    256*4     
            Endm

    MakePixmap  backbuffer,320,180,backbuffer_image_data


backbuffer_image_data: ds.b 320*180
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
