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
bdb_total_sectors:          dw 2880                         ; 2880 * 512 = 1.4 MB
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
    ; setup data segment
    mov ax, 0                                               ; peut pas ecrire sur ds/es pour l'instant
    mov ds, ax
    mov es, ax

    ;setup stack
    mov ss, ax
    mov sp, 0x7C00                                          ; le stack grandit vers le bas et commence a partir de ou il est loader en memoire

    ; Certain bios peuvent commencer a l'adresse 07C0:0000 a la place de 0000:7C00, juste etre sur
    ; de commencer au bon endroit
    push es
    push word .after
    retf

.after:
    ; lire le disque
    ; le bios devrait setter dl comme numero de disque
    mov [ebr_drive_number], dl

    
    ; Afficher le Message de chargement
    mov si, msg_loading
    call puts

    ; lit les parametre du disque
    push es
    mov ah, 08h
    int 13h
    jc floppy_error
    pop es

    and cl, 0x3F                                            ; retire les 2 bits du haut
    xor ch, ch
    mov [bdb_sectors_per_track], cx                         ; nombre de secteur

    inc dh
    mov [bdb_heads], dh                                     ; nombre de tete

    ; lire le Root du FAT
    mov ax, [bdb_sectors_per_fat]                           ; calculer le lba du root = reserver + fats * secteur par fat
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx                                                  ; ax = (fats * secteur par fat)
    add ax, [bdb_reserved_sectors]                          ; ax = lba du root

    push ax

    ; calculer la taille du root = (32 * nombre d'entree) / bytes par secteur
    mov ax, [bdb_dir_entries_count]
    shl ax, 5                                               ; ax *= 32
    xor dx, dx                                              ; dx = 0
    div word [bdb_bytes_per_sector]                         ; le nombre de secteur a lire

    test dx, dx                                             ; si dx != 0, ajouter 1
    jz .root_dir_after
    inc ax                                                  ; reste de la division != 0, ajoute 1
                                                            ; ca veut dire que le secteur est partiellement rempli 
                                                            ; avec des entrees
    
.root_dir_after:
    ; lire le root
    mov cl, al                                              ; cl = nombre de secteur a lire = taille du root
    pop ax                                                  ; ax = lba du root
    mov dl, [ebr_drive_number]                              ; dl = numero de disque (sauvegarder plus tot)
    mov bx, buffer                                          ; es:bx = buffer
    call disk_read

    ; chercher pour le fichier kernel.bin
    xor bx, bx
    mov di, buffer

.search_kernel:
    mov si, file_kernel_bin
    mov cx, 11                                              ; compare jusqu'a 11 caractere
    push di
    repe cmpsb
    pop di
    je .found_kernel

    add di, 32
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_kernel

    ; le kernel est introuvable
    jmp kernel_not_found

.found_kernel:

    ; di devrait contenir l'adresse de l'entree
    mov ax, [di + 26]                                       ; premier cluster logiquement
    mov [kernel_cluster], ax

    ; loader la FAT dans la memoire
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]                              ; CORRIGÉ : dl au lieu de cl
    call disk_read

    ; lire le kernel et processer la chaine FAT
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    ; lire le prochain cluster
    mov ax, [kernel_cluster]
    add ax, 31                                              ; premier cluster = (kernel_cluster - 2) * nombre de secteur par cluster + start_secter
                                                            ; start sector = reserver + fat + taille du root  = 1 + 18 + 14 = 33
    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]

    ; calculer la position du prochain cluster
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx                                                  ; ax = index de l'entree en FAT, dx = cluster modulo 2

    mov si, buffer
    add si, ax
    mov ax, [ds:si]                                         ; lire l'entree de la table fat a l'index ax

    or dx, dx 
    jz .even 

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8                                          ; fin de la chaine
    jae .read_finish

    mov [kernel_cluster], ax
    jmp .load_kernel_loop

.read_finish:
    
    ; aller au kernel
    mov dl, [ebr_drive_number]                              ; booter l'appareil dans dl

    mov ax, KERNEL_LOAD_SEGMENT                             ; setter les registre de segment
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    jmp wait_key_and_reboot                                 ; ne devrait jamais arriver


    cli                                                     ; desactive les interrupts, le cpu ne sort pas de halte
    hlt

;
; gestion d'erreur
;
floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

kernel_not_found:
    mov si, msg_kernel_not_found
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h                                                 ; attend une touche
    jmp 0FFFFh:0                                            ; saute au debut du bios, devrait rebooter


.halt:
    cli                                                     ; desactive les interrupts, comme ca le CPU peut pas sortir de halte
    hlt                                                     ; 


;
; Affiche un string a l'ecran
; Params:
;   - ds:si pointe la string
;
puts:
    push si
    push ax
    push bx

.loop:
    lodsb               ; loader le prochain caractere dans al
    or al, al           ; verifie si il est null
    jz .done

    mov ah, 0x0E        ; appelle l'interrupt du bios
    mov bh, 0           ; set le numero de page a 0
    int 0x10

    jmp .loop

.done:
    pop bx
    pop ax
    pop si    
    ret

;
; Disk routines
;

;
; Convertir un adresse LBA => CHS
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
    mov dl, al                                              ; restaurer DL
    pop ax
    ret

; 
; Lire du disque 
; Params:
;   - ax: adresse de LBA
;   - cl: nombre de secteur a lire (max 128)
;   - dl: numero du disque
;   - es:bx: addresse en memoire ou stocker les datas
;
disk_read:

    push ax                                                 ; sauver les registres modifies
    push bx
    push cx
    push dx
    push di


    push cx                                                 ; sauve temporairement CL (nombre de secteur a lire)
    call lba_to_chs                                         ; calculer CHS
    pop ax                                                  ; AL = nombre de secteur a lire

    mov ah, 02h
    mov di, 3                                               ; compteur d'essai
     
.retry:
    pusha                                                   ; sauver tous les registres
    stc                                                     ; set carry flag
    int 13h                                                 ; carry flag cleared = reussi
    jnc .done                                               ; jump si carry not set

    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax                                                  ; restaurer les registres modifies
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

; Differents messages possibles
msg_loading:          db "Chargement ...", ENDL, 0
msg_read_failed:      db "erreur a la lecture du disque", ENDL, 0
msg_kernel_not_found: db "kernel.bin introuvable", ENDL, 0
file_kernel_bin:      db "KERNEL  BIN"
kernel_cluster:       dw 0
KERNEL_LOAD_SEGMENT   equ 0x2000
KERNEL_LOAD_OFFSET    equ 0

times 510-($-$$) db 0
dw 0AA55h

buffer: