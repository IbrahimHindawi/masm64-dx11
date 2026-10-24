;---------------------------------------------------------------------------------------------------
; wall: a square with tangents, for normal and parallax mapping
;---------------------------------------------------------------------------------------------------
; Two triangles from (-1, -1) to (1, 1) at z = 0, facing +z. Each vertex is a position, a normal, a
; texture coordinate and a tangent: 44 bytes, described by `wall_layout`.
;
; The tangent of a triangle is the direction in which u grows. It is solved for from how position
; and uv change along two of its edges; both triangles of a flat square share it.
;
;     e1 = p1 - p0,  e2 = p2 - p0,  (du1, dv1), (du2, dv2) the uv changes along them
;     tangent = normalize((e1 dv2 - e2 dv1) / (du1 dv2 - du2 dv1))
ifndef wall_asm
wall_asm = 0

include macros.asm
include math.asm
include learn\gpu.asm

wall_stride equ 44

.data
wall_semantic_position byte "POSITION", 0
wall_semantic_normal byte "NORMAL", 0
wall_semantic_texcoord byte "TEXCOORD", 0
wall_semantic_tangent byte "TANGENT", 0
align 8
wall_layout D3D11_INPUT_ELEMENT_DESC <offset wall_semantic_position, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0>
            D3D11_INPUT_ELEMENT_DESC <offset wall_semantic_normal, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0>
            D3D11_INPUT_ELEMENT_DESC <offset wall_semantic_texcoord, 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D11_INPUT_PER_VERTEX_DATA, 0>
            D3D11_INPUT_ELEMENT_DESC <offset wall_semantic_tangent, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 32, D3D11_INPUT_PER_VERTEX_DATA, 0>
wall_layout_count equ 4

align 4
; the four corners and their texture coordinates
wall_corners vec3 <-1.0, -1.0, 0.0>, <1.0, -1.0, 0.0>, <1.0, 1.0, 0.0>, <-1.0, 1.0, 0.0>
wall_uvs vec2 <0.0, 1.0>, <1.0, 1.0>, <1.0, 0.0>, <0.0, 0.0>
; which corner each of the six vertices is
wall_order dword 0, 1, 2, 0, 2, 3

.code
; -> rax: the wall's vertex buffer, six vertices
align 16
create_wall proc
    local e1:vec3, e2:vec3, tangent:vec3, f:real4, vertices[66]:real4
    USING rbx, rsi, rdi
    SaveRegs
    ; edges
    lea rcx, e1
    lea rdx, wall_corners[1 * sizeof vec3]
    lea r8, wall_corners[0]
    call v3_sub
    lea rcx, e2
    lea rdx, wall_corners[2 * sizeof vec3]
    lea r8, wall_corners[0]
    call v3_sub
    ; du1 = xmm0, dv1 = xmm1, du2 = xmm2, dv2 = xmm3
    movss xmm0, wall_uvs[1 * sizeof vec2].x
    subss xmm0, wall_uvs[0].x
    movss xmm1, wall_uvs[1 * sizeof vec2].y
    subss xmm1, wall_uvs[0].y
    movss xmm2, wall_uvs[2 * sizeof vec2].x
    subss xmm2, wall_uvs[0].x
    movss xmm3, wall_uvs[2 * sizeof vec2].y
    subss xmm3, wall_uvs[0].y
    ; f = 1 / (du1 dv2 - du2 dv1)
    movss xmm4, xmm0
    mulss xmm4, xmm3
    movss xmm5, xmm2
    mulss xmm5, xmm1
    subss xmm4, xmm5
    movss xmm5, math_one
    divss xmm5, xmm4
    movss f, xmm5
    ; tangent = normalize((e1 dv2 - e2 dv1) f)
    v3load xmm4, e1
    shufps xmm3, xmm3, 0
    mulps xmm4, xmm3
    v3load xmm5, e2
    shufps xmm1, xmm1, 0
    mulps xmm5, xmm1
    subps xmm4, xmm5
    movss xmm5, f
    shufps xmm5, xmm5, 0
    mulps xmm4, xmm5
    v3store tangent, xmm4
    lea rcx, tangent
    mov rdx, rcx
    call v3_normalize

    ; six vertices: position, normal (0, 0, 1), uv, tangent
    lea rdi, vertices
    lea rsi, wall_order
    xor ebx, ebx
    each_vertex:
        mov eax, [rsi + rbx * 4]
        lea rcx, wall_corners
        imul edx, eax, sizeof vec3
        v3load xmm0, [rcx + rdx]
        v3store [rdi], xmm0
        mov dword ptr [rdi + 12], 0
        mov dword ptr [rdi + 16], 0
        mov dword ptr [rdi + 20], 3F800000h
        lea rcx, wall_uvs
        mov rdx, [rcx + rax * 8]
        mov [rdi + 24], rdx
        v3load xmm0, tangent
        v3store [rdi + 32], xmm0
        add rdi, wall_stride
        inc ebx
        cmp ebx, 6
        jb each_vertex
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR vertices, 6 * wall_stride
    RestoreRegs
    ret
create_wall endp

endif
