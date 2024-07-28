; Define (initialized) variables in the data section
SECTION .data
filename    db 'hello.s',0h
sep         db '-->',0h
buffer_size db 255

; Define (NOT initialized) variables in the BSS section
SECTION .bss
buffer  resb 4096
open_fd resb 4

SECTION .text
global _start

_start:
    pop     ecx
    mov     ebx, 0
arg_loop:
    cmp     ebx, ecx
    je      kraj
    inc     ebx
    pop     eax

    cmp     ebx, 1
    je      arg_loop

    call    cat
    jmp     arg_loop

kraj:
    call    exit


;---------------------------------------------------------------------------
; sprintln(s *char)
; Print the null-terminated string s (eax) to stdout and append line-feed
sprintln:
    call    sprint

    push    eax
    mov     eax, 0Ah
    push    eax

    mov     eax, esp
    call    sprint

    pop     eax
    pop     eax
    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; sprint(s *char)
; Print the null-terminated string s (eax) to stdout
sprint:
    push    edx
    push    ecx
    push    ebx
    push    eax

    call    slen

    mov     edx, eax
    pop     ecx
    mov     ebx, 1
    mov     eax, 4
    int     80h

    pop     ebx
    pop     ecx
    pop     edx

    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; slen(s *char) -> int
; Calculate the length of null-terminated string s (eax) and return the length
; in eax.
slen:
    push    ebx

    mov     ebx, eax            ; point ebx to the beginning of the string
slen_loop:
    cmp     byte [eax], 0       ; loop until we hit 00h (null terminator)
    jz      slen_done
    inc     eax
    jmp     slen_loop
slen_done:
    sub eax, ebx                ; eax points to end, ebx to beginning of the string

    pop ebx

    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; cat(path *char)
; Print out the file located at null-terminated string path (eax)
cat:
    push    ebx
    push    ecx
    push    edx

    ; open file
    mov     ecx, 0              ; flag for readonly access mode (O_RDONLY)
    mov     ebx, eax            ; filename we created above
    mov     eax, 5              ; invoke SYS_OPEN (kernel opcode 5)
    int     80h
    mov     [open_fd], eax

read_loop:
    ; read file
    mov     edx, 255            ; number of bytes to read - one for each letter of the file contents
    mov     ecx, buffer         ; move the memory address of our file contents variable into ecx
    mov     ebx, [open_fd]
    mov     eax, 3              ; invoke SYS_READ (kernel opcode 3)
    int     80h

    ; if 0 bytes read, return
    cmp     eax, 0
    jz      read_done

    ; print buffer
    mov     edx, eax            ; buffer len
    mov     ecx, buffer         ; buffer addr
    mov     ebx, 1              ; STDOUT
    mov     eax, 4              ; read syscall (4)
    int     80h

    jmp     read_loop

read_done:
    ; close file
    mov     ebx, [open_fd]
    mov     eax, 6
    int     80h

    ; clean up
    pop     edx
    pop     ecx
    pop     ebx
    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; indexOf(s *char, l int, c char)
; Try to find the index of character c in string s of length l. Returns the
; index in eax or -1 if not found
indexOf:
    push    edx

    mov     edx, eax
indexOfLoop:
    push    eax
    sub     eax, edx
    cmp     eax, ebx
    je      indexNotFound
    pop     eax

    cmp     byte [eax], cl
    je      indexFound
    inc     eax
    jmp     indexOfLoop

indexFound:
    sub     eax, edx
    jmp     indexOfRet

indexNotFound:
    pop     eax
    mov     eax, -1
    jmp     indexOfRet

indexOfRet:
    pop     edx
    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; exit the program with 0 code
exit:
    mov     ebx, 0
    mov     eax, 1
    int     80h
    ret
;---------------------------------------------------------------------------

; vim: ft=nasm
