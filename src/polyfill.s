;
; simple chunky polyfiller for 680x0 - all registers used (except a6)
; TODO:
;  + prestepping (subpixel)
;  - pipelining for 68060
;  - investigate FIX_BITS for 060, want more than 8 - not sure this works...
;  - reuse pixel loop from '.upper_right_y_triseg:'

;
; core GOA assembler definitions
;
GOA_PIXMAP_PALETTESIZE equ 256

;
; higher will cause problems with division (only < 68040????)
;
FIX_10_BITS        equ 10
FIX_10_BITS_ONE    equ (1<<FIX_BITS)
FIX_10_BITS_HALF   equ (1<<(FIX_BITS-1))
FIX_10_BITS_MASK   equ (FIX_BITS_ONE - 1)

FIX_BITS        equ 7
FIX_BITS_ONE    equ (1<<FIX_BITS)
FIX_BITS_HALF   equ (1<<(FIX_BITS-1))
FIX_BITS_MASK   equ (FIX_BITS_ONE - 1)


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



        rsreset
pf_side         rs.l 1
pf_dxdy_long    rs.l 1
pf_pres_long    rs.l 1
pf_xfix_long    rs.l 1
pf_xmid_long    rs.l 1
pf_xend_long    rs.l 1

pf_valid_up     rs.l 1
pf_dxdy_up      rs.l 1
pf_pres_up      rs.l 1
pf_xfix_up      rs.l 1

pf_valid_down   rs.l 1
pf_dxdy_down    rs.l 1
pf_pres_down    rs.l 1
pf_xfix_down    rs.l 1
pf_ffm_down     rs.l 1

pf_dxdy1        rs.l 1
pf_dxdy2        rs.l 1
pf_dxdy3        rs.l 1


        rsreset
pf_data_dxdy1        rs.l 1 ; short up
pf_data_dxdy2        rs.l 1 ; long
pf_data_dxdy3        rs.l 1 ; short down
pf_data_pmwidth      rs.l 1

pf_data_prestep      rs.l 1
pf_data_prestep_down rs.l 1



    section code

test:
    nop
;    move.l  #320,d3
    move.l  #2,d3
    move.l  #16,d0
    ;asl.l   d0,d3
    ;move.l  #$01020304,d1
;    move.l  #$0304,d1
 ;   move.l  #$0102,d2
    move.l #0,d1
    move.l #10, d2
;    move.l  d1,d2
;    asr.l   d0,d2
    asl.l   d0,d1

    divs.l    d3, d2:d1


    ;
    ; I simply don't know how to autofill the pointer to the buffer in asm
    ; However, this is not an issue as it will be supplied from C/C++
    ;

    lea     backbuffer,a0
    lea     backbuffer_image_data,a1
    move.l  a1, goa_pixmap_image(a0)
    
;    move.l  #255,d0
;    lea     backbuffer,a0
;    lea     v1_left,a1
;    lea     v2_left,a2
;    lea     v3_left,a3
;    lea     pf_debug_data, a6
;    bsr     _fp_poly_singlecolor

    lea     backbuffer,a0
    lea     v1_left_fp10,a1
    lea     v2_left_fp10,a2
    move.l  #255,d0
    bsr     _fp10_drawline

    lea     backbuffer,a0
    lea     v2_left_fp10,a1
    lea     v3_left_fp10,a2
    move.l  #255,d0
    bsr     _fp10_drawline

    lea     backbuffer,a0
    lea     v3_left_fp10,a1
    lea     v1_left_fp10,a2
    move.l  #255,d0
    bsr     _fp10_drawline




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


;
; d0 - color
;
; a0 - pointer to pixmap
; a1 - v1, fp: 22:10
; a2 - v2, fp: 22:10
;

_line_draw_singlecolor:
; ------------------------------------
;
; fp10_drawline - DDA Line Drawer (without anything fancy)
;
;   a0: pixmap
;   a1: p1 coordinate [x,y] values -> 32bit
;   a2: p2 coordinate [x,y] values -> 32bit
;   d6: color
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
_fp10_drawline:
    push    d2-d7/a1-a3
    move.l  #FIX_10_BITS, d7

    move.l  (a1)+,d1
    move.l  (a2)+,d3
    move.l  (a1)+,d2
    move.l  (a2)+,d4
    ;
    ; d1 = x1, fix point 22:10
    ; d2 = y1, fix point 22:10
    ; d3 = x2, fix point 22:10
    ; d4 = y2, fix point 22:10
    ;
    cmp.l   d4,d2   
    bmi     .y2_greater
    exg     d1,d3
    exg     d2,d4
