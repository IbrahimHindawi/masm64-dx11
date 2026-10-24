;---------------------------------------------------------------------------------------------------
; cube: the unit cube most lessons draw
;---------------------------------------------------------------------------------------------------
; 36 vertices, two triangles a face, counter-clockwise from outside. Each vertex is a position, a
; normal and a texture coordinate, 32 bytes; `cube_layout` describes that to the input assembler.
; 6.1 coordinate systems introduces it.
;
; `cube_positions` are the ten places 6.1 scatters its cubes, which the lighting lessons reuse, and
; cube_model builds the model matrix of the i-th.
ifndef cube_asm
cube_asm = 0

include math.asm

.data
align 4
cube_vertices label byte
              ; right (+x)
              real4   0.5,  -0.5,   0.5,     1.0,   0.0,   0.0,   0.0, 1.0
              real4   0.5,  -0.5,  -0.5,     1.0,   0.0,   0.0,   1.0, 1.0
              real4   0.5,   0.5,  -0.5,     1.0,   0.0,   0.0,   1.0, 0.0
              real4   0.5,  -0.5,   0.5,     1.0,   0.0,   0.0,   0.0, 1.0
              real4   0.5,   0.5,  -0.5,     1.0,   0.0,   0.0,   1.0, 0.0
              real4   0.5,   0.5,   0.5,     1.0,   0.0,   0.0,   0.0, 0.0
              ; left (-x)
              real4  -0.5,  -0.5,  -0.5,    -1.0,   0.0,   0.0,   0.0, 1.0
              real4  -0.5,  -0.5,   0.5,    -1.0,   0.0,   0.0,   1.0, 1.0
              real4  -0.5,   0.5,   0.5,    -1.0,   0.0,   0.0,   1.0, 0.0
              real4  -0.5,  -0.5,  -0.5,    -1.0,   0.0,   0.0,   0.0, 1.0
              real4  -0.5,   0.5,   0.5,    -1.0,   0.0,   0.0,   1.0, 0.0
              real4  -0.5,   0.5,  -0.5,    -1.0,   0.0,   0.0,   0.0, 0.0
              ; top (+y)
              real4  -0.5,   0.5,   0.5,     0.0,   1.0,   0.0,   0.0, 1.0
              real4   0.5,   0.5,   0.5,     0.0,   1.0,   0.0,   1.0, 1.0
              real4   0.5,   0.5,  -0.5,     0.0,   1.0,   0.0,   1.0, 0.0
              real4  -0.5,   0.5,   0.5,     0.0,   1.0,   0.0,   0.0, 1.0
              real4   0.5,   0.5,  -0.5,     0.0,   1.0,   0.0,   1.0, 0.0
              real4  -0.5,   0.5,  -0.5,     0.0,   1.0,   0.0,   0.0, 0.0
              ; bottom (-y)
              real4  -0.5,  -0.5,  -0.5,     0.0,  -1.0,   0.0,   0.0, 1.0
              real4   0.5,  -0.5,  -0.5,     0.0,  -1.0,   0.0,   1.0, 1.0
              real4   0.5,  -0.5,   0.5,     0.0,  -1.0,   0.0,   1.0, 0.0
              real4  -0.5,  -0.5,  -0.5,     0.0,  -1.0,   0.0,   0.0, 1.0
              real4   0.5,  -0.5,   0.5,     0.0,  -1.0,   0.0,   1.0, 0.0
              real4  -0.5,  -0.5,   0.5,     0.0,  -1.0,   0.0,   0.0, 0.0
              ; front (+z)
              real4  -0.5,  -0.5,   0.5,     0.0,   0.0,   1.0,   0.0, 1.0
              real4   0.5,  -0.5,   0.5,     0.0,   0.0,   1.0,   1.0, 1.0
              real4   0.5,   0.5,   0.5,     0.0,   0.0,   1.0,   1.0, 0.0
              real4  -0.5,  -0.5,   0.5,     0.0,   0.0,   1.0,   0.0, 1.0
              real4   0.5,   0.5,   0.5,     0.0,   0.0,   1.0,   1.0, 0.0
              real4  -0.5,   0.5,   0.5,     0.0,   0.0,   1.0,   0.0, 0.0
              ; back (-z)
              real4   0.5,  -0.5,  -0.5,     0.0,   0.0,  -1.0,   0.0, 1.0
              real4  -0.5,  -0.5,  -0.5,     0.0,   0.0,  -1.0,   1.0, 1.0
              real4  -0.5,   0.5,  -0.5,     0.0,   0.0,  -1.0,   1.0, 0.0
              real4   0.5,  -0.5,  -0.5,     0.0,   0.0,  -1.0,   0.0, 1.0
              real4  -0.5,   0.5,  -0.5,     0.0,   0.0,  -1.0,   1.0, 0.0
              real4   0.5,   0.5,  -0.5,     0.0,   0.0,  -1.0,   0.0, 0.0
cube_stride equ 32
cube_vertices_size equ 36 * cube_stride
.erre ($ - cube_vertices) eq cube_vertices_size

cube_semantic_position byte "POSITION", 0
cube_semantic_normal byte "NORMAL", 0
cube_semantic_texcoord byte "TEXCOORD", 0
align 8
cube_layout D3D11_INPUT_ELEMENT_DESC <offset cube_semantic_position, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0>
            D3D11_INPUT_ELEMENT_DESC <offset cube_semantic_normal, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0>
            D3D11_INPUT_ELEMENT_DESC <offset cube_semantic_texcoord, 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D11_INPUT_PER_VERTEX_DATA, 0>
cube_layout_count equ 3

; world space positions of our cubes
align 4
cube_positions vec3 <0.0, 0.0, 0.0>
               vec3 <2.0, 5.0, -15.0>
               vec3 <-1.5, -2.2, -2.5>
               vec3 <-3.8, -2.0, -12.3>
               vec3 <2.4, -0.4, -3.5>
               vec3 <-1.7, 3.0, -7.5>
               vec3 <1.3, -2.0, -2.5>
               vec3 <1.5, 2.0, -2.5>
               vec3 <1.5, 0.2, -1.5>
               vec3 <-1.3, 1.0, -1.5>
cube_rotation_axis vec3 <1.0, 0.3, 0.5>

.code
; rcx: out mat4, rdx: i (0..9) -> translate(cube_positions[i]) * rotate(radians(20 i), (1, 0.3, 0.5))
align 16
cube_model proc out_ref:qword, index:qword
    local translation:mat4
    cvtsi2ss xmm0, dword ptr index
    movf xmm1, 20.0
    mulss xmm0, xmm1
    call radians
    movaps xmm1, xmm0
    mov rcx, out_ref
    lea r8, cube_rotation_axis
    call m4_rotate
    imul eax, dword ptr index, sizeof vec3
    lea rdx, cube_positions
    add rdx, rax
    lea rcx, translation
    call m4_translate
    invoke m4_mul, out_ref, ADDR translation, out_ref
    ret
cube_model endp

endif
