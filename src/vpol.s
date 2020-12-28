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
    lea     backbuffer,a0
    lea     backbuffer_image_data,a2
    move.l  goa_pixmap_image(a0),a3
    move.l  #200, d0
    move.l  #0,d1
    move.b  d0,(a3,d1.l)
    move.l  #160+90*320,d1
    move.b  d0,(a3,d1.l)



    lea     cyldata,a0

    move.l  cyl_h_prev(a0),d0
    move.l  cyl_h(a0),d0
    move.l  cyl_col(a0),d0
    move.l  cyl_l(a0),d0
    move.l  cyl_xp(a0),d0
    move.l  cyl_yp(a0),d0

    move.l  #5326,d7
    ; this is the loop
.draw
    movem.l   d7/a0,-(a7)

    move.l  a0,a2
    lea     backbuffer,a0    
    lea     ltab, a1

    move.l  vpol_r0_start_col,d0
    lsl.l   #LIGHT_STEPS_BITS, d0
    lea     (a1,d0.l),a1
    bsr     _interpolate_asm

    movem.l (a7)+,d7/a0
    add.l   #9*4,a0
    sub.l   #1, d7
    bne     .draw


    ; lea     backbuffer,a0    
    ; lea     ltab, a1
    ; move.l  vpol_r0_start_col,d0
    ; lsl.l   #LIGHT_STEPS_BITS, d0
    ; lea     (a1,d0.l),a1

    ; lea     vpol_r0_start, a2
    ; bsr     _interpolate_asm

    ; lea     vpol_r0_start, a0
    ; lea     vpol_r0_end, a1
    ; bsr     _cmp_vpol
endtest:
    rts


    public _interpolate_asm

_interpolate_asm:
; ------------------------------------
;
; Voxel bar interpolation...
;
; arguments:
;   a0 - backbuffer (GOA_PIXMAP8)
;   a1 - lighttab for color
;   a2 - interpolation structure
; used:
;   d0 - xp
;   d1 - yp
;   d2 - light value
;   a3 - scanline pointer
;



    move.l cyl_h_prev(a2), d7
    move.l goa_pixmap_image(a0),a3

    move.l cyl_xp(a2),d0       
    move.l cyl_yp(a2),d1
    move.l cyl_l(a2),d2
.loop
    ; interleave operations for better pipelining
    move.l d0,d4        
    move.l d1,d5        
    move.l d2,d6
    ;; d4 = xp, d5 = yp, d5 = l
    asr.l  #FIX_BITS, d5
    asr.l  #FIX_BITS, d4
    mulu.l goa_pixmap_width(a0),d5
    asr.l  #FIX_BITS,d6     ; d5 = fix_to_int(l)
    add.l  d5,d4
    move.b (a1,d6.l), d3 ; c = ltab[d6];
;
;  NOW: d4 = x + y * width
;  NOW: d3 = color;    
;

    ; move.l #200, d3       ;; temporary, override color

    ; interlave...
    add.l  cyl_x_step(a2),d0    ; xp += x_step
    move.b d3,(a3,d4.l)         ; scanline[pos] = color
    add.l  cyl_y_step(a2),d1    ; yp += y_step
    move.b d3,1(a3,d4.l)        ; scanline[pos+1] = color
    add.l  cyl_l_step(a2),d2    ; l  += l_step

    add.l  #1,d7
    cmp.l  cyl_h(a2),d7
    bne    .loop 

    move.l d0,cyl_xp(a2)
    move.l d1,cyl_yp(a2)
    move.l d2,cyl_l(a2)

    rts

; ---------------
;
; check if VPOL structures are same
;
; a0 - vpol A
; a1 - vpol B
;

_cmp_vpol:
    move.l #1, d0
    move.l cyl_xp(a0),d1
    cmp.l  cyl_xp(a1),d1
    bne    .exit
    move.l cyl_yp(a0),d1
    cmp.l  cyl_yp(a1),d1
    bne    .exit
    move.l cyl_l(a0),d1
    cmp.l  cyl_l(a1),d1
    bne    .exit
    move.l  #0,d0
.exit:
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

MakeCYLIPOL_A  Macro ;
\1:          
\1_h_prev  dc.l    \2
\1_h       dc.l    \3
\1_col     dc.l    \4
        endm

MakeCYLIPOL_B Macro ;
\1_l       dc.l    \2
\1_xp      dc.l    \3
\1_yp      dc.l    \4     
\1_l_step  dc.l    \5    
\1_x_step  dc.l    \6
\1_y_step  dc.l    \7
            Endm


; Start condition
;0, h_prev = 0
;0, h = 13
;0, col = 26
;0, l = 8064
;0, xp = 20480
;0, yp = 11520
;0, l_step = 0
;0, x_step = 0
;0, y_step = 128

    MakeCYLIPOL_A  vpol_r0_start,0,13,26
    MakeCYLIPOL_B  vpol_r0_start,8064,20480,11520,0,0,128

; End Condition
;1, h_prev = 13
;1, h = 13
;1, col = 26
;1, l = 8064
;1, xp = 20480
;1, yp = 13184
;1, l_step = 0
;1, x_step = 0
;1, y_step = 128

    MakeCYLIPOL_A  vpol_r0_end,13,13,26
    MakeCYLIPOL_B  vpol_r0_end,8064,20480,13184,0,0,128



    ; make sure we are 32bit aligned
    cnop 0,4

ltab                   incbin 'ltab.bin'
cyldata                incbin 'cyldata.bin'

backbuffer_image_data:  ds.b 320*180