.y2_greater:

    move.l  d2, d5
    move.l  d4, d6
    asr.l   d7, d5
    asr.l   d7, d6

    ;; y1 == y2 -> out
    cmp.l   d5,d6
    beq     .out

    move.l  d3, d5
    move.l  d4, d6
    sub.l   d1, d5
    bpl     .x_positive
    neg.l   d5
.x_positive:
    sub.l   d2, d6

    cmp.l   d5, d6
    bgt     .y_greater
    ;;  x greater
    move.l  d3, d5
    sub.l   d1, d5


    move.l  d6, d4  ; d4 used as loop register
    asr.l   d7, d4


    asl.l   d7, d5
    divs.l  d6, d5  
    ;
    ; d5 = dxdyfix
    ;
    asr.l   d7, d2
    move.l  goa_pixmap_image(a0),a3
    mulu.l  goa_pixmap_width(a0),d2
    add.l   d2, a3

    move.l  d1,d3
    add.l   d5,d3

    cmp.l   d1,d3
    bgt     .x_no_swap
    exg     d1,d3
.x_no_swap:
    ;
    ; register allocation
    ; d0 = color
    ; d1 = x1fix
    ; d2 = xpos - calculated
    ; d3 = x1fix, next
    ; d5 = dxdy
    ;
.y_loop_x_greater:
    move.l  d1, d2
    asr.l   d7, d2

    move.l  d3, d6
    asr.l   d7, d6
    sub.l   d2, d6
.ylx:
    move.b  d0,(a3,d2.l)
    addq.l  #1,d2
    subq.l  #1,d6
    bne     .ylx

    add.l   goa_pixmap_width(a0),a3
    add.l   d5, d1
    add.l   d5, d3
    subq.l  #1, d4
    bne     .y_loop_x_greater


    pop     d2-d7/a1-a3
    rts

.y_greater:
    ;; need to restore this, if negated - better just recalculate
    move.l  d3, d5
    sub.l   d1, d5

    ;
    ; d5 = dxfix
    ; d6 = dyfix

    move.l  d6, d4  ; d4 used as loop register
    asr.l   d7, d4


    asl.l   d7, d5
    divs.l  d6, d5  
    ;
    ; d5 = dxdyfix
    ;
    asr.l   d7, d2
    move.l  goa_pixmap_image(a0),a3
    mulu.l  goa_pixmap_width(a0),d2
    add.l   d2, a3
    ;
    ; register allocation
    ; d0 = color
    ; d1 = x1fix
    ; d2 = xpos - calculated
    ; d3
    ; d5 = dxdy
    ;
.y_loop_y_greater:
    move.l  d1, d2
    asr.l   d7, d2
    move.b  d0,(a3,d2.l)
    add.l   goa_pixmap_width(a0),a3
    add.l   d5, d1
    subq.l  #1, d4
    bne     .y_loop_y_greater


.out:
    pop     d2-d7/a1-a3
    rts

_fp10_drawline_old:

    ;; __regsused in VBCC doesn't work, manually pushing instead
    push    d2-d7/a1


    move.l  #FIX_10_BITS,d7

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
    asr.l   d7, d0
    sub.l   d1, d5  ;; dy, d5 = d3 - d1
    asr.l   d7, d2

    sub.l   d0, d2      ; d2 = dx, loop register


    ; register allocation
    ; d0 = x1
    ; d1 = y1
    ; d2 = x2
    ; d3 = y2
    ;
    move.l  d1, d4
    sub.l   d3, d4
    beq     .out_y

    move.l  d0, d5
    sub.l   d2, d5
    ;;
    ;; d5 == 0 -> vertical line
    ;;
    asl.l   d7, d4
    divs.l  d5, d4
    ;;
    ;; d4 = dxdya
    ;;

    asr.l   d7, d1
    move.l    goa_pixmap_image(a0), a1
    mulu.l    goa_pixmap_width(a0), d1
    add.l   d1, a1
    ;;
    ;; d0 = x1 (fix-point)
    ;; 
    ;; d4 = dx/dy
    ;;
    ;;

