; Mateusz Biesiadowski 406097

INC_V     equ 1                         ; wartość o jaką zostaje zwiększone pidx w każdym obrocie pętli
EXP_BASE  equ 16                        ; podstawa potęgi


%define ppi r12
%define pidx r13
%define max r14
%define m r15


; void pixtime(uint64_t clock_tick)
extern pixtime


; Wywołuje funkcję pixtime(uint64_t clock_tick) z odpowiednią wartością clock_tick.
%macro call_pix_time 0
        rdtsc
        mov     rdi, rdx
        shl     rdi, 32
        add     rdi, rax
        call    pixtime
%endmacro


; Umieszcza na stosie rejestry, które nie powinny być modyfikowane.
%macro preserve_registers 0
        push    rbx
        push    rsp
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
%endmacro


; Przywraca rejestry zapisane na początku funkcji ze stosu.
%macro restore_registers 0
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rsp
        pop     rbx
%endmacro


; Zapisuje argumenty funkcji do zmiennych.
; Pierwszy argument zostaje zapisany w rejestrze rdi, drugi w rsi, a trzeci w rdx.
%macro get_pix_args 0
        mov     ppi, rdi                ; pierwszy argument
        mov     pidx, rsi               ; drugi argument
        mov     max, rdx                ; trzeci argument
%endmacro


; Pobiera atomowo aktualną wartość indeksu w tablicy i zwiększa jego wartość o INC_V.
; Wartość zostaje zapisana w m.
%macro get_inc_counter 0
        xor     m, m
        mov     m, INC_V                ; W m jest wartość, o którą *pidx ma zostać zwiększony.

        lock \
        xadd    [pidx], m               ; Atomowo zapisuje wartość *pidx w m i zwiększa wartość *pidx o INC_V.
%endmacro


; Oblicza pierwszą część sumy Sj.
; Pierwszy argument to rejestr na sumę, a drugi to wartość j.
; Korzysta z rejestrów rsi, rax, rcx, rdx (i r10, r11, rbx w części z potęgowaniem).
%macro Sj_I 2
        xor     rsi, rsi
        xor     rax, rax
        xor     rcx, rcx
        xor     rdx, rdx                ; Zeruje zmienne.

        mov     rcx, m                  ; iterator sumy dla n = 8m i wykładnik przy 16^n-k

        add     rsi, %2                 ; 8k + j, dla k = 0

%%loop:
        cmp     rcx, 0                  ; Sprawdza czy zostały dodane już wszystkie składniki sumy.
        je      %%last

        pow_mod rcx, rsi                ; Licznik znajduje się w rejestrze rdx.
        div     rsi                     ; Rozwinięcie dziesiętne ułamka znajduje się w rejestrze rax.

        add     %1, rax                 ; Dodaję ułamek do sumy.

        dec     rcx                     ; Zmniejsza wykładnik o 1.
        add     rsi, 8                  ; Zwiększa 8k + j dla następnej iteracji.

        jmp     %%loop

%%last:
        cmp     rsi, 1                  ; Jeśli makro zostało wywołane dla m = 0, to kończę.
        je      %%finished

        xor     rax, rax                ; Wpp. wykonuję jeszcze jedną iterację sumy, dla k = n.
        mov     rdx, 1                  ; 16^0 = 1 = 1 mod 8k + j dla k != 0 i j != 1

        div     rsi                     ; Obliczam 1 / (8n + j)
        add     %1, rax                 ; Dodaje ułamek do sumy.

%%finished:
%endmacro


; Oblicza 16^(%1) mod (%2) przy pomocy algorytmu szybkiego potęgowania.
; Pierwszym argumentem jest wykładnik, a drugim wartość modulo.
; Wynik zapisywany jest w rejestrze rdx, a rax jest zerowany.
; Korzysta z rejestrów rdx, rax, r10, r11, rbx.
%macro pow_mod 2
        xor     r10, r10
        xor     r11, r11
        xor     rdx, rdx
        xor     rbx, rbx
        xor     rax, rax                ; Zeruje zmienne.

        mov     rax, 1                  ; wynik
        mov     r10, %1                 ; wykładnik potęgi
        mov     r11, EXP_BASE           ; podstawa potęgi

%%loop:
        cmp     r10, 0                  ; Sprawdza czy całe potęgowanie zostało wykonane.
        je      %%finished

        test    r10, 1                  ; Sprawdza czy ostatni bit r10 jest 1.
        je      %%body                  ; Jeśli bit nie jest zapalony to przechodzi do dalszej części pętli. 

        mul     r11                     ; Mnoży aktualny wynik przez podstawę potęgi.

        xor     rdx, rdx
        div     %2                      ; Wynik modulo.
        
        mov     rax, rdx                ; Zamienia wynik na wynik modulo.

%%body:
        xor     rbx, rbx
        mov     rbx, rax                ; Zapisuje aktualny wynik w rbx.

        xor     rdx, rdx
        mov     rax, r11                ; Przenosi podstawę potęgi do rax.
        mul     rax                     ; Podnosi podstawę do kwadratu.
        div     %2                      ; Wykonuje modulo na podstawie potęgi.

        mov     r11, rdx                ; Przenosi podstawę potęgi modulo spowrotem do jej rejestru.
        
        mov     rax, rbx                ; Przenosi wynik spowrotem do rax.

        shr     r10, 1                  ; Przesuwa wykładnik o 1 bit w prawo.

        jmp     %%loop                  ; Kontynuuje pętlę.

