; Define (initialized) variables in the data section
SECTION .data
filename            db 'hello.s',0h
sep                 db ' --> ',0h
eq_string           db '=',0h
slash_string        db '/',0h
comma_string        db ', ',0h
open_brace_string   db '{',0h
closed_brace_string db '}',0h
buffer_size         db 255

; Define (NOT initialized) variables in the BSS section
SECTION .bss
buffer              resb 4096
open_fd             resb 4

current_state       resb 1

current_key_buff    resb 101
current_key_offset  resb 1
current_val_buff    resb 10
current_val_offset  resb 1

struc result
    .city:          resb 101
    .min:           resd 1
    .max:           resd 1
    .sum:           resd 1
    .cnt:           resd 1
endstruc

result_index        resd 10000
result_pool         times 10000 resb result_size
result_pool_i       resd 1

itoa_buffer         resb 100

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

    push    result_index
    call    print_results

    jmp     arg_loop

_end:
    mov     eax, 0
    call    exit


;---------------------------------------------------------------------------
; sprintln(s *char)
; Print the null-terminated string s (eax) to stdout and append line-feed
sprintln:
    push    eax
    call    sprint

    push    eax
    mov     eax, 0Ah
    push    eax

    mov     eax, esp
    call    sprint

    pop     eax
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

    call    store

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
; store() void
store:
    push    ebp                             ; set up stack frame
    mov     ebp, esp
    sub     esp, 20

    mov     [ebp-4], eax                    ; save registers that we modify
    mov     [ebp-8], ebx
    mov     [ebp-12], ecx
    mov     [ebp-16], edx

    push    current_val_buff                ; convert string value to int
    call    atoi
    mov     [ebp-20], eax

    push    current_key_buff                ; calculate hash of the key
    call    hash

    mov     edx, result_index               ; get the position in the index array (base + hash*4)
    mov     ebx, [edx+eax*4]
    cmp     ebx, 0                          ; if it's NULL, means we should allocate new result
    jne     .update_existing                ; otherwise, update the existing result

.allocate:
    push    eax                             ; save key hash on stack
    push    edx                             ; save key hash on stack
    mov     eax, [result_pool_i]            ; calculate the offset of the next result (i * size)
    mov     ebx, result_size
    mul     ebx
    mov     ebx, result_pool                ; get the final address by adding the offset to the start
    add     ebx, eax

    pop     edx                             ; retrieve hash value
    pop     eax                             ; retrieve hash value
    mov     [edx+eax*4], ebx                ; set the allocated result address in the index

    movzx   eax, byte [current_key_offset]  ; copy the key to the allocated result - start by incrementing
    inc     eax                             ; the offset to get the actual number of bytes to be copied
    push    eax                             ; (including the NULL)
    push    current_key_buff
    push    ebx
    call    memcpy

    mov     eax, [ebp-20]                   ; get current value (int)
    mov     [ebx+result.min], eax
    mov     [ebx+result.max], eax
    mov     [ebx+result.sum], eax
    mov     dword [ebx+result.cnt], 1h

    inc     dword [result_pool_i]           ; increment the index of the next available spot for allocation

    jmp     store.done

.update_existing:
    mov     eax, [ebp-20]                   ; get current value (int)
.min:
    mov     edx, [ebx+result.min]           ; get current minimum
    cmp     edx, eax                        ; compare with new value
    jle     .max                            ; if current minimum is smaller, continue
    mov     [ebx+result.min], eax           ; else update it
.max:
    mov     edx, [ebx+result.max]           ; get current maximum
    cmp     edx, eax                        ; compare with new value
    jge     .sum                            ; if current maximum is greater, continue
    mov     [ebx+result.max], eax           ; else update it
.sum:
    mov     edx, [ebx+result.sum]           ; add the new value to the current sum
    add     edx, eax
    mov     [ebx+result.sum], edx
.cnt:
    inc     dword [ebx+result.cnt]          ; increment the count

.done:
    mov     eax, [ebp-4]                    ; restore modified registers
    mov     ebx, [ebp-8]
    mov     ecx, [ebp-12]
    mov     edx, [ebp-16]

    mov     esp, ebp                        ; tear down stack frame
    pop     ebp
    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; memcpy(dest, source *char, count int) void
memcpy:
    push    ebp
    mov     ebp, esp

    mov     ecx, 0
memcpy_loop:
    cmp     ecx, [ebp+16]
    je      memcpy_loop_done

    mov     eax, [ebp+12]
    mov     al, byte [eax+ecx]
    mov     ebx, [ebp+8]
    mov     byte [ebx+ecx], al

    inc     ecx
    jmp     memcpy_loop
memcpy_loop_done:
    mov     esp, ebp
    pop     ebp
    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; print_results() void
print_results:
    push    ebp
    mov     ebp, esp
    sub     esp, 17

    mov     [ebp-4], eax                    ; save registers that we modify
    mov     [ebp-8], ebx
    mov     [ebp-12], ecx
    mov     [ebp-16], edx
    mov     byte [ebp-17], 0h

    mov     ecx, 0