.loop_y:
    move.l  d0, d5          ;; this will not pipeline very well
    asr.l   d7, d5
    add.l   d4,d0
    move.b  d6,(a1, d5.l)
    add.l   goa_pixmap_width(a0), a1

    subq.l  #1, d3
    bne     .loop_y

 .out_y:
    ;;  restore and exist 
    pop     d2-d7/a1
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

    sub.l   d0, d4  ;; dx, d4 = d2 - d0
    bne     .do_x   ;; dx == 0, leave (dx == dy == 0)
    ;; restore and exist
    pop     d2-d7/a1
    rts

.do_x:
    move.l  d3, d5

    asr.l   d7, d0
    sub.l   d1, d5  ;; dy, d5 = d3 - d1
    asr.l   d7, d2

    sub.l   d0, d2      ; d2 = dx, loop register
    beq     .out_x

    asl.l   d7, d5
    divs.l  d4, d5      ;; d5 = dy / dx
    ;ext.l   d5

    move.l    goa_pixmap_image(a0), a1
    add.l     d0, a1      ;; smarter to use lea???
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
    asr.l   d7, d4
    add.l   d5, d1        ;; try pipeline

    mulu.l  goa_pixmap_width(a0), d4        ;; y * 320, 

    move.b  d6, (a1, d4.l)    ;; store pixel
                                ;; perhaps do "subq.l d2, 1"
    addq    #1, a1
    subq.l  #1, d2
    bne     .loop_x
.out_x:
    ;; restore and exist
    pop     d2-d7/a1
    rts






; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
; /////////////////////////////////////////////////////////////
_fp_dumb_drawline:

    ;; __regsused in VBCC doesn't work, manually pushing instead
    push    d2-d7/a1

    move.l  #FIX_10_BITS, d7

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

    ;; abs(dx) > abs(dy)      - the above is due to this
    cmp.l   d5, d4  
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
        
    asr.l   d7, d3
    asr.l   d7, d1
    sub.l   d1, d3      ; d3 = dy, loop register
    beq     .out_y
    asl.l   d7,d4
    divs.l  d5, d4      ;; d4 = dx / dy    d4 = d4 / d5

    mulu.l    goa_pixmap_width(a0), d1
    move.l    goa_pixmap_image(a0), a1
    add.l     d1, a1

    ;;
    ;; a0 = first scanline
    ;; d0 = x1 (fix-point)
    ;; d4 = y1 
    ;; d4 = dx/dy
    ;;

.loop_y:
    move.l  d0, d5          ;; this will not pipeline very well
    asr.l   d7, d5
    add.l   d4,d0
    move.b  d6,(a1, d5.l)
    add.l   goa_pixmap_width(a0), a1

    subq.l  #1, d3
    bne     .loop_y

 .out_y:
    ;;  restore and exist 
    pop     d2-d7/a1
    rts
;
;  dx > dy
;
.x_greater:
    ; register allocation
    ;
    ;   d0 = x1
    ;   d1 = y1
    ;   d2 = x2
    ;   d3 = y2
    ;   d4 = dx
    ;

    ;; make sure x2 > x1, we want dx positive
    cmp     d2, d0  ;; x1 > x2
    bgt     .noswap
    ;; TODO: swap
    exg     d0,d2       ;; swap x1 <-> x2
    exg     d1,d3       ;; swap y1 <-> y2
.noswap:
    move.l  d2, d4
    move.l  d3, d5

    sub.l   d0, d4  ;; dx, d4 = d2 - d0
    bne     .do_x   ;; dx == 0, leave (dx == dy == 0)
    ;; restore and exit
    pop     d2-d7/a1
    rts

.do_x:

    sub.l   d1, d5  ;; dy, d5 = d3 - d1

    asr.l   d7, d2
    asr.l   d7, d0

    sub.l   d0, d2      ; d2 = dx, loop register
    beq     .out_x

    asl.l   d7, d5
    divs.l  d4, d5      ;; d5 = dy / dx

    move.l    goa_pixmap_image(a0), a1
    add.l     d0, a1      ;; smarter to use lea???
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
    asr.l   d7, d4
    add.l   d5, d1        ;; try pipeline

    mulu.l  goa_pixmap_width(a0), d4        ;; y * 320, 
    move.b  d6, (a1, d4.l)    ;; store pixel
                                ;; perhaps do "subq.l d2, 1"
    addq    #1, a1
    subq.l  #1, d2
    bne     .loop_x
.out_x:
    ;; restore and exist
    pop     d2-d7/a1
   
    rts


