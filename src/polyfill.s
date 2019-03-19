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


    section code

test:
    nop

;dxdy1: fffeaaab:0
;dxdy2: ffffff81:ffffff81
    move.l  #$fffeaaab,d1
    move.l  #$ffffff81,d2

    moveq   #1, d6
    cmp.l   d1, d2
    bgt     .dxdy2_gt_dxdy1
    moveq   #0, d6
.dxdy2_gt_dxdy1:  

    move.l  #$0,d1
    move.l  #$ffffff81,d2

    moveq   #1, d6
    cmp.l   d1, d2
    bgt     .dxdy2_gt_dxdy1_b
    moveq   #0, d6
.dxdy2_gt_dxdy1_b:  


    move.l  #$2d,d4
    move.l  #$fffffe51,d3
    muls.l  d3, d4                      ;; prestep * dxdyb (dxdyb = dxdy3)  
    asr.l   #FIX_BITS, d4               ;; fix_fix_mul = (x * y) / (fix_bits)  => arithmetic shift right
    ;;             C          asm
    ;; ffm....: ffffff02 : ffffff01
    ;;
    ;;


    move.l #$1234,d0
    and.l  #$ff,d0

    ;
    ; I simply don't know how to autofill the pointer to the buffer in asm
    ; However, this is not an issue as it will be supplied from C/C++
    ;

    lea     backbuffer,a0
    lea     backbuffer_image_data,a1
    move.l  a1, goa_pixmap_image(a0)
    move.l  #255,d0
    lea     backbuffer,a0
    lea     v1_fail_d,a1
    lea     v2_fail_d,a2
    lea     v3_fail_d,a3
    lea     pf_debug_data, a6
    bsr     _fp_poly_singlecolor_dbg

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
; a1: v1, fp: 24:8
; a2: v2, fp: 24:8
; a3: v3, fp: 24:8
; a6: pointer to debug info (pf_xxx) result structure
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
_fp_poly_singlecolor_dbg:

    push    d2-d7/a4-a5
    ;
    ; TODO: adjust coords with 0.5, which is 'add.l #FIX_BITS_HALF, d1' - or leave this to the caller
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

    asl.l  #FIX_BITS,d1        ;;  8:8 fix point, doesn't work as the "sign" bit will be set for lines > 128px unless we can do long / long division
    asl.l  #FIX_BITS,d2
    asl.l  #FIX_BITS,d3
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

    move.l  d1,pf_dxdy1(a6)
    move.l  d2,pf_dxdy2(a6)
    move.l  d3,pf_dxdy3(a6)
    

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



    move.l  #1,pf_side(a6)

    ; Register allocation
    ;  d1 - gradient, upper short
    ;  d2 - gradient, long edge
    ;  d3 - gradient, lower short
    ;

    ;;
    ;; prestepping, long edge
    ;;      no prestepping: move.l  vertex_x(a1),d5              ;; d5 = xb, do this here as we skip the setup if zero height
    ;;
    ;; int32_t prestep = (1<<FIX_BITS) - fix_frac(y1fix);

    move.l  vertex_y(a1),d7              ;; d0 = y1
    move.l  #FIX_BITS_ONE, d5           ;;  1 << FIX_BITS (i.e. 1 in Fixpoint)
    and.l   #FIX_BITS_MASK, d7          ;; mask out the fractional part of Y1
    sub.l   d7, d5                      ;; d5 = prestep (1.0 - fractional(y1)), adjustument
    move.l  d5, d6                      ;; save for later


    move.l  d5,pf_pres_long(a6)

    ;; xbfix = x1fix + fix_fix_mul(prestep, dxdyb);   // dxdyb = dxdy2
    ;;       =>  x1fix + (prestep * dxdyb) / (FIX_BITS_ONE) - division =  >> FIX_BITS, but '>>' is implementation specific (logical / arithmetic)

    muls    d2, d5                      ;; prestep * dxdyb (dxdyb = dxdy2)
    asr.l   #FIX_BITS, d5               ;; fix_fix_mul = (x * y) / (fix_bits)  => arithmetic shift right
    add.l   vertex_x(a1),d5             ;; adjust starting point for long edge: xbfix, =  (x1 + fix_fix_mul(prestep, dxdyb))


    move.l  d5,pf_xfix_long(a6)
    move.l  d2,pf_dxdy_long(a6)


    ;; get scanline (a4 = &pixmap->image[y1 * pixmap->width])

    move.l  vertex_y(a1),d7              ;; d0 = y1
    asr.l   #FIX_BITS, d7               ;; fixpoint correction 
    ;; can be optimized, but does not work in the emulator!!!
    mulu.l  goa_pixmap_width(a0),d7     ;; width * y1, this is always unsigned!
    move.l  goa_pixmap_image(a0),a4    
    add.l   d7, a4                      ;; a4 = pixmap->image + width * y1; (&pixmap->image[width * y1])
    ;; a4 now points to the corfect scanline


    ;; calc and check dy
    move.l  vertex_y(a2),d7
    move.l  vertex_y(a1),d4
    asr.l   #FIX_BITS, d4               ;; fixpoint correction 
    asr.l   #FIX_BITS, d7               ;; fixpoint correction 
    sub.l   d4,d7             ;; d7 = dy = y2 - y1 (still in fix point)
    beq     .skip_upper_right   
    ;; dy (d7) > 0


    move.l  d6,pf_pres_up(a6)

    move.l  vertex_x(a1),d4              ;; d4 = xafix
    ;; prestepping for d4 (xafix), d1 - gradient, d6 is prestep value (see above)
    muls    d1, d6              ;; prestep * dxdya
    asr.l   #FIX_BITS, d6       ;; (prestep * dxdya) / FIX_BITS
    add.l   d6, d4              ;; x1fix + (prestep * dxdya) / FIX_BITS

    move.l  #1,pf_valid_up(a6)
    move.l  d1,pf_dxdy_up(a6)
    move.l  d4,pf_xfix_up(a6)

    
    ;; d3, gradient, short lower edge, need to save this
    push    d3 
