;---------------------------------------------------------------------------------------------------
; 4.1 Textures
;---------------------------------------------------------------------------------------------------
; An image on a rectangle. Each vertex says where in the image it sits, its texture coordinate,
; 0..1 across and down, and the pixel shader samples the image there. Two textures are blended:
; the crate, with 20% of the face.
;
; load_texture (includes/learn/gpu.asm) decodes the file with includes/image.asm (WIC, Windows' own
; codecs) into RGBA8 pixels, uploads them, and has the GPU generate the mipmaps from the first
; level. A sampler, a separate object in D3D, decides how the texture is filtered and what happens
; past its edges: create_sampler.
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

align 16
s shader <>
align 8
vb qword 0
ib qword 0
sampler qword 0
textures qword 2 dup(0)
stride dword 20
offset_ dword 0

;---------------------------------------------------------------------------------------------------
.code
;---------------------------------------------------------------------------------------------------
align 16
main proc
    invoke window_create, "LearnD3D11"

    ; A sampler: how textures are filtered and what happens past their edges. Anisotropic
    ; filtering stays sharp on surfaces seen at a slant; wrap repeats the image.
    invoke create_sampler, D3D11_FILTER_ANISOTROPIC, D3D11_TEXTURE_ADDRESS_WRAP
    mov sampler, rax
    vcall context, ID3D11DeviceContext_PSSetSamplers, 0, 1, ADDR sampler

    ; build and compile our shader program
    ; ------------------------------------
    invoke shader_create, ADDR s, "src/1.getting_started/4.1.textures/textures.hlsl", ADDR vertex_layout, 2

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

    ; render loop
    ; -----------
    render_loop:
        call window_poll
        test eax, eax
        jz render_loop_done

        ; render
        ; ------
        vcall context, ID3D11DeviceContext_OMSetRenderTargets, 1, ADDR backbuffer_rtv, 0
        vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR viewport
        vcall context, ID3D11DeviceContext_ClearRenderTargetView, backbuffer_rtv, floats(0.2, 0.3, 0.3, 1.0)

        ; the two textures, in registers t0 and t1
        vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 2, ADDR textures
        invoke shader_use, ADDR s
        vcall context, ID3D11DeviceContext_IASetPrimitiveTopology, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST
        vcall context, ID3D11DeviceContext_IASetVertexBuffers, 0, 1, ADDR vb, ADDR stride, ADDR offset_
        vcall context, ID3D11DeviceContext_IASetIndexBuffer, ib, DXGI_FORMAT_R32_UINT, 0
        vcall context, ID3D11DeviceContext_DrawIndexed, 6, 0, 0

        call window_present
        jmp render_loop
    render_loop_done:

    invoke ExitProcess, 0
main endp

end
