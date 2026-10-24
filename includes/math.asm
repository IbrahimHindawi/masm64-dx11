;---------------------------------------------------------------------------------------------------
; math: vectors and 4x4 matrices, what glm is to LearnOpenGL
;---------------------------------------------------------------------------------------------------
; Conventions, chosen to match the maths in LearnOpenGL so its formulas carry over unchanged:
;
;   * right-handed world: +x right, +y up, the camera looks down -z
;   * column vectors: a point is transformed as `M * p`, so `T * R * S` scales first and
;     translates last
;   * clip-space depth runs 0..1, which is D3D's range (GL's is -1..1)
;
; A mat4 is stored row by row, `m[row * 4 + col]`. Every shader starts with
; `#pragma pack_matrix(row_major)`, which makes HLSL read the constant buffer the same way, so
; `mul(M, v)` in a shader is exactly `M * v` here.
;
; Calling convention: Win64, floats included. A float argument goes in the xmm register of its
; position (the second argument in xmm1, whatever the first one was), from the fifth on in the
; stack slots [rsp+32], [rsp+40], ... A float result comes back in xmm0. Vectors and matrices are
; passed by address, and results are written through `out`, which may be the same as an input.
;
; Only xmm0-xmm5 are used: xmm6-xmm15 belong to the caller.
ifndef math_asm
math_asm = 0

include macros.asm

vec2 struct
    x real4 ?
    y real4 ?
vec2 ends

vec3 struct
    x real4 ?
    y real4 ?
    z real4 ?
vec3 ends

vec4 struct
    x real4 ?
    y real4 ?
    z real4 ?
    w real4 ?
vec4 ends

mat4 struct
    m real4 16 dup(?)
mat4 ends

; xmm = vec3 in memory, in lanes x, y, z (w is 0)
v3load macro reg:req, mem:req
    movsd reg, qword ptr mem
    insertps reg, dword ptr mem[8], 20h
endm

; vec3 in memory = lanes x, y, z of xmm
v3store macro mem:req, reg:req
    movsd qword ptr mem, reg
    extractps dword ptr mem[8], reg, 2
endm

; xmm = the same float in every lane
splat macro reg:req
    shufps reg, reg, 0
endm

;---------------------------------------------------------------------------------------------------
.const
;---------------------------------------------------------------------------------------------------
align 16
math_sign_mask label xmmword            ; xor: flips the sign of every lane
    dword 4 dup(80000000h)
math_abs_mask label xmmword             ; and: clears it
    dword 4 dup(7FFFFFFFh)
math_one real4 1.0
math_half real4 0.5
math_degrees_to_radians real4 0.0174532925199433
math_pi real4 3.14159265358979

.code
;---------------------------------------------------------------------------------------------------
; scalars
;---------------------------------------------------------------------------------------------------
; xmm0: degrees -> xmm0: radians
align 16
radians proc
    mulss xmm0, math_degrees_to_radians
    ret
radians endp

; The x87 unit still has sine, cosine and tangent instructions, which saves writing polynomials.
; xmm0: angle in radians -> xmm0
align 16
sinf proc
    local t:real4
    movss t, xmm0
    fld t
    fsin
    fstp t
    movss xmm0, t
    ret
sinf endp

align 16
cosf proc
    local t:real4
    movss t, xmm0
    fld t
    fcos
    fstp t
    movss xmm0, t
    ret
cosf endp

align 16
tanf proc
    local t:real4
    movss t, xmm0
    fld t
    fptan                       ; leaves tan(x), then 1.0 on top
    fstp st(0)
    fstp t
    movss xmm0, t
    ret
tanf endp

