/*
 * iir.s - IIR Filter with SUBROUTINE structure
 *
 *  Created on: 29/7/2025
 *      Author: Ni Qingqing
 */
    .syntax unified
    .cpu cortex-m4
    .fpu softvfp
    .thumb

    .global iir

@ Start of executable code
.section .text

@ CG2028 Assignment 1, Sem 1, AY 2025/26
@ (c) ECE NUS, 2025

@ Write Student 1's Name here: Peng Ziyi
@ Write Student 2's Name here: Zhu Yangyi

    .equ    N_MAX, 10

    /* -------- Persistent state -------- */
    .bss
    .align  2
x_store:    .space  4*N_MAX         /* previous x values */
y_store:    .space  4*N_MAX         /* previous y values (UNSCALED) */
inited:     .word   0               /* one-time clear flag */

    .text
    .align  2
    .global iir
    .type   iir, %function

/* int iir(int N, int* b, int* a, int x_n)
   r0=N, r1=b, r2=a, r3=x_n  -> returns y[n]/100 in r0
*/
iir:
    PUSH    {R14}
    
    @ Pass all parameters to SUBROUTINE via registers
    @ R0 = N (already in R0)
    @ R1 = b pointer (already in R1)  
    @ R2 = a pointer (already in R2)
    @ R3 = x_n (already in R3)
    
    BL      SUBROUTINE
    
    @ Result is already in R0
    POP     {R14}
    BX      LR

SUBROUTINE:
    PUSH    {R4-R12, LR}
    
    @ Save parameters for later use
    MOV     R8,  R0            @ R8 = N
    MOV     R9,  R1            @ R9 = b pointer
    MOV     R10, R2            @ R10 = a pointer
    MOV     R11, R3            @ R11 = x_n
    
    @ ---------- One-time initialization ----------
    LDR     R0, =inited
    LDR     R1, [R0]
    CMP     R1, #0
    BNE     INIT_DONE
    
    @ Clear x_store
    LDR     R2, =x_store
    MOVS    R1, #0
    MOVS    R3, #N_MAX
CLEAR_X:
    STR     R1, [R2], #4
    SUBS    R3, R3, #1
    BNE     CLEAR_X
    
    @ Clear y_store
    LDR     R2, =y_store
    MOVS    R3, #N_MAX
CLEAR_Y:
    STR     R1, [R2], #4
    SUBS    R3, R3, #1
    BNE     CLEAR_Y
    
    @ Set inited flag
    MOVS    R1, #1
    STR     R1, [R0]
    
INIT_DONE:
    @ ---------- Get a[0] for division ----------
    LDR     R7, [R10]          @ R7 = a[0]
    
    @ ---------- Initialize accumulator: y = x_n * b[0] / a[0] ----------
    LDR     R0, [R9]           @ R0 = b[0]
    MUL     R4, R11, R0        @ R4 = x_n * b[0]
    SDIV    R4, R4, R7         @ R4 = (x_n * b[0]) / a[0]
    
    @ ---------- Set up for LOOP ----------
    MOVS    R5, #1             @ R5 = j = 1 (loop counter)
    
LOOP:
    @ Check if j > N
    CMP     R5, R8
    BGT     EXIT
    
    @ Calculate index for delay line access (j-1)
    SUB     R6, R5, #1         @ R6 = j-1
    
    @ ---------- Calculate b[j] * x_store[j-1] ----------
    @ Load b[j]
    LSL     R0, R5, #2         @ R0 = j * 4
    ADD     R0, R9, R0         @ R0 = address of b[j]
    LDR     R1, [R0]           @ R1 = b[j]
    
    @ Load x_store[j-1]
    LDR     R2, =x_store
    LSL     R0, R6, #2         @ R0 = (j-1) * 4
    ADD     R0, R2, R0         @ R0 = address of x_store[j-1]
    LDR     R2, [R0]           @ R2 = x_store[j-1]
    
    @ Multiply
    MUL     R12, R1, R2        @ R12 = b[j] * x_store[j-1]
    
    @ ---------- Calculate a[j] * y_store[j-1] ----------
    @ Load a[j]
    LSL     R0, R5, #2         @ R0 = j * 4
    ADD     R0, R10, R0        @ R0 = address of a[j]
    LDR     R1, [R0]           @ R1 = a[j]
    
    @ Load y_store[j-1]
    LDR     R2, =y_store
    LSL     R0, R6, #2         @ R0 = (j-1) * 4
    ADD     R0, R2, R0         @ R0 = address of y_store[j-1]
    LDR     R2, [R0]           @ R2 = y_store[j-1]
    
    @ Multiply
    MUL     R1, R1, R2         @ R1 = a[j] * y_store[j-1]
    
    @ ---------- Calculate term and accumulate ----------
    SUB     R12, R12, R1       @ R12 = b[j]*x[j-1] - a[j]*y[j-1]
    SDIV    R12, R12, R7       @ R12 = term / a[0]
    ADD     R4, R4, R12        @ R4 += term
    
    @ Increment j and continue loop
    ADD     R5, R5, #1
    B       LOOP
    
EXIT:
    @ ---------- Shift delay lines (from end to beginning) ----------
    MOV     R1, R8             @ R1 = N
    SUBS    R1, R1, #1         @ R1 = N-1
    BLE     NO_SHIFT           @ If N <= 1, skip shifting
    
SHIFT_LOOP:
    SUB     R2, R1, #1         @ R2 = j-1
    
    @ Shift x_store[j-1] to x_store[j]
    LDR     R3, =x_store
    LSL     R0, R2, #2         @ R0 = (j-1) * 4
    LDR     R5, [R3, R0]       @ R5 = x_store[j-1]
    LSL     R0, R1, #2         @ R0 = j * 4
    STR     R5, [R3, R0]       @ x_store[j] = x_store[j-1]
    
    @ Shift y_store[j-1] to y_store[j]
    LDR     R3, =y_store
    LSL     R0, R2, #2         @ R0 = (j-1) * 4
    LDR     R5, [R3, R0]       @ R5 = y_store[j-1]
    LSL     R0, R1, #2         @ R0 = j * 4
    STR     R5, [R3, R0]       @ y_store[j] = y_store[j-1]
    
    SUBS    R1, R1, #1         @ j--
    BNE     SHIFT_LOOP         @ Continue if j != 0
    
NO_SHIFT:
    @ ---------- Store new values at index 0 ----------
    LDR     R0, =x_store
    STR     R11, [R0]          @ x_store[0] = x_n
    
    LDR     R0, =y_store
    STR     R4, [R0]           @ y_store[0] = y_n (UNSCALED)
    
    @ ---------- Return y_n / 100 ----------
    MOV     R0, R4             @ R0 = unscaled y_n
    MOVS    R1, #100
    SDIV    R0, R0, R1         @ R0 = y_n / 100
    
    POP     {R4-R12, PC}       @ Return to iir function
