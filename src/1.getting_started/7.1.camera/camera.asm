;---------------------------------------------------------------------------------------------------
; 7.1 Camera
;---------------------------------------------------------------------------------------------------
; The same ten cubes, seen through a camera you can fly. A camera is only a view matrix: a
; position, a direction to look in and which way is up, turned by look_at into the matrix that
; moves the world in front of it.
;
; The direction comes from two angles, yaw and pitch, which the mouse changes. Movement is scaled
; by the frame's duration, so the speed is the same at any frame rate. The camera is
; includes/learn/camera.asm, LearnOpenGL's Camera class; every lesson from here on uses it.
;
;   W A S D, Space, Shift   move
;   right mouse + drag      look
;   wheel                   zoom
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm
include learn\cube.asm
include learn\camera.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
align 4
camera_start vec3 <-1.5, 1.0, 4.0>

object_constants struct
    model mat4 <>
    view mat4 <>
    projection mat4 <>
object_constants ends

align 16
c object_constants <>
s shader <>
cam camera <>
align 8
cube_vb qword 0
sampler qword 0
constants qword 0
textures qword 2 dup(0)
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
    USING rbx
    SaveRegs
    invoke window_create, "LearnD3D11"
    call window_create_depth

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile our shader program
    ; ------------------------------------
    invoke shader_create, ADDR s, "src/1.getting_started/7.1.camera/camera.hlsl", ADDR cube_layout, cube_layout_count

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR cube_vertices, cube_vertices_size
    mov cube_vb, rax
    invoke filesystem_path, "resources/textures/container.jpg"
    invoke load_texture, rax, 0
    mov textures[0], rax
    invoke filesystem_path, "resources/textures/awesomeface.png"
    invoke load_texture, rax, 0
    mov textures[8], rax
    invoke create_constant_buffer, sizeof object_constants
    mov constants, rax

    ; camera
    ; ------
    lea rcx, cam
    lea rdx, camera_start
    movf xmm2, -70.0                        ; yaw
    movf xmm3, -10.0                        ; pitch
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
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, depth_dsv
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, backbuffer_rtv, floats(0.2, 0.3, 0.3, 1.0)
        movf xmm3, 1.0                          ; the depth, a float: xmm3
        vcall context, ID3D11DeviceContext_ClearDepthStencilView, depth_dsv, D3D11_CLEAR_DEPTH or D3D11_CLEAR_STENCIL, 0, 0

        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 2, ADDR textures
        invoke shader_use, ADDR s
        invoke bind_constants, 0, constants
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR cube_vb, ADDR stride, ADDR offset_

        ; view from the camera; projection with the camera's zoom as its field of view
        invoke camera_view, ADDR c.view, ADDR cam
        movf xmm0, 100.0
        movss real4 ptr [rsp + 32], xmm0        ; z_far
        movss xmm0, cam.zoom
        call radians
        movaps xmm1, xmm0                       ; fovy
        cvtsi2ss xmm2, scr_width
        cvtsi2ss xmm0, scr_height
        divss xmm2, xmm0                        ; aspect
        movf xmm3, 0.1                          ; z_near
        lea rcx, c.projection
        call m4_perspective

        xor ebx, ebx
        cubes:
            ; model = translate(cube_positions[i]) * rotate(radians(20 * i), (1, 0.3, 0.5))
            invoke cube_model, ADDR c.model, rbx
            invoke update_buffer, constants, ADDR c, sizeof object_constants
            vcall context, ID3D11DeviceContext_Draw, 36, 0
            inc ebx
            cmp ebx, 10
            jb cubes

        call window_present
        jmp render_loop
    render_loop_done:

    RestoreRegs
    invoke ExitProcess, 0
main endp

end