; xmm0: x, xmm1: y -> xmm0: x to the power y, for x > 0. 2^(y * log2 x), with x87's log2 and 2^x.
align 16
powf proc
    local t:real4
    xorps xmm2, xmm2
    comiss xmm0, xmm2
    ja positive
        xorps xmm0, xmm0
        ret
    positive:
    movss t, xmm1
    fld t                       ; y
    movss t, xmm0
    fld t                       ; x, y
    fyl2x                       ; y * log2(x)
    fld st(0)
    frndint                     ; whole part
    fsub st(1), st(0)           ; whole, fraction
    fxch st(1)                  ; fraction, whole
    f2xm1                       ; 2^fraction - 1
    fld1
    faddp st(1), st(0)          ; 2^fraction, whole
    fscale                      ; 2^fraction * 2^whole
    fstp st(1)
    fstp t
    movss xmm0, t
    ret
powf endp

; xmm0: x, xmm1: lo, xmm2: hi -> xmm0
align 16
clampf proc
    maxss xmm0, xmm1
    minss xmm0, xmm2
    ret
clampf endp

;---------------------------------------------------------------------------------------------------
; vec3
;---------------------------------------------------------------------------------------------------
; rcx: out, rdx: a, r8: b
align 16
v3_add proc
    v3load xmm0, [rdx]
    v3load xmm1, [r8]
    addps xmm0, xmm1
    v3store [rcx], xmm0
    ret
v3_add endp

align 16
v3_sub proc
    v3load xmm0, [rdx]
    v3load xmm1, [r8]
    subps xmm0, xmm1
    v3store [rcx], xmm0
    ret
v3_sub endp

align 16
v3_mul proc
    v3load xmm0, [rdx]
    v3load xmm1, [r8]
    mulps xmm0, xmm1
    v3store [rcx], xmm0
    ret
v3_mul endp

; rcx: out, rdx: a, xmm2: s
align 16
v3_scale proc
    v3load xmm0, [rdx]
    splat xmm2
    mulps xmm0, xmm2
    v3store [rcx], xmm0
    ret
v3_scale endp

; rcx: a, rdx: b -> xmm0: a . b
align 16
v3_dot proc
    v3load xmm0, [rcx]
    v3load xmm1, [rdx]
    dpps xmm0, xmm1, 71h        ; multiply x, y, z; sum into lane 0
    ret
v3_dot endp

; rcx: out, rdx: a, r8: b. (a.y b.z - a.z b.y, a.z b.x - a.x b.z, a.x b.y - a.y b.x)
align 16
v3_cross proc
    v3load xmm0, [rdx]
    v3load xmm1, [r8]
    movaps xmm2, xmm0
    movaps xmm3, xmm1
    shufps xmm0, xmm0, 0C9h     ; a.yzx
    shufps xmm1, xmm1, 0D2h     ; b.zxy
    mulps xmm0, xmm1
    shufps xmm2, xmm2, 0D2h     ; a.zxy
    shufps xmm3, xmm3, 0C9h     ; b.yzx
    mulps xmm2, xmm3
    subps xmm0, xmm2
    v3store [rcx], xmm0
    ret
v3_cross endp

; rcx: a -> xmm0: |a|
align 16
v3_length proc
    v3load xmm0, [rcx]
    dpps xmm0, xmm0, 71h
    sqrtss xmm0, xmm0
    ret
v3_length endp

; rcx: out, rdx: a. A zero vector stays zero.
align 16
v3_normalize proc
    v3load xmm0, [rdx]
    movaps xmm1, xmm0
    dpps xmm1, xmm1, 7Fh        ; |a|^2 in every lane
    xorps xmm2, xmm2
    comiss xmm1, xmm2
    je done
    sqrtps xmm1, xmm1
    divps xmm0, xmm1
    done:
    v3store [rcx], xmm0
    ret
v3_normalize endp

; rcx: out, rdx: a, r8: b, xmm3: t -> a + (b - a) t
align 16
v3_lerp proc
    v3load xmm0, [rdx]
    v3load xmm1, [r8]
    subps xmm1, xmm0
    splat xmm3
    mulps xmm1, xmm3
    addps xmm0, xmm1
    v3store [rcx], xmm0
    ret