; ------------------------------------
;
; Subpixel corrected single color triangle filler, no Z-buffer
;
; This version has correct interpolation
; TODO: 
;  - verify end-point for long edge
;  - verify when upper segment has zero scanlines (doesn't draw anything right now)
;  - check all loops for correct d6/d7 usage
; 
; Main thing:
; 1) Don't calculate DY in fix-point space and afterwards move back to int!
; 2) Use BNE not BPL
;
; d0: color
;
; a0: pointer to pixmap
; a1: v1, fp: 22:10
; a2: v2, fp: 22:10
; a3: v3, fp: 22:10
; a6: pointer to debug info (pf_xxx) result structure
;
;
; Note: This can probably be optimized further, as we can also use address registers 
;       for 'add.l' instruction in the inner loop - currently this is not done!
;
;
; ------------------------------------
_fp_poly_singlecolor:

    push    d2-d7/a4-a5
    ;
    ; TODO: adjust coords with 0.5, which is 'add.l #FIX_BITS_HALF, d1' - or leave this to the caller
    ;
    move.l vertex_y(a1), d1   
    move.l vertex_y(a2), d2
    move.l vertex_y(a3), d3   

    lea     polydata, a6

    ;; move the width of pixmap to poly-structure
    ;; this is 'cache optimization' as we only want the pf_data structure to be accessed during 
    ;; edge-loop interpolation
    move.l  goa_pixmap_width(a0),a5
    move.l  a5,pf_data_pmwidth(a6)


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
    ; coordinates sorted (a1,a2,a3 points correctly)
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
        
    ;;
    ;; todo pipe line this!!!  had a pipelined version but needed more clarity when debugging!!
    ;;

    ;;
    ;; Is this an issue on the 060, on < 030 this will cause division problem if shifted with 8 for numbers > 128
    ;;
    move.l #FIX_BITS, d6
    asl.l  d6,d1        ;;  8:8 fix point, doesn't work as the "sign" bit will be set for lines > 128px unless we can do long / long division
    asl.l  d6,d2
    asl.l  d6,d3
                        ;;  ((f1 << FIX_BITS) / f2);
    move.l (4,a3),d6
    sub.l  (4,a1),d6   ;; d6 = y3 - y1

    
    ;; 'divs.l   d4,d1' not supported in emulator
    ;; d1 = dxdy1 = (x2 - x1) / (y2 - y1)
    move.l vertex_y(a2),d7
    cmp.l  vertex_y(a1),d7
    ble    .skip_dxdy1
    divs.l d4,d1
.skip_dxdy1:


    cmp.l  #0, d6
    beq    .skip_dxdy2
    divs.l d6,d2       ;; d2 = dxdy2 = (x3 - x1) / (y3 - y1)
.skip_dxdy2:

    cmp.l  #0, d5
    beq    .skip_dxdy3
    divs.l d5,d3       ;; d3 = dxdy3 = (x3 - x2) / (y3 - y2)
.skip_dxdy3:

    ;;
    ;; calculate side, d6 - side: 0: left, 1: right
    ;;
    ;;  int32_t side = dxdy2 > dxdy1;
    moveq   #1, d6
    cmp.l   d1, d2
    bgt     .dxdy2_gt_dxdy1
    moveq   #0, d6
.dxdy2_gt_dxdy1:  

    ;; if (y1fix == y2fix)
    move.l  vertex_y(a1),d4
    cmp.l   vertex_y(a2),d4
    bne     .y1fix_ne_y2fix

    ;;   side = x1fix > x2fix;
    moveq   #1, d6
    move.l  vertex_x(a1),d4
    cmp.l   vertex_x(a2),d4
    bgt     .y1fix_ne_y2fix
    moveq   #0, d6
.y1fix_ne_y2fix:  
    ;;  TODO!!!
;    if (y2fix == y3fix)
;        side = x3fix > x2fix;

    cmp.l   #0,d6
    beq     .left_long_edge

