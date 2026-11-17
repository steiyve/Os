org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

start:
    jmp main

;
; Affiche un string a l'ecran
; Params:
;   - ds:si point le string
;
puts:
    ; sauve les registre qui vont etre modifier
    push si
    push ax

.loop:
    lodsb                                  ; load le prochain char dans al
    or al, al                              ; checke si al est pas null
    jz .done
    
    mov ah, 0x0e                           ; call le bios interupt
    int 0x10

    jmp .loop


.done:
    pop ax
    pop si
    ret


main:
    ; setup data segment
    mov ax, 0                              ; peut pas ecrire sur dsées pour l'instant
    mov ds, ax
    mov es, ax

    ;setup stack
    mov ss, ax
    mov sp, 0x7C00                         ; le stack grandit vers le bas et commence a partir de ou il est loader en memoire

    ; ecire le message
    mov si, msg_hello_world
    call puts

    hlt

.halt:
    jmp .halt


msg_hello_world: db "hello world", ENDL, 0

times 510-($-$$) db 0
dw 0AA55h