v3_lerp endp

; rcx: out, xmm1: x, xmm2: y, xmm3: z
align 16
v3_set proc
    movss [rcx].vec3.x, xmm1
    movss [rcx].vec3.y, xmm2
    movss [rcx].vec3.z, xmm3
    ret
v3_set endp

;---------------------------------------------------------------------------------------------------
; mat4
;---------------------------------------------------------------------------------------------------
; rcx: out
align 16
m4_identity proc
    xorps xmm0, xmm0
    movups [rcx], xmm0
    movups [rcx + 16], xmm0
    movups [rcx + 32], xmm0
    movups [rcx + 48], xmm0
    mov eax, 3F800000h          ; 1.0
    mov [rcx + 0], eax
    mov [rcx + 20], eax
    mov [rcx + 40], eax
    mov [rcx + 60], eax
    ret
m4_identity endp

; rcx: out, rdx: a, r8: b -> out = a * b
;
; Row i of the product is a[i][0] * b.row0 + a[i][1] * b.row1 + a[i][2] * b.row2 + a[i][3] * b.row3.
; b is read into registers first and each row of a is read before its row of out is written, so
; out may be a or b.
align 16
m4_mul proc
    movups xmm2, [r8]
    movups xmm3, [r8 + 16]
    movups xmm4, [r8 + 32]
    movups xmm5, [r8 + 48]
    for row, <0, 16, 32, 48>
        movss xmm0, dword ptr [rdx + row]
        splat xmm0
        mulps xmm0, xmm2
        movss xmm1, dword ptr [rdx + row + 4]
        splat xmm1
        mulps xmm1, xmm3
        addps xmm0, xmm1
        movss xmm1, dword ptr [rdx + row + 8]
        splat xmm1
        mulps xmm1, xmm4
        addps xmm0, xmm1
        movss xmm1, dword ptr [rdx + row + 12]
        splat xmm1
        mulps xmm1, xmm5
        addps xmm0, xmm1
        movups [rcx + row], xmm0
    endm
    ret
m4_mul endp

; rcx: out, rdx: m, r8: v -> out = m * v
align 16
m4_mul_v4 proc
    movups xmm4, [r8]
    movups xmm0, [rdx]
    mulps xmm0, xmm4
    movups xmm1, [rdx + 16]
    mulps xmm1, xmm4
    movups xmm2, [rdx + 32]
    mulps xmm2, xmm4
    movups xmm3, [rdx + 48]
    mulps xmm3, xmm4
    haddps xmm0, xmm1           ; row sums, two lanes at a time
    haddps xmm2, xmm3
    haddps xmm0, xmm2
    movups [rcx], xmm0
    ret
m4_mul_v4 endp

; rcx: out, rdx: a -> out = a transposed
align 16
m4_transpose proc
    movups xmm0, [rdx]
    movups xmm1, [rdx + 16]
    movups xmm2, [rdx + 32]
    movups xmm3, [rdx + 48]
    movaps xmm4, xmm0
    movaps xmm5, xmm2
    unpcklps xmm0, xmm1         ; a00 a10 a01 a11
    unpckhps xmm4, xmm1         ; a02 a12 a03 a13
    unpcklps xmm2, xmm3         ; a20 a30 a21 a31
    unpckhps xmm5, xmm3         ; a22 a32 a23 a33
    movaps xmm1, xmm0
    movlhps xmm0, xmm2          ; a00 a10 a20 a30
    movhlps xmm2, xmm1          ; a01 a11 a21 a31
    movaps xmm3, xmm4
    movlhps xmm4, xmm5          ; a02 a12 a22 a32
    movhlps xmm5, xmm3          ; a03 a13 a23 a33
    movups [rcx], xmm0
    movups [rcx + 16], xmm2
    movups [rcx + 32], xmm4
    movups [rcx + 48], xmm5
    ret
m4_transpose endp

; rcx: out, rdx: t (vec3) -> a translation by t
align 16
m4_translate proc
    mov r8, rdx
    call m4_identity
    mov eax, [r8].vec3.x
    mov [rcx + 12], eax
    mov eax, [r8].vec3.y
    mov [rcx + 28], eax
    mov eax, [r8].vec3.z
    mov [rcx + 44], eax
    ret
m4_translate endp

; rcx: out, rdx: s (vec3) -> a scale by s
align 16
m4_scale proc
    mov r8, rdx
    call m4_identity
    mov eax, [r8].vec3.x
    mov [rcx + 0], eax
    mov eax, [r8].vec3.y
    mov [rcx + 20], eax
    mov eax, [r8].vec3.z
    mov [rcx + 40], eax
    ret
m4_scale endp

; rcx: out, rdx: t (vec3), xmm2: s -> translate(t) * scale(s, s, s): an object of size s at t, such
; as the small cube that stands in for a light
align 16
m4_translate_scale proc
    mov r8, rdx
    call m4_identity
    movss real4 ptr [rcx + 0], xmm2
    movss real4 ptr [rcx + 20], xmm2
    movss real4 ptr [rcx + 40], xmm2
    mov eax, [r8].vec3.x
    mov [rcx + 12], eax
    mov eax, [r8].vec3.y
    mov [rcx + 28], eax
    mov eax, [r8].vec3.z
    mov [rcx + 44], eax
    ret
m4_translate_scale endp

; rcx: out, xmm1: angle in radians, r8: axis (vec3)
;
; A rotation of `angle` about `axis`, counter-clockwise when looking down the axis towards the
; origin.
align 16
m4_rotate proc out_ref:qword, angle:qword, axis_ref:qword
    local a:vec3, c:real4, s:real4, t:real4

    movss real4 ptr angle, xmm1 ; the prologue homed rdx here, not xmm1
    lea rcx, a
    mov rdx, axis_ref
    call v3_normalize
    movss xmm0, real4 ptr angle
    call cosf
    movss c, xmm0
    movss xmm1, math_one
    subss xmm1, xmm0
    movss t, xmm1
    movss xmm0, real4 ptr angle
    call sinf
    movss s, xmm0

    mov rcx, out_ref
    call m4_identity
    ; r.m[0] = c + a.x * a.x * t
    movss xmm0, a.x
    mulss xmm0, a.x
    mulss xmm0, t
    addss xmm0, c
    movss real4 ptr [rcx + 0], xmm0
    ; r.m[1] = a.x * a.y * t - a.z * s
    movss xmm0, a.x
    mulss xmm0, a.y
    mulss xmm0, t
    movss xmm1, a.z
    mulss xmm1, s
    subss xmm0, xmm1
    movss real4 ptr [rcx + 4], xmm0
    ; r.m[2] = a.x * a.z * t + a.y * s
    movss xmm0, a.x
    mulss xmm0, a.z
    mulss xmm0, t
    movss xmm1, a.y
    mulss xmm1, s
    addss xmm0, xmm1
    movss real4 ptr [rcx + 8], xmm0
    ; r.m[4] = a.y * a.x * t + a.z * s
    movss xmm0, a.y
    mulss xmm0, a.x
    mulss xmm0, t
    movss xmm1, a.z
    mulss xmm1, s
    addss xmm0, xmm1
    movss real4 ptr [rcx + 16], xmm0
    ; r.m[5] = c + a.y * a.y * t
    movss xmm0, a.y
    mulss xmm0, a.y
    mulss xmm0, t
    addss xmm0, c
    movss real4 ptr [rcx + 20], xmm0
    ; r.m[6] = a.y * a.z * t - a.x * s
    movss xmm0, a.y
    mulss xmm0, a.z
    mulss xmm0, t
    movss xmm1, a.x
    mulss xmm1, s
    subss xmm0, xmm1
    movss real4 ptr [rcx + 24], xmm0
    ; r.m[8] = a.z * a.x * t - a.y * s
    movss xmm0, a.z
    mulss xmm0, a.x
    mulss xmm0, t
    movss xmm1, a.y
    mulss xmm1, s
    subss xmm0, xmm1
    movss real4 ptr [rcx + 32], xmm0
    ; r.m[9] = a.z * a.y * t + a.x * s
    movss xmm0, a.z
    mulss xmm0, a.y
    mulss xmm0, t
    movss xmm1, a.x
    mulss xmm1, s
    addss xmm0, xmm1
    movss real4 ptr [rcx + 36], xmm0
    ; r.m[10] = c + a.z * a.z * t
    movss xmm0, a.z
    mulss xmm0, a.z
    mulss xmm0, t
    addss xmm0, c
    movss real4 ptr [rcx + 40], xmm0
    ret
