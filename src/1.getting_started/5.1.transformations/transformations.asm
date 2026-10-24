;---------------------------------------------------------------------------------------------------
; 5.1 Transformations
;---------------------------------------------------------------------------------------------------
; Moving vertices with a matrix instead of editing them. The vertex shader multiplies every
; position by `transform`, which the CPU builds each frame with includes/math.asm (what glm is to
; LearnOpenGL):
;
;   bottom right:  translate * rotate   spins in place, then moves
;   top left:      translate * scale    pulses in place, then moves
;
; Read right to left: the matrix nearest the vertex applies first. Swap the order in the first one
; and it orbits the centre instead of spinning.
;
; A mat4 is stored row by row, and the shader says so with `#pragma pack_matrix(row_major)`, so
; mul(M, v) in HLSL is M * v here.
;
; The maths is SSE: four floats to a register, so a row of a matrix is one load. math.asm's procs
; take vectors and matrices by address and floats in xmm registers, like any Win64 function.
include rt.inc
include d3d11.inc
include macros.asm
include math.asm
include learn\window.asm
include learn\shader.asm
include learn\gpu.asm

;---------------------------------------------------------------------------------------------------
.data
;---------------------------------------------------------------------------------------------------
; x, y, z, then u, v. D3D's texture coordinate (0, 0) is the image's top-left, where GL's is its
; bottom-left, so nothing is flipped on load.
align 4
rectangle_vertices real4 -0.5, -0.5, 0.0,   0.0, 1.0
                   real4  0.5, -0.5, 0.0,   1.0, 1.0
                   real4  0.5,  0.5, 0.0,   1.0, 0.0
                   real4 -0.5,  0.5, 0.0,   0.0, 0.0
rectangle_vertices_size equ $ - rectangle_vertices

rectangle_indices dword 0, 1, 2, 0, 2, 3
rectangle_indices_size equ $ - rectangle_indices

semantic_position byte "POSITION", 0
semantic_texcoord byte "TEXCOORD", 0
align 8
vertex_layout D3D11_INPUT_ELEMENT_DESC <offset semantic_position, 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D11_INPUT_PER_VERTEX_DATA, 0>
              D3D11_INPUT_ELEMENT_DESC <offset semantic_texcoord, 0, DXGI_FORMAT_R32G32_FLOAT, 0, 12, D3D11_INPUT_PER_VERTEX_DATA, 0>

object_constants struct
    transform mat4 <>
object_constants ends

align 4
z_axis vec3 <0.0, 0.0, 1.0>
bottom_right vec3 <0.5, -0.5, 0.0>
top_left vec3 <-0.5, 0.5, 0.0>

align 16
c object_constants <>
aspect mat4 <>                  ; squeezes x so a square stays square in a wide window
translation mat4 <>
rotation mat4 <>
scale_ mat4 <>
pulse vec3 <>
s shader <>
align 8
vb qword 0
ib qword 0
sampler qword 0
constants qword 0
textures qword 2 dup(0)
stride dword 20
offset_ dword 0
current_frame real4 0.0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11"

    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile our shader program
    ; ------------------------------------
    invoke shader_create, ADDR s, "src/1.getting_started/5.1.transformations/transformations.hlsl", ADDR vertex_layout, 2

    ; set up vertex data and textures
    ; -------------------------------
    invoke create_buffer, D3D11_BIND_VERTEX_BUFFER, ADDR rectangle_vertices, rectangle_vertices_size
    mov vb, rax
    invoke create_buffer, D3D11_BIND_INDEX_BUFFER, ADDR rectangle_indices, rectangle_indices_size
    mov ib, rax
    invoke filesystem_path, "resources/textures/container.jpg"
    invoke load_texture, rax, 0
    mov textures[0], rax
    invoke filesystem_path, "resources/textures/awesomeface.png"
    invoke load_texture, rax, 0
    mov textures[8], rax
    invoke create_constant_buffer, sizeof object_constants
    mov constants, rax

    ; aspect = scale(height / width, 1, 1)
    cvtsi2ss xmm1, scr_height
    cvtsi2ss xmm0, scr_width
    divss xmm1, xmm0
    movss pulse.x, xmm1
    storef pulse.y, 1.0
    storef pulse.z, 1.0
    invoke m4_scale, ADDR aspect, ADDR pulse

    ; render loop
    ; -----------
    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        ; per-frame time logic
        ; --------------------
        call get_time
        movss current_frame, xmm0

        ; render
        ; ------
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, 0
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, backbuffer_rtv, floats(0.2, 0.3, 0.3, 1.0)

        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 2, ADDR textures
        invoke shader_use, ADDR s
        invoke bind_constants, 0, constants
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR vb, ADDR stride, ADDR offset_
        vcall context, ID3D11DeviceContext_IASetIndexBuffer, ib, DXGI_FORMAT_R32_UINT, 0

        ; transform = aspect * translate(0.5, -0.5, 0) * rotate(time, z)
        invoke m4_translate, ADDR translation, ADDR bottom_right
        lea rcx, rotation
        movss xmm1, current_frame
        lea r8, z_axis
        call m4_rotate
        invoke m4_mul, ADDR c.transform, ADDR translation, ADDR rotation
        invoke m4_mul, ADDR c.transform, ADDR aspect, ADDR c.transform
        invoke update_buffer, constants, ADDR c, sizeof object_constants
        vcall context, ID3D11DeviceContext_DrawIndexed, 6, 0, 0

        ; transform = aspect * translate(-0.5, 0.5, 0) * scale(|sin(time)|)
        movss xmm0, current_frame
        call sinf
        andps xmm0, math_abs_mask
        movss pulse.x, xmm0
        movss pulse.y, xmm0
        movss pulse.z, xmm0
        invoke m4_translate, ADDR translation, ADDR top_left
        invoke m4_scale, ADDR scale_, ADDR pulse
        invoke m4_mul, ADDR c.transform, ADDR translation, ADDR scale_
        invoke m4_mul, ADDR c.transform, ADDR aspect, ADDR c.transform
        invoke update_buffer, constants, ADDR c, sizeof object_constants
        vcall context, ID3D11DeviceContext_DrawIndexed, 6, 0, 0

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
