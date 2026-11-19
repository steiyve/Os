bits 16

section _TEXT class=CODE
global _x86_Video_WriteCharTeletype

;
; int 10h ah=0Eh
; args: charatere, pages
;
_x86_Video_WriteCharTeletype:
    ; fair un nouveau call frame
    push bp                                                 ; sauver le le vieux call frame
    mov bp, sp                                              ; initialiser un nouveau call frame

    ; sauver bx
    push bx

    ; [bp + 0] - le vieux call frame
    ; [bp + 2] - retourne l'adresse(petit model de memoir => 2 bytes)
    ; [bp + 4] - premier argmuent (charactere) 
    ; [bp + 6] - deuxime argument (page)
    ; note: les bytes sont convertie en word (tu peux pas push un byte seul sur le stack)
    mov ah, 0Eh 
    mov al, [bp + 4]
    mov bh, [bp + 6]

    int 10h

    ; restorer bx
    pop bx

    ; restorer le vieux call frame
    mov sp, bp
    pop bp
    ret