m4_rotate endp

; rcx: out, xmm1: fovy in radians, xmm2: aspect, xmm3: z_near, [rsp+32]: z_far
;
; Right-handed perspective onto D3D's 0..1 depth range.
align 16
m4_perspective proc out_ref:qword, fovy:qword, aspect:qword, z_near:qword, z_far:qword
    movss real4 ptr aspect, xmm2
    movss real4 ptr z_near, xmm3
    movaps xmm0, xmm1
    mulss xmm0, math_half
    call tanf
    movss xmm1, math_one
    divss xmm1, xmm0            ; f = 1 / tan(fovy / 2)

    mov rcx, out_ref
    xorps xmm0, xmm0
    movups [rcx], xmm0
    movups [rcx + 16], xmm0
    movups [rcx + 32], xmm0
    movups [rcx + 48], xmm0
    movss xmm0, xmm1
    divss xmm0, real4 ptr aspect
    movss real4 ptr [rcx + 0], xmm0         ; f / aspect
    movss real4 ptr [rcx + 20], xmm1        ; f
    movss xmm2, real4 ptr z_near
    subss xmm2, real4 ptr z_far             ; near - far
    movss xmm0, real4 ptr z_far
    divss xmm0, xmm2
    movss real4 ptr [rcx + 40], xmm0        ; far / (near - far)
    movss xmm0, real4 ptr z_near
    mulss xmm0, real4 ptr z_far
    divss xmm0, xmm2
    movss real4 ptr [rcx + 44], xmm0        ; near * far / (near - far)
    mov dword ptr [rcx + 56], 0BF800000h    ; -1
    ret
m4_perspective endp

; rcx: out, xmm1: left, xmm2: right, xmm3: bottom, [rsp+32]: top, [rsp+40]: z_near, [rsp+48]: z_far
;
; Right-handed orthographic projection onto 0..1 depth.
align 16
m4_ortho proc out_ref:qword, left_:qword, right_:qword, bottom:qword, top:qword, z_near:qword, z_far:qword
    movss real4 ptr left_, xmm1
    movss real4 ptr right_, xmm2
    movss real4 ptr bottom, xmm3
    call m4_identity
    ; 2 / (right - left), -(right + left) / (right - left)
    movss xmm0, real4 ptr right_
    subss xmm0, real4 ptr left_
    movf xmm1, 2.0
    divss xmm1, xmm0
    movss real4 ptr [rcx + 0], xmm1
    movss xmm1, real4 ptr right_
    addss xmm1, real4 ptr left_
    divss xmm1, xmm0
    xorps xmm1, math_sign_mask
    movss real4 ptr [rcx + 12], xmm1
    ; 2 / (top - bottom), -(top + bottom) / (top - bottom)
    movss xmm0, real4 ptr top
    subss xmm0, real4 ptr bottom
    movf xmm1, 2.0
    divss xmm1, xmm0
    movss real4 ptr [rcx + 20], xmm1
    movss xmm1, real4 ptr top
    addss xmm1, real4 ptr bottom
    divss xmm1, xmm0
    xorps xmm1, math_sign_mask
    movss real4 ptr [rcx + 28], xmm1
    ; 1 / (near - far), near / (near - far)
    movss xmm0, real4 ptr z_near
    subss xmm0, real4 ptr z_far
    movss xmm1, math_one
    divss xmm1, xmm0
    movss real4 ptr [rcx + 40], xmm1
    movss xmm1, real4 ptr z_near
    divss xmm1, xmm0
    movss real4 ptr [rcx + 44], xmm1
    ret
