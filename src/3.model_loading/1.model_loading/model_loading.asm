;---------------------------------------------------------------------------------------------------
; 1. Model loading
;---------------------------------------------------------------------------------------------------
; Up to now every shape was typed in. Real ones come from a modelling tool, as a file: here a
; backpack of about 68,000 triangles, stored as Wavefront .obj with its textures named in a .mtl
; beside it.
;
; includes/learn/model.asm reads it, playing the part Assimp and LearnOpenGL's Model class play
; there: positions, texture coordinates and normals, then faces that index into all three, then the
; material's textures. Once loaded it is one vertex buffer, drawn with the lighting from chapter 2;
; model_draw binds its diffuse texture to t0 and its specular to t1.
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm
include learn\camera.asm
include learn\transforms.asm
include learn\model.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; Mirrors `cbuffer light` in model_loading.hlsl.
light_constants struct
    position vec3 <>
    pad0 real4 ?
light_constants ends

align 4
camera_start vec3 <0.0, 0.5, 4.5>

align 16
t transforms <>
light light_constants <>
s shader <>
cam camera <>
backpack model <>
align 8
transforms_buffer qword 0
light_buffer qword 0
sampler qword 0

; timing
current_frame real4 0.0
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    invoke shader_create, ADDR s, "src/3.model_loading/1.model_loading/model_loading.hlsl", ADDR model_layout, model_layout_count

    ; load models
    ; -----------
    invoke model_load, ADDR backpack, "resources/objects/backpack/", "backpack.obj", 0

    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof light_constants
    mov light_buffer, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -90.0
    movf xmm3, -5.0
    call camera_create

    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        call get_time
        movss current_frame, xmm0
        movss xmm1, xmm0
        subss xmm0, last_frame
        movss delta_time, xmm0
        movss last_frame, xmm1

        invoke camera_process_input, ADDR cam, ADDR delta_time

        invoke window_begin, floats(0.05, 0.05, 0.05, 1.0)

        ; the backpack stays where it was modelled
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke m4_identity, ADDR t.model
        invoke m4_identity, ADDR t.normal_matrix
        invoke update_buffer, transforms_buffer, ADDR t, sizeof transforms

        ; the light circles in front of it: (3 cos(t / 2), 2, 3 sin(t / 2) + 2)
        movss xmm0, current_frame
        mulss xmm0, math_half
        call cosf
        movf xmm1, 3.0
        mulss xmm0, xmm1
        movss light.position.x, xmm0
        storef light.position.y, 2.0
        movss xmm0, current_frame
        mulss xmm0, math_half
        call sinf
        movf xmm1, 3.0
        mulss xmm0, xmm1
        movf xmm1, 2.0
        addss xmm0, xmm1
        movss light.position.z, xmm0
        invoke update_buffer, light_buffer, ADDR light, sizeof light_constants

        invoke shader_use, ADDR s
        invoke bind_constants, 0, transforms_buffer
        invoke bind_constants, 1, light_buffer
        invoke model_draw, ADDR backpack

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