;;
;; the code below works for long-edge on right-hand side!
;;
.right_long_edge:

    ;
    ; Save gradients
    ;
    move.l  d1,pf_data_dxdy1(a6)
    move.l  d2,pf_data_dxdy2(a6)
    move.l  d3,pf_data_dxdy3(a6)

    ;;
    ;; prestepping, long edge
    ;;      no prestepping: move.l  vertex_x(a1),d5              ;; d5 = xb, do this here as we skip the setup if zero height
    ;;
    ;; int32_t prestep = (1<<FIX_BITS) - fix_frac(y1fix);

    move.l  #FIX_BITS, d6

    move.l  vertex_y(a1),d7              ;; d0 = y1
    move.l  #FIX_BITS_ONE, d5           ;;  1 << FIX_BITS (i.e. 1 in Fixpoint)
    and.l   #FIX_BITS_MASK, d7          ;; mask out the fractional part of Y1
    sub.l   d7, d5                      ;; d5 = prestep (1.0 - fractional(y1)), adjustument
    move.l  d5, pf_data_prestep(a6)                      ;; save for later

    ;; xbfix = x1fix + fix_fix_mul(prestep, dxdyb);   // dxdyb = dxdy2
    ;;       =>  x1fix + (prestep * dxdyb) / (FIX_BITS_ONE) - division =  >> FIX_BITS, but '>>' is implementation specific (logical / arithmetic)

    muls    d2, d5                      ;; prestep * dxdyb (dxdyb = dxdy2)
    asr.l   d6, d5                      ;; fix_fix_mul = (x * y) / (fix_bits)  => arithmetic shift right
    add.l   vertex_x(a1),d5             ;; adjust starting point for long edge: xbfix, =  (x1 + fix_fix_mul(prestep, dxdyb))



    ;; get scanline (a4 = &pixmap->image[y1 * pixmap->width])

    move.l  vertex_y(a1),d7              ;; d0 = y1
    asr.l   d6, d7               ;; fixpoint correction 
    ;; can be optimized, but does not work in the emulator!!!
    mulu.l  goa_pixmap_width(a0),d7     ;; width * y1, this is always unsigned!
    move.l  goa_pixmap_image(a0),a4    
    add.l   d7, a4                      ;; a4 = pixmap->image + width * y1; (&pixmap->image[width * y1])
    ;; a4 now points to the corfect scanline


    ;; calc and check dy
    move.l  vertex_y(a2),d7
    move.l  vertex_y(a1),d4
    asr.l   d6, d4               ;; fixpoint correction 
    asr.l   d6, d7               ;; fixpoint correction 
    sub.l   d4,d7             ;; d7 = dy = y2 - y1 (still in fix point)
    beq     .skip_upper_right   
    ;; dy (d7) > 0


    move.l  vertex_x(a1),d4              ;; d4 = xafix
    ;; prestepping for d4 (xafix), d1 - gradient, d6 is prestep value (see above)
    muls    pf_data_prestep(a6), d1              ;; prestep * dxdya
    asr.l   d6, d1              ;; (prestep * dxdya) / FIX_BITS
    add.l   d1, d4              ;; x1fix + (prestep * dxdya) / FIX_BITS

  
    ;; d3, gradient, short lower edge, need to save this
    push    d3 
;
; Upper triangle segment including scanline
;
; register allcation
; d0, color
; d1, 
; d2, fix-bits
; d3, scratch - used for internal calculations 
; d4, short edge
; d5, long edge
; d6, scanloop-counter
; d7, scanline-counter
; 
; a0, pointer to pixmap
; a1, v1
; a2, v2
; a3, v3
; a4, scanline pointer
; a5, scanline + x1 -> first pixel pointer
; a6, prestepping value
;
    move.l #FIX_BITS, d2

.upper_right_y_triseg:
    ;; I've been testing a few ways in order to pipeline the loop better, but they all produced jagged edges
    ;; This scanline version produces by far the best results...

    move.l  d5, d6
    move.l  d4, d3              ; d4 is the short edge
    asr.l   d2, d6       ; can't do asr.l on address register... pity...
    asr.l   d2, d3
    move.l  a4, a5
    sub.l   d3,d6               ; d6 is loop
    add.l   d3,a5               ; a5 points at first pixel of scanline

    ;; THIS IS THE MASTER LOOP - I don't know how to make this any tighter..
.upper_right_y_scan:
    move.b  d0,(a5)+      ; this is 1 cycle slower then direct but pipeline is maintained
    subq.l  #1, d6
    bpl     .upper_right_y_scan
;;   this will just draw the edges!
;    move.b  d0,(a5)      
;    move.b  d0,(a5,d6.l)      

    ;; end of scanline here

    add.l   pf_data_dxdy1(a6),d4                   ;; xafix += dxdy1
    add.l   pf_data_dxdy2(a6),d5                   ;; xbfix += dxdy2      
;    add.l   goa_pixmap_width(a0),a4                 ;; advance next scanline
    add.l   pf_data_pmwidth(a6),a4

    subq.l  #1,d7
    bne     .upper_right_y_triseg

    pop     d3                      ;; restore lower short edge gradient

    move.l  d5,pf_xmid_long(a6)
    ;; lower right from here