.loop:
    cmp     ecx, 10000
    je      .done

    mov     eax, [ebp+8]
    mov     ebx, [eax+ecx*4]
    cmp     ebx, 0
    je      .continue

    cmp     byte [ebp-17], 0h
    jne     .print_comma
.print_brace:
    mov     eax, open_brace_string
    call    sprint
    mov     byte [ebp-17], 1h
    jmp     .print_single
.print_comma:
    mov     eax, comma_string
    call    sprint


.print_single:
    mov     eax, ebx
    call    sprint
    mov     eax, eq_string
    call    sprint
    push    itoa_buffer
    push    dword [ebx+result.min]
    call    itoa
    mov     eax, itoa_buffer
    call    sprint
    mov     eax, slash_string
    call    sprint
    push    itoa_buffer
    push    dword [ebx+result.max]
    call    itoa
    mov     eax, itoa_buffer
    call    sprint
    mov     eax, slash_string
    call    sprint
    push    itoa_buffer
    push    dword [ebx+result.sum]
    call    itoa
    mov     eax, itoa_buffer
    call    sprint
    mov     eax, slash_string
    call    sprint
    push    itoa_buffer
    push    dword [ebx+result.cnt]
    call    itoa
    mov     eax, itoa_buffer
    call    sprint
.continue:
    inc     ecx
    jmp     .loop

.done:
    mov     eax, closed_brace_string
    call    sprint

    mov     eax, [ebp-4]                    ; restore modified registers
    mov     ebx, [ebp-8]
    mov     ecx, [ebp-12]
    mov     edx, [ebp-16]

    mov     esp, ebp
    pop     ebp
    ret

;---------------------------------------------------------------------------


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
; atoi(s *char) int
; Parse int from the null-terminated string s - with a caveat: since we
; know the string will be in the format '[0-9]+\.[0.9]', we will parse it as a
; regular int and not a floating point (e.g. atoi("12.3") -> 123). Result is 
; returned in `eax`.
atoi:
    push    ebp                     ; set up stack frame
    mov     ebp, esp
    sub     esp, 8                  ; reserve space for local vars
    mov     dword [ebp-4], 0        ; var result
    mov     dword [ebp-8], 0        ; var exponent

    push    ebx                     ; save registers that we modify
    push    ecx

    mov     eax, [ebp+8]            ; calculate len of input string
    call    slen
    dec     eax                     ; the last index in string (len(s)-1)
    mov     ecx, eax                ; going to loop backwards: (len(s)-1)..0

atoi_loop:
    cmp     ecx, -1                 ; break loop if out of bounds
    je      atoi_end

    mov     eax, [ebp+8]            ; input string
    movzx   eax, byte [eax+ecx]     ; get character at index (s[i])
    cmp     eax, 2Eh                ; if char is '.' continue
    je      continue

    sub     eax, 30h                ; char is a digit, to get int, subtract '0'
    push    eax                     ; save current digit
    mov     eax, 10                 ; base 10
    mov     ebx, [ebp-8]            ; exponent x
    call    pow                     ; calculate 10^x
    pop     ebx                     ; get current digit
    mul     ebx                     ; multiply current digit with 10^x

    add     [ebp-4], eax            ; add to overall result
    inc     dword [ebp-8]           ; increment exponent
continue:
    dec     ecx
    jmp     atoi_loop
atoi_end:
    pop     ecx                     ; restore saved register
    pop     ebx

    mov     eax, [ebp-4]            ; put result in eax

    mov     esp, ebp                ; tear down stack frame
    pop     ebp
    ret
;---------------------------------------------------------------------------

;---------------------------------------------------------------------------
; itoa(i int) char*
itoa:
    push    ebp
    mov     ebp, esp

    push    eax
    push    ebx
    push    ecx
    push    edx

    mov     eax, [ebp+8]
    mov     ebx, [ebp+12]
    mov     ecx, 0
.loop:
    cmp     eax, 0
    je      .done
    push    ecx
    mov     ecx, 10
    mov     edx, 0h
    div     ecx
    pop     ecx

    add     edx, dword 30h
    mov     [ebx+ecx], dl
    inc     ecx
    jmp     .loop
.done:
    mov     [ebx+ecx], byte 0h
    push    ebx
    call    reverse
    pop     ebx

    pop     edx
    pop     ecx
    pop     ebx
    pop     eax

    mov     esp, ebp
    pop     ebp
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
reverse:
    push    ebp
    mov     ebp, esp

    push    eax
    push    ebx
    push    ecx
    push    edx

    mov     eax, [ebp+8]
    call    slen
    dec     eax

    mov     ecx, 0
.loop:
    cmp     ecx, eax
    jge     .end
    mov     ebx, [ebp+8]
    mov     dl, [ebx+ecx]

    push    eax
    mov     al, [ebx+eax]
    mov     [ebx+ecx], al
    pop     eax
    mov     [ebx+eax], dl

    inc     ecx
    dec     eax
    jmp     .loop
.end:
    push    edx
    push    ecx
    push    ebx
    push    eax

    mov     esp, ebp
    pop     ebp
    ret
;---------------------------------------------------------------------------

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
