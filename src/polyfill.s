
;
; core GOA assembler definitions
;
GOA_PIXMAP_PALETTESIZE equ 256

;
; higher will cause problems with division
;
FIX_BITS equ 7


push    macro
        movem.l \1,-(a7)
        endm

pop     macro
        movem.l (a7)+,\1
        endm


;
; GOA_RGBA, see pixmap.h
;
;typedef struct
;{
;    BYTE r,g,b,a;
;} GOA_RGBA;
;

        rsreset
vertex_x            rs.l 1
vertex_y            rs.l 1
vertex_z            rs.l 1

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

    move.l  #4, d0
    move.l  #2, d1
    sub.l   d1, d0


    move.l  #2, d0
    move.l  #4, d1
    sub.l   d1, d0

    ;
    ; I simply don't know how to autofill the pointer to the buffer in asm
    ; However, this is not an issue as it will be supplied from C/C++
    ;
    lea     backbuffer,a0
    lea     backbuffer_image_data,a1
    move.l  a1, goa_pixmap_image(a0)

    lea     backbuffer,a0
    lea     v1_right,a1
    lea     v2_right,a2
    lea     v3_right,a3
    bsr     drawflat

;    lea     backbuffer,a0
;    lea     v1_left,a1
;    lea     v2_left,a2
;    lea     v3_left,a3
;    bsr     drawflat

endtest:
    rts

;
; a0: pointer to pixmap data
;
testpixmap:
    move.l  #100,d1
    move.l  goa_pixmap_image(a0),a1
.loop:
    move.b  #255,(a1)
    add.l   goa_pixmap_width(a0),a1
    addq.l  #1,a1
    subq.l  #1,d1
    bne     .loop
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
; NOTE: the number of FIX_POINT_BITS is critical, 6 is too low
;
;
; v1:     dc.l    160,  0, 0
; v2:     dc.l    100, 80, 0
; v3:     dc.l    110,140, 0
;
;
;
; ------------------------------------
drawflat:
    ;
    ; NOTE: this can be pre-calculated for poly streaming
    ;

    move.l vertex_y(a1), d1   
    move.l vertex_y(a2), d2
    move.l vertex_y(a3), d3   


;    if (y1 > y2) {
;        swap(v1, v2);
;    }
    move.l vertex_y(a1), d1   
    cmp.l  vertex_y(a2), d1     ;; effectively: y1 - y2, which is negative if y2 > y1
    bmi     .no_swap_y1_y2
    exg    a1,a2
    move.l vertex_y(a1), d1
.no_swap_y1_y2:
;    if (y1 > y3) {
;        swap(v1, v3);
;    }
    cmp.l  vertex_y(a3), d1
    bmi     .no_swap_y1_y3
    exg    a1,a3
.no_swap_y1_y3:
;    if (y2 > y3) {
;        swap(v2, x3);
;    }
    move.l vertex_y(a2), d1
    cmp.l  vertex_y(a3), d1
    bmi     .no_swap_y2_y3
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
    ;; the above works for the test vertices
    
slopecalc:
    
    ;;
    ;; todo pipe line this!!!  had a pipelined version but needed more clarity when debugging!!
    ;;

    ;;
    ;; Is this an issue on the 060, on < 030 this will cause division problem if shifted with 8 for numbers > 128
    ;;

    asl.l  #FIX_BITS,d1        ;;  8:8 fix point, doesn't work as the "sign" bit will be set for lines > 128px unless we can do long / long division
    asl.l  #FIX_BITS,d2
    asl.l  #FIX_BITS,d3
                        ;;  ((f1 << FIX_BITS) / f2);
    move.l (4,a3),d6
    sub.l  (4,a1),d6   ;; d6 = y3 - y1

    ;
    ; not supported in emulator
    ; divs.l   d4,d1       ;; d1 = dxdy1 = (x2 - x1) / (y2 - y1)
    divs   d4,d1
    ext.l  d1

    divs   d6,d2       ;; d2 = dxdy2 = (x3 - x1) / (y3 - y1)
    ext.l  d2

    divs   d5,d3       ;; d3 = dxdy3 = (x3 - x2) / (y3 - y2)
    ext.l  d3

sidecalc:

    moveq   #1, d0
    cmp.l  d1, d2
    bgt     .dxdy2_gt_dxdy1
    moveq   #0, d0