.skip_upper_right:

    ; register allocation
    ; d0 - color
    ; d1 - free
    ; d2 - 
    ; d3 - 
    ; d4 - free
    ; d5 - long edge X coordinate
    ; d6 - free
    ; d7 - free
    ;
 
    ;; very little setup for second segment as we just continue
    move.l #FIX_BITS, d6
    move.l vertex_y(a3),d7
    move.l vertex_y(a2),d1
    asr.l  d6, d7           ;; fixpoint correction 
    asr.l  d6, d1           ;; fixpoint correction 
    sub.l  d1,d7                ;; d6 = dy = y3 - y2
    ;; Zero check (y3 - y2 == 0, skip!)
    beq    .skip_lower_right


    ;; prestepping of lower short edge
    move.l  vertex_y(a2),d1             ;; 
    move.l  #FIX_BITS_ONE, d4           ;;  1 << FIX_BITS (i.e. 1 in Fixpoint)
    and.l   #FIX_BITS_MASK, d1          ;; mask out the fractional part of Y1
    sub.l   d1, d4                      ;; d1 = prestep (1.0 - fractional(y1)), adjustument

    muls    pf_data_dxdy3(a6), d4                      ;; prestep * dxdyb (dxdyb = dxdy2)
    asr.l   d6, d4                      ;; fix_fix_mul = (x * y) / (fix_bits)  => arithmetic shift right
    add.l   vertex_x(a2),d4             ;; adjust starting point for short edge: xafix, =  (x2 + fix_fix_mul(prestep, dxdy3))




    ; register allocation
    ; d0 - color
    ; d1 - free/scratch
    ; d2 - fix bits
    ; d3 - 
    ; d4 - short edge X coordinate
    ; d5 - long edge  X coordinate
    ; d6 - scan loop counter (X)
    ; d7 - scanline counter (Y)
    ;

    move.l  #FIX_BITS, d2

.lower_right_y_triseg:
    move.l  d5, d6      ;; 
    move.l  d4, d1      ;; d4 is short edge, d1 was used for upper and is now free
    asr.l   d2, d6
    asr.l   d2, d1
    move.l  a4, a5
    sub.l   d1, d6
    add.l   d1, a5
.lower_right_y_scan:
    move.b  d0, (a5)+
    subq    #1, d6
    bpl     .lower_right_y_scan

;; end scanline, advance to next

    add.l   pf_data_dxdy3(a6),d4                   ;; xafix += dxdy3
    add.l   pf_data_dxdy2(a6),d5                   ;; xbfix += dxdy2      
    ;add.l   goa_pixmap_width(a0),a4                 ;; advance next scanline
    add.l   pf_data_pmwidth(a6),a4

    subq.l  #1,d7
    bne     .lower_right_y_triseg   ;; BNE or BPL??????
.skip_lower_right:

    ;; restore stack
    pop     d2-d7/a4-a5

    rts

