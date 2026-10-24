;---------------------------------------------------------------------------------------------------
; 9.1 Geometry shader
;---------------------------------------------------------------------------------------------------
; A stage between the vertex and pixel shaders that sees whole primitives, and may emit different
; ones: more, fewer, or of another kind.
;
;   exploding  each triangle is pushed out along its own face normal, by an amount that pulses
;              over time. The geometry shader can do this because it has all three corners; a
;              vertex shader sees one
;   normals    a second pass over the same model, whose geometry shader turns each triangle into
;              three short lines, one along each corner's normal: a quick way to check that a
;              model's normals are right
;
; shader_create compiles gs_main when a file has one, and shader_use binds it, or unbinds it when
; there is none.
;
;   Tab   whole / exploding / whole with normals
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
align 4
camera_start vec3 <0.0, 0.5, 4.5>

align 16
t transforms <>
amount real4 0.0, 0.0, 0.0, 0.0         ; mirrors `cbuffer explode`: 0 whole, 1 pushed out
explode shader <>
normals shader <>
cam camera <>
backpack model <>
align 8
transforms_buffer qword 0
amount_buffer qword 0
sampler qword 0
mode dword 0

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
    invoke window_mode_default, 2

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    invoke shader_create, ADDR explode, "src/4.advanced_d3d11/9.1.geometry_shader/explode.hlsl", ADDR model_layout, model_layout_count
    invoke shader_create, ADDR normals, "src/4.advanced_d3d11/9.1.geometry_shader/normal_visualization.hlsl", ADDR model_layout, model_layout_count
    invoke model_load, ADDR backpack, "resources/objects/backpack/", "backpack.obj", 0
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, 16
    mov amount_buffer, rax

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
        invoke window_mode, 3
        mov mode, eax

        invoke window_begin, floats(0.05, 0.05, 0.05, 1.0)
        invoke transforms_from_camera, ADDR t, ADDR cam
        invoke m4_identity, ADDR t.model
        invoke m4_identity, ADDR t.normal_matrix
        invoke update_buffer, transforms_buffer, ADDR t, sizeof transforms
        invoke bind_constants, 0, transforms_buffer

        ; exploding: amount = (sin(2 t) + 1) / 2; otherwise whole
        mov amount, 0
        cmp mode, 1
        jne whole
            movss xmm0, current_frame
            addss xmm0, xmm0
            call sinf
            addss xmm0, math_one
            mulss xmm0, math_half
            movss amount, xmm0
        whole:
        invoke update_buffer, amount_buffer, ADDR amount, 16
        invoke shader_use, ADDR explode
        invoke bind_constants, 1, amount_buffer
        invoke model_draw, ADDR backpack

        ; and again, as lines along the normals
        cmp mode, 2
        jne no_normals
            invoke shader_use, ADDR normals
            invoke model_draw, ADDR backpack
        no_normals:

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