m4_ortho endp

; rcx: out, rdx: eye, r8: target, r9: up (all vec3)
;
; The view matrix of a camera at `eye` looking at `target`.
align 16
m4_look_at proc out_ref:qword, eye:qword, target:qword, up:qword
    local f:vec3, s:vec3, u:vec3

    lea rcx, f                  ; f = normalize(target - eye)
    mov rdx, target
    mov r8, eye
    call v3_sub
    lea rcx, f
    lea rdx, f
    call v3_normalize
    lea rcx, s                  ; s = normalize(cross(f, up))
    lea rdx, f
    mov r8, up
    call v3_cross
    lea rcx, s
    lea rdx, s
    call v3_normalize
    lea rcx, u                  ; u = cross(s, f)
    lea rdx, s
    lea r8, f
    call v3_cross

    mov rcx, out_ref
    call m4_identity
    mov rdx, eye
    v3load xmm4, [rdx]
    ; row 0: s, -dot(s, eye)
    v3load xmm0, s
    movups [rcx], xmm0
    dpps xmm0, xmm4, 71h
    xorps xmm0, math_sign_mask
    movss real4 ptr [rcx + 12], xmm0
    ; row 1: u, -dot(u, eye)
    v3load xmm0, u
    movups [rcx + 16], xmm0
    dpps xmm0, xmm4, 71h
    xorps xmm0, math_sign_mask
    movss real4 ptr [rcx + 28], xmm0
    ; row 2: -f, dot(f, eye)
    v3load xmm0, f
    movaps xmm1, xmm0
    xorps xmm1, math_sign_mask
    movups [rcx + 32], xmm1
    dpps xmm0, xmm4, 71h
    movss real4 ptr [rcx + 44], xmm0
    ret
m4_look_at endp

; rcx: out, rdx: a -> a with its translation removed: what a skybox is drawn with, so it turns
; with the camera but never gets closer.
align 16
m4_without_translation proc
    movups xmm0, [rdx]
    movups xmm1, [rdx + 16]
    movups xmm2, [rdx + 32]
    movups [rcx], xmm0
    movups [rcx + 16], xmm1
    movups [rcx + 32], xmm2
    xor eax, eax
    mov [rcx + 12], eax
    mov [rcx + 28], eax
    mov [rcx + 44], eax
    mov [rcx + 48], eax
    mov [rcx + 52], eax
    mov [rcx + 56], eax
    mov dword ptr [rcx + 60], 3F800000h
    ret
m4_without_translation endp