;;
;; Long edge on the left
;;
.left_long_edge:

    ;  d1 - dxdy1, upper short
    ;  d2 - dxdy2, long edge
    ;  d3 - dxdy3, lower short

    move.l  d1,pf_data_dxdy1(a6)
    move.l  d2,pf_data_dxdy2(a6)
    move.l  d3,pf_data_dxdy3(a6)
    move.l  #FIX_BITS, d6

    ; Register allocation
    ;  d0 - color
    ;  d4 - short edge X-coord (set later)
    ;  d5 - long edge X-coord

    ;move.l  vertex_y(a1),d0              ;; d0 = y1
    ;move.l  vertex_x(a1),d5              ;; d5 = xb, do this here as we skip the setup if zero height

    ; subpixel correction on v1 for long edge
    ; this should be done regardless if upper or lower is segment


    ;; int32_t prestep = (1<<FIX_BITS) - fix_frac(y1fix);
    move.l  vertex_y(a1),d7              ;; d0 = y1
    move.l  #FIX_BITS_ONE, d5           ;;  1 << FIX_BITS (i.e. 1 in Fixpoint)
    and.l   #FIX_BITS_MASK, d7          ;; mask out the fractional part of Y1
    sub.l   d7, d5                      ;; d5 = prestep (1.0 - fractional(y1)), adjustument
    move.l  d5, d1                      ;; save for later

    ;; xbfix = x1fix + fix_fix_mul(prestep, dxdyb);   // dxdyb = dxdy2
    ;;       =>  x1fix + (prestep * dxdyb) / (FIX_BITS_ONE) - division =  >> FIX_BITS, but '>>' is implementation specific (logical / arithmetic)

    ;; prestep X1, long edge X-coord
    muls.l  pf_data_dxdy2(a6), d5                      ;; prestep * dxdya (dxdya = dxdy2)
    asr.l   d6, d5               ;; fix_fix_mul = (x * y) / (fix_bits)  => arithmetic shift right
    add.l   vertex_x(a1),d5             ;; adjust starting point for long edge: xbfix, =  (x1 + fix_fix_mul(prestep, dxdyb))

    ;; get scanline
    move.l  vertex_y(a1),d7            
    asr.l   d6, d7               ;; fixpoint correction 
    ;; can be optimized, but does not work in the emulator!!!
    mulu.l  goa_pixmap_width(a0),d7     ;; width * y1, this is always unsigned!
    move.l  goa_pixmap_image(a0),a4    
    add.l   d7, a4                      ;; a4 = pixmap->image + width * y1; (&pixmap->image[width * y1])

    ;; a4 now points to the corfect scanline

    move.l  vertex_y(a2),d7
    asr.l   d6, d7           ;; fixpoint correction 
    move.l  vertex_y(a1),d4                    ;; d6 = dy = y2 - y1 (still in fix point)
    asr.l   d6, d4           ;; fixpoint correction 

    sub.l   d4,d7
    beq     .skip_upper_left

    ;; Upper left segment here

    ;
    ; prestepping for short edge (xbfix)
    ;


    move.l  vertex_x(a1),d4     ;; d4 = xa, this is equal to d5 at this point (starting at same point)
    muls.l  pf_data_dxdy1(a6), d1              ;; prestep * dxdyb
    asr.l   d6, d1       ;; (prestep * dxdyb) / FIX_BITS
    add.l   d1, d4              ;; x1fix + (prestep * dxdyb) / FIX_BITS   

    ;;
    ;; d0 - color
    ;; d1 - fix bits
    ;; d2 - 
    ;; d4 - X-coord, left upper short edge X-coord
    ;; d5 - X-coord, right hand coord (long side), this will live through
    ;; d6 - dx, scan loop counter
    ;; d7 - dy, scanline loop counter   
    push    d3
    move.l  #FIX_BITS, d1
.upper_left_y_triseg:

    move.l  d5, d3              ; d5 is long edge (left side)
    move.l  d4, d6              ; d4 is the short edge
    asr.l   d1, d3
    asr.l   d1, d6
    move.l  a4, a5
    sub.l   d3,d6               ; d6 is loop
    add.l   d3,a5               ; a5 points at first pixel of scanline

    ;; fill scan line
.upper_left_y_scan:
    move.b  d0,(a5)+      
    subq.l  #1, d6
    bpl     .upper_left_y_scan
    ;; end of scan

    ;; advance left/right edges
    add.l   pf_data_dxdy1(a6),d4                   ;; right, xafix += dxdy1
    add.l   pf_data_dxdy2(a6),d5                   ;; left, xbfix += dxdy2      
;    add.l   goa_pixmap_width(a0),a4                 ;; advance next scanline
    add.l   pf_data_pmwidth(a6),a4

    subq.l  #1,d7
    bne     .upper_left_y_triseg    ;; XXXXXXX - bpl gives one more pixel... 
    pop     d3
    ;; end of upper triangle segment

.skip_upper_left:    

    ;; very little setup for second segment as we just continue

    move.l #FIX_BITS, d6

    move.l vertex_y(a3),d7
    move.l vertex_y(a2),d1
    asr.l  d6,d7           ;; fixpoint correction 
    asr.l  d6,d1
    sub.l  d1,d7                ;; d6 = dy = y3 - y2,
    ;; Zero check (y3 - y2 == 0, skip!)
    beq    .skip_lower_left

    ;;
    ;; d0 - color
    ;; d1 - scratch
    ;; d2 is long edge gradient
    ;; d3 is short edge gradient
    ;; d4 is short edge X-coord
    ;; d5 is long edge X-coord

    move.l  vertex_y(a2),d1
    move.l  #FIX_BITS_ONE, d4           ;;  1 << FIX_BITS (i.e. 1 in Fixpoint)
    and.l   #FIX_BITS_MASK, d1          ;; mask out the fractional part of Y2
    sub.l   d1, d4                      ;; d1 = prestep (1.0 - fractional(y21)), adjustument