%%finished:
        mov     rdx, rax                ; Przenosi wynik do rejestru rdx.
        xor     rax, rax

%endmacro


; Oblicza drugą część sumy Sj.
; Pierwszy argument to rejestr na sumę, a drugi to wartość j.
; Korzysta z rejestrów rax, rdx, r10, rcx, rsi.
%macro Sj_II 2
        xor     rsi, rsi
        xor     r10, r10
        xor     rax, rax
        xor     rcx, rcx
        xor     rdx, rdx                ; Zeruje zmienne.

        mov     rcx, m                  ; n
        inc     rcx                     ; n + 1
        shl     rcx, 3                  ; 8k            dla k = n + 1
        add     rcx, %2                 ; 8k + j        dla k = n + 1
        mov     rsi, rcx

        xor     rax, rax
        xor     rcx, rcx                ; iterator nie jest już potrzebny

        mov     r10, 16                 ; czynnik przez który będzie mnożony mianownik co obrót pętli

%%loop:
        mov     rax, r10                ; Mianownik, aktualnie wynosi 16^n-k.
        mul     rsi
        cmp     rdx, 0                  ; Sprawdza czy mianownik jest mniejszy niż 2^64.
        jne     %%finished              ; Jeżeli nie, przerywam sumowanie.

        mov     rcx, rax                ; Przenosi wartość mianownika, bo rejestr rax będzie potrzebny przy dzieleniu.
        xor     rax, rax
        mov     rdx, 1                  ; 1 w liczniku przesunięte w lewo o 64 bity.

        div     rcx                     ; 1 / (16^(n-k) * (8k + j))
        add     %1, rax                 ; Dodaje do całości wartość ułamka.

        shl     r10, 4                  ; Mnoży 16^n-k przez 16.
        add     rsi, 8                  ; Dodaje 8 do 8k + j.
        
        jmp     %%loop                  ; Przechodzi do następnej iteracji sumy.

%%finished:
%endmacro


section .text

        ; void pix(uint32_t *ppi, uint64_t *pidx, uint64_t max);
        global pix


pix:
        preserve_registers              ; Zapisuje rejestry na stosie.
        get_pix_args                    ; Zapisuje do zmiennych argumenty funkcji.
        call_pix_time                   ; Rozpoczyna mierzenie czasu.

main_loop:
        get_inc_counter                 ; Pobiera i zwiększa indeks elementu w tablicy ppi.
        cmp     m, max                  ; Sprawdza czy wartość m jest większa lub równa max.
        jge     end_section             ; Jeżeli tak, funkcja kończy działanie.

        shl     m, 3                    ; Liczy 8 cyfr rozwinęcia dziesiętnego zamiast 1.
        xor     r9, r9
        xor     rdi, rdi

        mov     r9, 1                   ; Argument dla _calc_Sj, że liczone będzie S_1.
        call    _calc_Sj                ; Po wywołaniu w rejestrze r8 znajduje się S_1.

        shl     r8, 2                   ; 4 * S_1
        mov     rdi, r8                 ; Przenosi 4 S_1 do rdi.

        mov     r9, 4                   ; Argument dla _calc_Sj, że liczone będzie S_4.
        call    _calc_Sj                ; Po wywołaniu w rejestrze r8 znajduje się S_4.

        shl     r8, 1                   ; 2 * S_4
        sub     rdi, r8                 ; 4S_1 - 2S_4

        mov     r9, 5                   ; Argument dla _calc_Sj, że liczone będzie S_5.
        call    _calc_Sj                ; Po wywołaniu w rejestrze r8 znajduje się S_5.

        sub     rdi, r8                 ; 4S_1 - 2S_4 - S_5

        mov     r9, 6                   ; Argument dla _calc_Sj, że liczone będzie S_6.
        call    _calc_Sj                ; Po wywołaniu w rejestrze r8 znajduje się S_6.

        sub     rdi, r8                 ; 4S_1 - 2S_4 - S_5 - S_6

        shr     rdi, 32                 ; Pozbywa się 32 bitów, które służyły zwiększeniu precyzji obliczeń.
        shr     m, 1                    ; Dzieli m przez 2, aby odnieść się do opowiedniej komórki tablicy.

        mov     [ppi + m], edi          ; Przenosi obliczone rozwinięcie do tablicy.

        jmp     main_loop               ; Przechodzi do kolejnej iteracji.

end_section:
        call_pix_time                   ; Kończy mierzenie czasu.
        restore_registers               ; Przywraca ze stosu zapisane rejestry.
        
        ret


; Oblicza wartość sumy Sj dla zadanych argumentów.
; W rejestrze r8 znajduje się suma, a w r9 znajduje się wartość j. Sumy zostają wyliczone dla n = 8m.
; Korzysta z rejestrów r8, r9, rsi, rax, rcx, rdx, r10, r11, rbx.
_calc_Sj:
        xor     r8, r8                  ; Zeruje rejestr na sumę.

        Sj_I    r8, r9                  ; Oblicza pierwszą część sumy.

        Sj_II   r8, r9                  ; Oblicza drugą część sumy.

        ret