;
; Upper triangle segment including scanline
;
; register allcation
; d0, color
; d1, short edge gradient
; d2, long edge gradient
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
.upper_right_y_triseg:
    ;; I've been testing a few ways in order to pipeline the loop better, but they all produced jagged edges
    ;; This scanline version produces by far the best results...

    move.l  d5, d6
    move.l  d4, d3              ; d4 is the short edge
    asr.l   #FIX_BITS, d6       ; can't do asr.l on address register... pity...
    asr.l   #FIX_BITS, d3
    move.l  a4, a5
    sub.l   d3,d6               ; d6 is loop
    add.l   d3,a5               ; a5 points at first pixel of scanline

    ;; THIS IS THE MASTER LOOP - I don't know how to make this any tighter..
.upper_right_y_scan:
    move.b  d0,(a5)+      ; this is 1 cycle slower then direct but pipeline is maintained
    subq.l  #1, d6
    bpl     .upper_right_y_scan
;    move.b  d0,(a5)      ; this is 1 cycle slower then direct but pipeline is maintained
;    move.b  d0,(a5,d6.l)      ; this is 1 cycle slower then direct but pipeline is maintained

    ;; end of scanline here

    add.l   d1,d4                   ;; xafix += dxdy1
    add.l   d2,d5                   ;; xbfix += dxdy2      
    add.l   goa_pixmap_width(a0),a4                 ;; advance next scanline
    subq.l  #1,d7
    bne     .upper_right_y_triseg

    pop     d3                      ;; restore lower short edge gradient

    move.l  d5,pf_xmid_long(a6)
    ;; lower right from here
.skip_upper_right:

    ; register allocation
    ; d0 - color
    ; d1 - free
    ; d2 - long edge gradient - xbfix
    ; d3 - short edge gradient
    ; d4 - free
    ; d5 - long edge X coordinate
    ; d6 - free
    ; d7 - free
    ;
 
    ;; very little setup for second segment as we just continue
    move.l vertex_y(a3),d7
    move.l vertex_y(a2),d1
    asr.l  #FIX_BITS, d7           ;; fixpoint correction 
    asr.l  #FIX_BITS, d1           ;; fixpoint correction 
    sub.l  d1,d7                ;; d6 = dy = y3 - y2
    ;; Zero check (y3 - y2 == 0, skip!)
    beq    .skip_lower_right


    ;; prestepping of lower short edge
    move.l  vertex_y(a2),d1             ;; 
    move.l  #FIX_BITS_ONE, d4           ;;  1 << FIX_BITS (i.e. 1 in Fixpoint)
    and.l   #FIX_BITS_MASK, d1          ;; mask out the fractional part of Y1
    sub.l   d1, d4                      ;; d1 = prestep (1.0 - fractional(y1)), adjustument

    move.l  d4,pf_pres_down(a6)

 
    muls    d3, d4                      ;; prestep * dxdyb (dxdyb = dxdy2)
    asr.l   #FIX_BITS, d4               ;; fix_fix_mul = (x * y) / (fix_bits)  => arithmetic shift right
    add.l   vertex_x(a2),d4             ;; adjust starting point for short edge: xafix, =  (x2 + fix_fix_mul(prestep, dxdy3))


    move.l  #1,pf_valid_down(a6)
    move.l  d3,pf_dxdy_down(a6)
    move.l  d4,pf_xfix_down(a6)


    ; register allocation
    ; d0 - color
    ; d1 - free/scratch
    ; d2 - long edge gradient - xbfix
    ; d3 - short edge gradient
    ; d4 - short edge X coordinate
    ; d5 - long edge  X coordinate
    ; d6 - scan loop counter (X)
    ; d7 - scanline counter (Y)
    ;
