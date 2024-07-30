; Define (initialized) variables in the data section
SECTION .data
filename    db 'hello.s',0h
sep         db '-->',0h
buffer_size db 255

; Define (NOT initialized) variables in the BSS section
SECTION .bss
buffer      resb 4096
open_fd     resb 4

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
    mov     edx, buffer

handle_line:
    cmp     cl, 3Bh
    je      push_lf
    push    3Bh
    jmp     continue
push_lf:
    push    0Ah
continue:

    pop     ecx                 ; get either ';' or '\lf' from stack depending on where we are in the line
    mov     eax, edx            ; set up buffer pointer argument
    call    indexOf             ; find the index of ';' or '\lf'
    cmp     eax, -1             ; if it was *not* found
    je      handle_end          ; stop loop - this means we are at the end of buffer

    push    eax                 ; holds the index of '\lf' or ';', save for later
    push    ebx                 ; holds the current current buffer len, save for later
    push    ecx                 ; holds '\lf' or ';', what is being searched for
    push    edx                 ; holds the current start pointer of the buffer, save for later

    mov     ecx, edx            ; set buffer
    mov     edx, eax            ; set number of bytes to print (index of)
    mov     ebx, 1              ; stdout
    mov     eax, 4              ; write
    int     80h                 ; syscall

    mov     eax, sep            ; print '-->' instead of ';' or '\lf'
    call    sprint

    pop     edx                 ; restore pointer
    pop     ecx                 ; restore ';' or '\lf', which ever was searched last
    pop     ebx                 ; restore len
    pop     eax                 ; restore index of

    add     eax, 1              ; eax points to a '\lf' or ';' - move it forward
    add     edx, eax            ; point the buffer to the new start
    sub     ebx, eax            ; calculate the remaining len to the end of buffer

    jmp     handle_line         ; loop

handle_end:                     ; flush (print) whatever is left in the buffer
    mov     ecx, edx            ; pointer
    mov     edx, ebx            ; count (current len)
    mov     ebx, 1              ; stdout
    mov     eax, 4              ; write
    int     80h                 ; syscall

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