;    move.l  d4,pf_data_prestep(a6)

 
    muls.l  pf_data_dxdy3(a6), d4                      ;; prestep * dxdyb (dxdyb = dxdy3)  
    asr.l   d6, d4               ;; fix_fix_mul = (x * y) / (fix_bits)  => arithmetic shift right

    add.l   vertex_x(a2),d4             ;; adjust starting point for short edge: xafix, =  (x2 + fix_fix_mul(prestep, dxdy3))

    move.l  #FIX_BITS, d2
    ;;
    ;; d1 is free to use at this stage - as it was upper short delta add (xafix)
    ;;
.lower_left_y_triseg:
    
    move.l  d4, d6     ; right
    move.l  d5, d1     ; left
    asr.l   d2, d6
    asr.l   d2, d1

    move.l  a4, a5
    sub.l   d1,d6
    add.l   d1,a5
    ;; scanline
.lower_left_y_scan:
    move.b  d0, (a5)+
    subq.l  #1, d6
    bpl     .lower_left_y_scan

    ;; end scanline, advance edges

    add.l   pf_data_dxdy3(a6),d4                   ;; right, xafix += dxdy3
    add.l   pf_data_dxdy2(a6),d5                   ;; left xbfix += dxdy2      
;    add.l   goa_pixmap_width(a0),a4                 ;; advance next scanline
    add.l   pf_data_pmwidth(a6),a4

    subq.l  #1,d7
    bne     .lower_left_y_triseg
    ;; end triangle segment
.skip_lower_left:

    ;; restore stack
    pop     d2-d7/a4-a5
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


    cnop 0,4
polydata: ds.b     4*32

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

v1_right_fp10:     dc.l    160<<FIX_10_BITS,  0<<FIX_10_BITS, 0
v2_right_fp10:     dc.l    100<<FIX_10_BITS, 80<<FIX_10_BITS, 0
v3_right_fp10:     dc.l    110<<FIX_10_BITS,140<<FIX_10_BITS, 0

;
; xx_left, will cause long-edge in polyfiller to be left
;

v1_left:     dc.l    160<<FIX_BITS,  0<<FIX_BITS, 0
v2_left:     dc.l    180<<FIX_BITS, 80<<FIX_BITS, 0
v3_left:     dc.l    110<<FIX_BITS,140<<FIX_BITS, 0

v1_left_fp10:     dc.l    160<<FIX_10_BITS,  0<<FIX_10_BITS, 0
v2_left_fp10:     dc.l    180<<FIX_10_BITS, 80<<FIX_10_BITS, 0
v3_left_fp10:     dc.l    110<<FIX_10_BITS,110<<FIX_10_BITS, 0


;;
;; test cases that have failed
;;

; FIXED: division by zero
v1_fail_a:     dc.l    160<<FIX_BITS, 90<<FIX_BITS, 0
v2_fail_a:     dc.l    240<<FIX_BITS, 90<<FIX_BITS, 0
v3_fail_a:     dc.l    216<<FIX_BITS,146<<FIX_BITS, 0

; FIXED: division by zero
v1_fail_b:     dc.l    160<<FIX_BITS,  90<<FIX_BITS, 0
v2_fail_b:     dc.l    216<<FIX_BITS,  33<<FIX_BITS, 0
v3_fail_b:     dc.l    239<<FIX_BITS,  90<<FIX_BITS, 0
 
; FIXED: no segment drawn, due to division problems => wrong side
v1_fail_c:     dc.l    $3240, $2d40, 0
v2_fail_c:     dc.l    $1602, $4993, 0
v3_fail_c:     dc.l    $0a40, $2d4f, 0

; no segment drawn, due to division problems => wrong side
v1_fail_d:     dc.l    $3240, $2d40, 0
v2_fail_d:     dc.l    $15de, $496f, 0
v3_fail_d:     dc.l    $0a40, $2d1c, 0

; line fp10 crash:
v1_fp10_fail_a:     dc.l    160 << FIX_10_BITS, 90  << FIX_10_BITS, 0
v2_fp10_fail_a:     dc.l    234 << FIX_10_BITS, 121  << FIX_10_BITS, 0
v3_fp10_fail_a:     dc.l    190  << FIX_10_BITS, 164  << FIX_10_BITS, 0


pf_debug_data: ds.b     4*32

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