.lower_right_y_triseg:
    move.l  d5, d6      ;; 
    move.l  d4, d1      ;; d4 is short edge, d1 was used for upper and is now free
    asr.l   #FIX_BITS, d6
    asr.l   #FIX_BITS, d1
    move.l  a4, a5
    sub.l   d1, d6
    add.l   d1, a5
.lower_right_y_scan:
    move.b  d0, (a5)+
    subq    #1, d6
    bpl     .lower_right_y_scan

;; end scanline, advance to next

    add.l   d3,d4                   ;; xafix += dxdy3
    add.l   d2,d5                   ;; xbfix += dxdy2      
    add.l   goa_pixmap_width(a0),a4                 ;; advance next scanline
    subq.l  #1,d7
    bne     .lower_right_y_triseg   ;; BNE or BPL??????
.skip_lower_right:

    move.l  d5,pf_xend_long(a6)

    ;; restore stack
    pop     d2-d7/a4-a5

    rts

;;
;; Long edge on the left
;;
.left_long_edge:

    ; Register allocation
    ;  d0 - color
    ;  d1 - dxdy1, upper short
    ;  d2 - dxdy2, long edge
    ;  d3 - dxdy3, lower short
    ;  d4 - short edge X-coord (set later)
    ;  d5 - long edge X-coord

    ;move.l  vertex_y(a1),d0              ;; d0 = y1
    ;move.l  vertex_x(a1),d5              ;; d5 = xb, do this here as we skip the setup if zero height

    ; subpixel correction on v1 for long edge
    ; this should be done regardless if upper or lower is segment

    move.l  #0,pf_side(a6)


    ;; int32_t prestep = (1<<FIX_BITS) - fix_frac(y1fix);
    move.l  vertex_y(a1),d7              ;; d0 = y1
    move.l  #FIX_BITS_ONE, d5           ;;  1 << FIX_BITS (i.e. 1 in Fixpoint)
    and.l   #FIX_BITS_MASK, d7          ;; mask out the fractional part of Y1
    sub.l   d7, d5                      ;; d5 = prestep (1.0 - fractional(y1)), adjustument
    move.l  d5, d6                      ;; save for later

    move.l  d5,pf_pres_long(a6)

    ;; xbfix = x1fix + fix_fix_mul(prestep, dxdyb);   // dxdyb = dxdy2
    ;;       =>  x1fix + (prestep * dxdyb) / (FIX_BITS_ONE) - division =  >> FIX_BITS, but '>>' is implementation specific (logical / arithmetic)

    ;; prestep X1, long edge X-coord
    muls.l  d2, d5                      ;; prestep * dxdya (dxdya = dxdy2)
    asr.l   #FIX_BITS, d5               ;; fix_fix_mul = (x * y) / (fix_bits)  => arithmetic shift right
    add.l   vertex_x(a1),d5             ;; adjust starting point for long edge: xbfix, =  (x1 + fix_fix_mul(prestep, dxdyb))

    move.l  d5,pf_xfix_long(a6)
    move.l  d2,pf_dxdy_long(a6)


    ;; get scanline
    move.l  vertex_y(a1),d7            
    asr.l   #FIX_BITS, d7               ;; fixpoint correction 
    ;; can be optimized, but does not work in the emulator!!!
    mulu.l  goa_pixmap_width(a0),d7     ;; width * y1, this is always unsigned!
    move.l  goa_pixmap_image(a0),a4    
    add.l   d7, a4                      ;; a4 = pixmap->image + width * y1; (&pixmap->image[width * y1])

    ;; a4 now points to the corfect scanline

    move.l  vertex_y(a2),d7
    asr.l   #FIX_BITS, d7           ;; fixpoint correction 
    move.l   vertex_y(a1),d4                    ;; d6 = dy = y2 - y1 (still in fix point)
    asr.l   #FIX_BITS, d4           ;; fixpoint correction 

    sub.l   d4,d7
    beq     .skip_upper_left

    ;; Upper left segment here

    ;
    ; prestepping for short edge (xbfix)
    ;

    move.l  #1,pf_valid_up(a6)
    move.l  d6,pf_pres_up(a6)
    move.l  d1,pf_dxdy_up(a6)


    move.l  vertex_x(a1),d4     ;; d4 = xa, this is equal to d5 at this point (starting at same point)
    muls.l  d1, d6              ;; prestep * dxdyb
    asr.l   #FIX_BITS, d6       ;; (prestep * dxdyb) / FIX_BITS
    add.l   d6, d4              ;; x1fix + (prestep * dxdyb) / FIX_BITS   


    move.l d4,pf_xfix_up(a6)

    ;;
    ;; d0 - color
    ;; d1 - gradient short - right hand side
    ;; d2 - gradient long - left hand side 
    ;; d4 - X-coord, left upper short edge X-coord
    ;; d5 - X-coord, right hand coord (long side), this will live through
    ;; d6 - dx, scan loop counter
    ;; d7 - dy, scanline loop counter
    push    d3
