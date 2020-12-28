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


LIGHT_STEPS     equ 64
LIGHT_STEPS_BITS equ 6

PIXMAP_WIDTH    equ 16

push    macro
        movem.l \1,-(a7)
        endm

pop     macro
        movem.l (a7)+,\1
        endm


        rsreset
cyl_h_prev  rs.l 1
cyl_h       rs.l 1
cyl_col     rs.l 1
cyl_l       rs.l 1
cyl_xp      rs.l 1
cyl_yp      rs.l 1
cyl_l_step  rs.l 1
cyl_x_step  rs.l 1
cyl_y_step  rs.l 1


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
    lea     backbuffer_image_data,a0
    lea     alpha_dst, a1
    add.l   #16,a1
    lea     alpha_src, a2
    add.l   #16,a2
    lea     image_src, a3
    add.l   #16,a3
    lea     blendtable, a4
    bsr     _blur_and_merge_scanline_asm
endtest:
    rts




    public _blur_and_merge_scanline_asm
_blur_and_merge_scanline_asm:
; ------------------------------------
;
;   Blur and Merge Scanline routine for particles part
;
;   a0 - backbuffer
;   a1 - alpha_dst
;   a2 - alpha_src
;   a3 - image_src
;   a4 - blendtable
;

    moveq.l #0,d0
    moveq.l #0,d1
    moveq.l #10,d6
    move.l  #PIXMAP_WIDTH,d7
    ;
    ; not optimized, per pixel..
    ;
.loop
    moveq.l #0,d0
    moveq.l #0,d1
    moveq.l #0,d2
    moveq.l #0,d3
    moveq.l #0,d4

    move.b (a2),d0
    move.b -1(a2),d2
    move.b +1(a2),d1
    move.b -PIXMAP_WIDTH(a2),d3
    move.b +PIXMAP_WIDTH(a2),d4

    add.l  d2,d1
    add.l  d4,d3
    add.l  d3,d1

    ; d1 = ia

    ;  alpha = (im + (ia >> 2)) >> 1;

    lsr.l  #2,d1
    ; d0 = im
    add.l  d1,d0
    lsr.l  #1,d0

    ; d0 = alpha
    move.b d0,(a1)+ ; alpha_pdst[x] = alpha;

    ; d1 = color
    move.b (a3)+,d1

    ; d2 = alpha, saved for later...
    move.l d0,d2

    ; blends = &blendtable[alpha*32*32];
    lsl.l  #5,d0
    lsl.l  #5,d0
    ; a5 = blends
    lea    (a4,d0.l),a5

    ; alpha = (16 + (alpha>>4)) << 5;
    lsr.l  #4, d2
    add.l  #16,d2
    lsl.l  #5, d2
    ; alpha + color
    add.l  d1, d2

    ; color = blends[alpha + color]
    move.b (a5,d2.l),d0

    ; next alpha value...
    add.l  #1,a2

    ; pdst[x] = color
    move.b d0,(a0)+

    subq    #1, d7
    bne     .loop

    rts



; ---------------
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

alpha_src:              dcb.b 320,128
alpha_dst:              dcb.b 320,0
image_src:              dcb.b 320,12

backbuffer_image_data:  dcb.b 320*180,0

blendtable:             incbin 'blendtable.bin'