; rcx: out, rdx: a -> the inverse of a. A singular matrix comes back unchanged.
;
; Gauss-Jordan elimination: [a | I] is row-reduced until the left half is I, which leaves the
; inverse on the right. Each step picks the largest remaining entry in the column as the pivot.
align 16
m4_inverse proc out_ref:qword, a_ref:qword
    local work[32]:real4        ; 4 rows of 8: a, then the identity
    USING rbx, rsi, rdi
    SaveRegs

    ; work = [a | I]
    lea r9, work
    mov rsi, a_ref
    xor ecx, ecx
    fill:
        mov rax, rcx
        shl rax, 5              ; row * 32 bytes
        mov rdx, rcx
        shl rdx, 4              ; row * 16 bytes
        movups xmm0, [rsi + rdx]
        movups [r9 + rax], xmm0
        xorps xmm0, xmm0
        movups [r9 + rax + 16], xmm0
        lea rdx, [rax + rcx * 4]
        mov dword ptr [r9 + rdx + 16], 3F800000h
        inc ecx
        cmp ecx, 4
        jb fill

    xor ebx, ebx                ; column
    columns:
        ; the pivot: the row from `column` down with the largest |entry|
        mov edi, ebx
        mov rax, rbx
        shl rax, 5
        lea r10, [r9 + rax]
        movss xmm1, real4 ptr [r10 + rbx * 4]
        andps xmm1, math_abs_mask
        lea esi, [ebx + 1]
        pivot_search:
            cmp esi, 4
            jae pivot_found
            mov rax, rsi
            shl rax, 5
            lea r10, [r9 + rax]
            movss xmm0, real4 ptr [r10 + rbx * 4]
            andps xmm0, math_abs_mask
            comiss xmm0, xmm1
            jbe not_larger
                movss xmm1, xmm0
                mov edi, esi
            not_larger:
            inc esi
            jmp pivot_search
        pivot_found:
        xorps xmm0, xmm0
        comiss xmm1, xmm0
        je singular

        ; swap the pivot row into place
        mov rax, rdi
        shl rax, 5
        mov rdx, rbx
        shl rdx, 5
        movups xmm0, [r9 + rax]
        movups xmm1, [r9 + rax + 16]
        movups xmm2, [r9 + rdx]
        movups xmm3, [r9 + rdx + 16]
        movups [r9 + rdx], xmm0
        movups [r9 + rdx + 16], xmm1
        movups [r9 + rax], xmm2
        movups [r9 + rax + 16], xmm3

        ; scale the pivot row so the pivot is 1
        movss xmm4, math_one
        lea r10, [r9 + rdx]
        divss xmm4, real4 ptr [r10 + rbx * 4]
        splat xmm4
        movups xmm0, [r9 + rdx]
        mulps xmm0, xmm4
        movups [r9 + rdx], xmm0
        movups xmm1, [r9 + rdx + 16]
        mulps xmm1, xmm4
        movups [r9 + rdx + 16], xmm1

        ; subtract it from every other row, clearing the column
        xor esi, esi
        eliminate:
            cmp esi, ebx
            je next_row
            mov rax, rsi
            shl rax, 5
            lea r10, [r9 + rax]
            movss xmm4, real4 ptr [r10 + rbx * 4]
            splat xmm4
            movaps xmm2, xmm0
            mulps xmm2, xmm4
            movups xmm3, [r9 + rax]
            subps xmm3, xmm2
            movups [r9 + rax], xmm3
            movaps xmm2, xmm1
            mulps xmm2, xmm4
            movups xmm3, [r9 + rax + 16]
            subps xmm3, xmm2
            movups [r9 + rax + 16], xmm3
            next_row:
            inc esi
            cmp esi, 4
            jb eliminate

        inc ebx
        cmp ebx, 4
        jb columns

    ; the right half is the inverse
    mov rcx, out_ref
    for row, <0, 1, 2, 3>
        movups xmm0, [r9 + row * 32 + 16]
        movups [rcx + row * 16], xmm0
    endm
    jmp done

    singular:
    mov rcx, out_ref
    mov rdx, a_ref
    for row, <0, 16, 32, 48>
        movups xmm0, [rdx + row]
        movups [rcx + row], xmm0
    endm

    done:
    RestoreRegs
    ret
m4_inverse endp

; rcx: out, rdx: model -> what normals are transformed by: the inverse transpose of the model
; matrix, so a non-uniform scale does not tilt them.
align 16
m4_normal_matrix proc out_ref:qword, model:qword
    invoke m4_inverse, out_ref, model
    mov rcx, out_ref
    mov rdx, rcx
    call m4_transpose
    ret
m4_normal_matrix endp

endif
