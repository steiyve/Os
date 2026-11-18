org 0x0
bits 16

%define ENDL 0x0D, 0x0A

start:
    ; ecire le message
    mov si, msg_hello_world
    call puts

    hlt

.halt:
    jmp .halt
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


msg_hello_world: db "hello world du kernel", ENDL, 0
