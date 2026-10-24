;---------------------------------------------------------------------------------------------------
; 1. Colors
;---------------------------------------------------------------------------------------------------
; The colour we see is the light's colour times the colour the surface reflects. A coral object
; under white light stays coral; under green light it turns dark green, because coral reflects
; little green.
;
; The scene is the one the lighting chapter keeps: an object, and a small cube standing in for the
; light. The lamp has a shader of its own, so nothing done to the lighting ever darkens it.
;
; From here on the per-draw matrices are `transforms` (includes/learn/transforms.asm), in register
; b0 for every shader, and window_begin binds and clears the backbuffer and depth buffer.
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm
include learn\cube.asm
include learn\camera.asm
include learn\transforms.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; Mirrors `cbuffer colors` in colors.hlsl: a float3 fills a register only with the float after it.
colors_constants struct
    object_color vec3 <>
    pad0 real4 ?
    light_color vec3 <>
    pad1 real4 ?
colors_constants ends

align 4
camera_start vec3 <-1.0, 1.0, 4.0>
light_position vec3 <1.2, 1.0, 2.0>

align 16
t transforms <>
colors colors_constants <<1.0, 0.5, 0.31>, 0.0, <1.0, 1.0, 1.0>, 0.0>
lamp_color vec4 <1.0, 1.0, 1.0, 1.0>
model mat4 <>
lighting_shader shader <>
lamp_shader shader <>
cam camera <>
align 8
cube_vb qword 0
transforms_buffer qword 0
colors_buffer qword 0
lamp_buffer qword 0
stride dword cube_stride
offset_ dword 0

; timing
delta_time real4 0.0
last_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11"
    call window_create_depth

    ; build and compile our shader programs
    ; -------------------------------------
    invoke shader_create, ADDR lighting_shader, "src/2.lighting/1.colors/colors.hlsl", ADDR cube_layout, cube_layout_count
    invoke shader_create, ADDR lamp_shader, "src/2.lighting/1.colors/light_cube.hlsl", ADDR cube_layout, cube_layout_count

    ; set up vertex data and constant buffers
    ; ---------------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke create_constant_buffer, sizeof transforms
    mov transforms_buffer, rax
    invoke create_constant_buffer, sizeof colors_constants
    mov colors_buffer, rax
    invoke create_constant_buffer, sizeof vec4
    mov lamp_buffer, rax

    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -75.0
    movf xmm3, -10.0
    call camera_create

    ; render loop
    ; -----------
    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        ; per-frame time logic
        ; --------------------
        call get_time
        movss xmm1, xmm0
        subss xmm0, last_frame
        movss delta_time, xmm0
        movss last_frame, xmm1

        ; input
        ; -----
        invoke camera_process_input, ADDR cam, ADDR delta_time

        ; render
        ; ------
        invoke window_begin, floats(0.1, 0.1, 0.1, 1.0)
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR cube_vb, ADDR stride, ADDR offset_
        invoke bind_constants, 0, transforms_buffer
        invoke transforms_from_camera, ADDR t, ADDR cam

        ; the object: coral, under white light
        invoke update_buffer, colors_buffer, ADDR colors, sizeof colors_constants
        invoke shader_use, ADDR lighting_shader
        invoke bind_constants, 1, colors_buffer
        invoke m4_identity, ADDR model
        invoke draw_cube, transforms_buffer, ADDR t, ADDR model

        ; the lamp: a small white cube where the light is
        invoke update_buffer, lamp_buffer, ADDR lamp_color, sizeof vec4
        invoke shader_use, ADDR lamp_shader
        invoke bind_constants, 1, lamp_buffer
        lea rcx, model
        lea rdx, light_position
        movf xmm2, 0.2
        call m4_translate_scale
        invoke draw_cube, transforms_buffer, ADDR t, ADDR model

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
