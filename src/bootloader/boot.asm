org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

;
; FAT12 header
;
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'                   ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                         ; 2880 * 512 = 1,4MB
bdb_media_descriptor_type:  db 0F0h                         ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                            ; 9 sectors / fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         db 0
bdb_large_sectors_count:    db 0

; Boot record etendu
ebr_drive_number:           db 0                            ; 0x00 floppy 0x80 hdd, pas important
                            db 0                            ; reserver
ebr_signature:              db 29h 
ebr_volume_id:              db 12h, 34h, 56h, 78h           ; numero de serie, la valeur est pas importante
ebr_volume_label:           db 'NICOLAS P. '                ; 11 bytes, padder avec des espaces
ebr_system_id:              db 'FAT12   '                   ; 8 bytes

;
; Le code commence ici
; 

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
    lodsb                                                   ; load le prochain char dans al
    or al, al                                               ; checke si al est pas null
    jz .done
    
    mov ah, 0x0e                                            ; call le bios interupt
    int 0x10

    jmp .loop


.done:
    pop ax
    pop si
    ret


main:
    ; setup data segment
    mov ax, 0                                               ; peut pas ecrire sur ds/es pour l'instant
    mov ds, ax
    mov es, ax

    ;setup stack
    mov ss, ax
    mov sp, 0x7C00                                          ; le stack grandit vers le bas et commence a partir de ou il est loader en memoire

    ; lire le disque
    ; le bios devrait setter dl comme numero de disque
    mov [ebr_drive_number], dl

    mov ax, 1                                               ; LBA = 1: deuximeme secteur du disque
    mov cl, 1                                               ; 1 secteur a lire
    mov bx, 0x7E00                                          ; sa edvrait etre apres le bootloader
    call disk_read

    ; ecire le message
    mov si, msg_hello_world
    call puts

    cli                                                     ; desactive les interputs, le cpu ne sort pas de halte
    hlt

;
; gestion d'erreur
;
floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h                                                 ; attend une touche
    jmp 0FFFFh:0                                            ; saute au debut du bios, devrait rebooter

;
; Affiche un message quand la l'ecture du disque reussi
;
floppy_success:
    mov si, msg_read_sucess
    call puts
    ret

.halt:
    cli                                                     ; desactive les interupts, comme sa le CPU peut pas sortir de halte
    hlt                                                     ; 


;
; Disk routines
;

;
; Convertir un addresse LBA => CHS
; Params:
;   - ax: adresse LBA
; Retourne:
;   - cx [bits 0-5]: numero de secteur
;   - cx [bits 6-15]: cylindre
;   - dh: tete
lba_to_chs:

    push ax
    push dx

    xor dx, dx                                              ; dx = 0
    div word [bdb_sectors_per_track]                        ; ax = LBA / SectorsPerTrack
                                                            ; dx = LBA % SectorsPerTrack
    
    inc dx                                                  ; dx = (LBA % SectorsPerTrack + 1) = sector
    mov cx, dx                                              ; cx = Sector

    xor dx, dx                                              ; dx = 0
    div word [bdb_heads]                                    ; ax = (LBA / SectorsPerTrack) / Heads = cylindre
                                                            ; dx = (LBA / SectorsPerTrack) % Heads = head

    mov dh, dl                                              ; dh = head 
    mov ch, al                                              ; ch = cylindre (8 bits du bas)
    shl ah, 6
    or cl, ah                                               ; mettre les deux bits du haut dans du cylindre dans cl

    pop ax
    mov dl, al                                              ; restorer DL
    pop ax
    ret

; 
; Lire du disque 
; Params:
;   - ax: adresse de LBA
;   - cl: nombre de sectuer a lire (max 128)
;   - dl: numero du disque
;   - es:bx: addresse en memoire ou storer les datas
;
disk_read:

    push ax                                                 ; sauver les registre modifier
    push bx
    push cx
    push dx
    push di


    push cx                                                 ; sauve temporairement CL (nombre de secteur al lire)
    call lba_to_chs                                         ; calculer CHS
    pop ax                                                  ; AL = nombre de secteur a lire

    mov ah, 02h
    mov di, 3                                               ; compteur d'essai
     
.retry:
    pusha                                                   ; sauver tout les registres, on sait pas ce que le bios modifie
    stc                                                     ; set carry flag, certain bios ne le font pas
    int 13h                                                 ; carry flag clearer = reussi
    jnc .done                                               ; jump si carry not set

    ; lecture echouer
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    ; toute les tentative sont utiliser
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax                                                 ; restorer les registres modifier
    jmp floppy_success
    ret

;
; Reseter le controleur du disque
; Params:
;   - dl: numero de disque
;
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

; Different message possible
msg_hello_world: db "hello world", ENDL, 0
msg_read_failed: db "La lecture du disque a echouer", ENDL, 0
msg_read_sucess: db "La lecture du disque a reussi", ENDL, 0

times 510-($-$$) db 0
dw 0AA55h