.dxdy2_gt_dxdy1:  

    ;; if (y1fix == y2fix)
    move.l  vertex_y(a1),d4
    cmp.l   vertex_y(a2),d4
    bne     .y1fix_ne_y2fix

    ;;   side = x1fix > x2fix;
    moveq   #1, d0
    move.l  vertex_x(a1),d4
    cmp.l   vertex_x(a2),d4
    bgt     .y1fix_ne_y2fix
    moveq   #0, d0
.y1fix_ne_y2fix:  
    ;;  TODO!!!
;    if (y2fix == y3fix)
;        side = x3fix > x2fix;

    cmp.l   #0,d0
    beq     .left_long_edge

;;
;; the code below works for long-edge on right-hand side!
;;
.right_long_edge:
    ;; 
    ;;
    ;; TODO: Pipeline this properly
    ;;
    move.l  vertex_y(a1),d0              ;; d0 = y1
    move.l  vertex_x(a1),d5              ;; d5 = xb, do this here as we skip the setup if zero height

    ;; get scanline
    asr.l   #FIX_BITS, d0               ;; fixpoint correction 
    ;; can be optimized, but does not work in the emulator!!!
    mulu    goa_pixmap_width(a0),d0     ;; width * y1, this is always unsigned!
    move.l  goa_pixmap_image(a0),a4    
    add.l   d0, a4                      ;; a4 = pixmap->image + width * y1; (&pixmap->image[width * y1])

    ;; a4 now points to the corfect scanline

    move.l  vertex_x(a1),d4              ;; d4 = xa


    ;; get the first scanline, part of this can be moved to where we dig out 'y1'
    move.l  vertex_y(a1),d0      
    move.l  vertex_y(a2),d6
    sub.l   d0,d6                ;; d6 = dy = y2 - y1 (still in fix point)

    asr.l   #FIX_BITS, d6           ;; fixpoint correction 
    beq     .skip_upper_right

    ;;
    ;; d5 is right hand coord (long side), this will live through
    ;; d2 is right hand add (long side)
    ;;
    ;; d4 is left (upper portion)

    push    d3
.upper_right_y_triseg:
    ;; I've been testing a few ways in order to pipeline the loop better, but they all produced jagged edges
    ;; This scanline version produces by far the best results...
    move.l  d5, d3
    move.l  d4, d0
    asr.l   #FIX_BITS, d3
    asr.l   #FIX_BITS, d0

.upper_right_y_scan:
    move.b  #255,(a4,d0.l)
    addq.l  #1,d0
    cmp.l   d3,d0
    ble     .upper_right_y_scan
    ;; end of scanline here

    add.l   d1,d4                   ;; xafix += dxdy1
    add.l   d2,d5                   ;; xbfix += dxdy2      
    add.l   #320,a4                 ;; advance next scanline
    subq.l  #1,d6
    bne     .upper_right_y_triseg
    pop     d3

    ;; lower right from here
.skip_upper_right:
    ;; very little setup for second segment as we just continue
    move.l vertex_y(a3),d6
    move.l  vertex_y(a2),d0
    sub.l  d0,d6                ;; d6 = dy = y3 - y2
    asr.l  #FIX_BITS, d6           ;; fixpoint correction 
    ;; Zero check (y3 - y2 == 0, skip!)
    beq    .skip_lower_right

    ;move.l vertex_x(a2),d4              ;; d4 = xa
    ;
    ; d5 -> xb, stays the same
    ;
.lower_right_y_triseg:
    ;;
    ;; d1 is free to use at this stage - as it was upper short delta add (xafix)
    ;;
    move.l  d5, d1
    move.l  d4, d0
    asr.l   #FIX_BITS, d1
    asr.l   #FIX_BITS, d0
.lower_right_y_scan:
    move.b  #255, (a4,d0.l)
    addq.l  #1,d0
    cmp.l   d1,d0
    ble     .lower_right_y_scan

;; end scanline, advance to next

    add.l   d3,d4                   ;; xafix += dxdy3
    add.l   d2,d5                   ;; xbfix += dxdy2      
    add.l   #320,a4                 ;; advance next scanline
    subq.l  #1,d6
    bpl     .lower_right_y_triseg   ;; BNE or BPL??????
.skip_lower_right:
    rts
;;
;; Long edge on the left
;;

.left_long_edge:

leftedge:
    move.l  vertex_y(a1),d0              ;; d0 = y1
    move.l  vertex_x(a1),d5              ;; d5 = xb, do this here as we skip the setup if zero height

    ;; get scanline
    asr.l   #FIX_BITS, d0               ;; fixpoint correction 
    ;; can be optimized, but does not work in the emulator!!!
    mulu    goa_pixmap_width(a0),d0     ;; width * y1, this is always unsigned!
    move.l  goa_pixmap_image(a0),a4    
    add.l   d0, a4                      ;; a4 = pixmap->image + width * y1; (&pixmap->image[width * y1])

    ;; a4 now points to the corfect scanline

    move.l  vertex_x(a1),d4              ;; d4 = xa, this is actually equal to d5 at this point (starting at same point)



    move.l  vertex_y(a1),d0      
    move.l  vertex_y(a2),d6
    sub.l   d0,d6                ;; d6 = dy = y2 - y1 (still in fix point)
upperleft:
    asr.l   #FIX_BITS, d6           ;; fixpoint correction 
    beq     .skip_upper_left
    ;;
    ;; d5 is right hand coord (long side), this will live through
    ;; d2 is right hand add (long side)
    ;;
    ;; d4 is left (upper portion)
    push    d3
.upper_left_y_triseg:

    move.l  d4,d3    ; right edge
    move.l  d5,d0    ; left
    asr.l   #FIX_BITS, d0
    asr.l   #FIX_BITS, d3
    ;; fill scan line
.upper_left_y_scan:
    move.b  #255,(a4,d0.l)      ;; THIS IS CACHE UNFRIENDLY
    addq.l  #1,d0
    cmp.l   d3, d0
    ble     .upper_left_y_scan
    ;; end of scan

    ;; advance left/right edges
    add.l   d1,d4                   ;; right, xafix += dxdy1
    add.l   d2,d5                   ;; left, xbfix += dxdy2      
    add.l   #320,a4                 ;; advance next scanline

    subq.l  #1,d6
    bne     .upper_left_y_triseg
    pop     d3
    ;; end of upper triangle segment

.skip_upper_left:    
    ;; very little setup for second segment as we just continue
    move.l vertex_y(a3),d6
    move.l vertex_y(a2),d0
    sub.l  d0,d6                ;; d6 = dy = y3 - y2,
    asr.l  #FIX_BITS, d6           ;; fixpoint correction 
    ;; Zero check (y3 - y2 == 0, skip!)
    beq    .skip_lower_left

    ;;
    ;; d1 is free to use at this stage - as it was upper short delta add (xafix)
    ;;
.lower_left_y_triseg:
    
    move.l  d4, d1     ; right
    asr.l   #FIX_BITS, d1
    move.l  d5, d0     ; left
    asr.l   #FIX_BITS, d0
    ;; do scanline
.lower_left_y_scan:
    move.b  #255, (a4,d0.l)
    addq.l  #1,d0
    cmp.l   d1,d0
    ble     .lower_left_y_scan

    ;; end scanline, advance edges

    add.l   d3,d4                   ;; right, xafix += dxdy3
    add.l   d2,d5                   ;; left xbfix += dxdy2      
    add.l   #320,a4                 ;; advance next scanline
    subq.l  #1,d6
    bne     .lower_left_y_triseg
    ;; end triangle segment
.skip_lower_left:


end_of_tri:
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

    MakePixmap  backbuffer,320,180, backbuffer_image_data


    ; make sure we are 32bit aligned
    cnop 0,4

;
; three vertices
;
; Note: vertices coming in are fixpoint 24:8
;

;
; xx_right, will cause long-edge in polyfiller to be right
;

v1_right:     dc.l    160<<FIX_BITS,  0<<FIX_BITS, 0
v2_right:     dc.l    100<<FIX_BITS, 80<<FIX_BITS, 0
v3_right:     dc.l    110<<FIX_BITS,140<<FIX_BITS, 0

;
; xx_left, will cause long-edge in polyfiller to be left
;

v1_left:     dc.l    160<<FIX_BITS,  0<<FIX_BITS, 0
v2_left:     dc.l    200<<FIX_BITS, 80<<FIX_BITS, 0
v3_left:     dc.l    110<<FIX_BITS,140<<FIX_BITS, 0


;v1:     dc.l    160,  0, 0
;v2:     dc.l    100, 80, 0
;v3:     dc.l    110,140, 0


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


backbuffer_image_data:  ds.b 320*180