.upper_left_y_triseg:

    move.l  d5, d3              ; d5 is long edge (left side)
    move.l  d4, d6              ; d4 is the short edge
    asr.l   #FIX_BITS, d6       ; can't do asr.l on address register... pity...
    asr.l   #FIX_BITS, d3
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
    add.l   d1,d4                   ;; right, xafix += dxdy1
    add.l   d2,d5                   ;; left, xbfix += dxdy2      
    add.l   goa_pixmap_width(a0),a4                 ;; advance next scanline

    subq.l  #1,d7
    bne     .upper_left_y_triseg    ;; XXXXXXX - bpl gives one more pixel... 
    pop     d3
    ;; end of upper triangle segment

    move.l  d5,pf_xmid_long(a6)

.skip_upper_left:    

    ;; very little setup for second segment as we just continue
    move.l vertex_y(a3),d7
    move.l vertex_y(a2),d1
    asr.l  #FIX_BITS,d7           ;; fixpoint correction 
    asr.l  #FIX_BITS,d1
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

    move.l  d4,pf_pres_down(a6)

 
    muls.l  d3, d4                      ;; prestep * dxdyb (dxdyb = dxdy3)  
    asr.l   #FIX_BITS, d4               ;; fix_fix_mul = (x * y) / (fix_bits)  => arithmetic shift right

    move.l  d4,pf_ffm_down(a6)

    add.l   vertex_x(a2),d4             ;; adjust starting point for short edge: xafix, =  (x2 + fix_fix_mul(prestep, dxdy3))


    move.l  #1,pf_valid_down(a6)
    move.l  d4,pf_xfix_down(a6)
    move.l  d3,pf_dxdy_down(a6)


    ;;
    ;; d1 is free to use at this stage - as it was upper short delta add (xafix)
    ;;
.lower_left_y_triseg:
    
    move.l  d4, d6     ; right
    move.l  d5, d1     ; left

    asr.l   #FIX_BITS, d6
    asr.l   #FIX_BITS, d1
    move.l  a4, a5
    sub.l   d1,d6
    add.l   d1,a5
    ;; TODO: fix this loop!!!!
.lower_left_y_scan:
    move.b  d0, (a5)+
    subq.l  #1, d6
    bpl     .lower_left_y_scan

    ;; end scanline, advance edges

    add.l   d3,d4                   ;; right, xafix += dxdy3
    add.l   d2,d5                   ;; left xbfix += dxdy2      
    add.l   goa_pixmap_width(a0),a4                 ;; advance next scanline
    subq.l  #1,d7
    bne     .lower_left_y_triseg
    ;; end triangle segment
.skip_lower_left:
    move.l  d5,pf_xend_long(a6)

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
v2_left:     dc.l    180<<FIX_BITS, 80<<FIX_BITS, 0
v3_left:     dc.l    110<<FIX_BITS,140<<FIX_BITS, 0


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
