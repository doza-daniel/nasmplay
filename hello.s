; Define (initialized) variables in the data section
SECTION .data
filename    db 'hello.s',0h
sep         db ' --> ',0h
buffer_size db 255

; Define (NOT initialized) variables in the BSS section
SECTION .bss
buffer              resb 4096
open_fd             resb 4

current_state       resb 1

current_key_buff    resb 101
current_key_offset  resb 1
current_val_buff    resb 10
current_val_offset  resb 1


SECTION .text
global _start

_start:
    pop     ecx
    mov     ebx, 0
arg_loop:
    cmp     ebx, ecx
    je      _end
    inc     ebx
    pop     eax

    cmp     ebx, 1
    je      arg_loop

    call    cat
    jmp     arg_loop

_end:
    mov     eax, 0
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
    mov     edx, [buffer_size]  ; number of bytes to read - one for each letter of the file contents
    mov     ecx, buffer         ; move the memory address of our file contents variable into ecx
    mov     ebx, [open_fd]      ; file descriptor
    mov     eax, 3              ; read
    int     80h                 ; syscall

    cmp     eax, 0              ; if 0 bytes read
    jz      read_done           ; end of file

    mov     ebx, eax
    mov     eax, buffer
    call    handle_buffer

    jmp     read_loop           ; loop

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
; handle_buffer(buff *char, len int)
handle_buffer:
    push    ebp
    mov     ebp, esp
    push    eax ; buff  [ebp-4]
    push    ebx ; len   [ebp-8]

    mov     ecx, 0
handle_loop:
    cmp     ecx, [ebp-8]
    je      handle_done
    mov     eax, [ebp-4]
    cmp     byte [eax+ecx], 3Bh
    je      switch_state
    cmp     byte [eax+ecx], 0Ah
    je      line_feed_found
    cmp     byte [current_state], 0
    je      in_key
    jmp     in_val
line_feed_found:
    movzx   eax, byte [current_key_offset]
    inc     eax
    mov     byte [current_key_buff+eax], 0x00
    mov     eax, current_key_buff
    call    sprint

    mov     eax, sep
    call    sprint

    movzx   eax, byte [current_val_offset]
    inc     eax
    mov     byte [current_val_buff+eax], 0x00
    mov     eax, current_val_buff
    call    sprintln

    mov     byte [current_key_offset], 0
    mov     byte [current_val_offset], 0
switch_state:
    inc     ecx
    xor     byte [current_state], 1h
    jmp     handle_loop
in_key:
    mov     eax, [ebp-4]
    mov     bl, byte [eax+ecx]
    movzx   eax, byte [current_key_offset]
    mov     byte [current_key_buff+eax], bl
    inc     byte [current_key_offset]
    jmp     inc_and_loop
in_val:
    mov     eax, [ebp-4]
    mov     bl, byte [eax+ecx]
    movzx   eax, byte [current_val_offset]
    mov     byte [current_val_buff+eax], bl
    inc     byte [current_val_offset]
inc_and_loop:
    inc     ecx
    jmp     handle_loop
handle_done:
    mov     esp, ebp
    pop     ebp
    ret

;---------------------------------------------------------------------------
; hash(s *char) int
; Given a null-terminated string `s`, compute it's polynomial rolling hash.
; hash = sum([s[i] * p^i for i in 0..len(s)]) % m
; ATM p = 31 and m = 10000 hardcoded
hash:
    push    ebp
    mov     ebp, esp
    push    0

    mov     ecx, 0x00
hash_loop:
    mov     eax, [ebp+8]
    movzx   ebx, byte [eax+ecx]
    cmp     ebx, 0x00
    je      hash_done


    push    ebx
    mov     eax, 31
    mov     ebx, ecx
    call    pow
    pop     ebx
    mul     ebx

    pop     ebx
    add     ebx, eax
    push    ebx

    inc     ecx
    jmp     hash_loop
hash_done:
    xor     edx, edx
    pop     eax
    mov     ebx, 10000
    div     ebx
    mov     eax, edx
    mov     esp, ebp
    pop     ebp
    ret
;---------------------------------------------------------------------------


;---------------------------------------------------------------------------
; atoi(s *char, l int) int
; Parse int from string s (s -> eax, l -> ebx) - with a caveat: since we
; know the string will be in the format '[0-9]+\.[0.9]', we will parse it as a
; regular int and not a floating point (e.g. atoi("12.3") -> 123)
atoi:
    push    eax                     ; pointer to start of string
    push    ebx                     ; string length
    push    0                       ; exponent (y) for calculating x*10^y
    push    0                       ; accumulated result


    mov     ecx, -1                 ; start from -1: we inc first thing in loop so we reduce the number of branching when we hit '.'
atoi_loop:
    inc     ecx                     ; i++
    cmp     ecx, dword [esp+8]      ; if i == len(s)
    je      atoi_end                ; break

    mov     eax, dword [esp+12]     ; eax = &(s[0])
    mov     ebx, dword [esp+8]      ; ebx = len(s)
    sub     ebx, ecx                ; ebx -= i
    mov     al, byte [eax+ebx-1]    ; al = s[len(s)-i]
    cmp     al, 0x2E                ; if al == '.'
    je      atoi_loop               ; continue

    sub     al, 0x30                ; al = al - '0'
    and     eax, 0xFF               ; kill all irrelevant bits
    push    eax                     ; save for after we calculate 10^x

    mov     eax, 10                 ; first arg - base
    mov     ebx, [esp+8]            ; second arg - exponent (from stack)
    call    pow                     ; calc 10^x
    add     dword [esp+8], 1        ; increment exponent

    mov     ebx, eax                ; ebx = 10^x
    pop     eax                     ; eax = current_digit
    mul     ebx                     ; eax *= 10^x
    pop     ebx                     ; get current total from stack
    add     ebx, eax                ; add `current_digit * 10^x` to total
    push    ebx                     ; push total back to stack

    jmp     atoi_loop               ; loop
atoi_end:
    pop     eax
    pop     ebx
    pop     ebx
    pop     ebx
    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; pow(x int, y int) -> int
; Compute x^y. (x -> eax, y -> ebx)
pow:
    push    ecx
    mov     ecx, eax
    mov     eax, 1
pow_loop:
    cmp     ebx, 0
    jz      pow_end
    mul     ecx
    dec     ebx
    jmp     pow_loop
pow_end:
    pop     ecx
    ret

;---------------------------------------------------------------------------
; indexOf(s *char, l int, c char)
; Try to find the index of character c in string s of length l. Returns the
; index in eax or -1 if not found
indexOf:
    push    ebx
    push    ecx
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
    pop     ecx
    pop     ebx
    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; exit the program with code in eax
exit:
    mov     ebx, eax
    mov     eax, 1
    int     80h
    ret
;---------------------------------------------------------------------------

; vim: ft=nasm
