;---------------------------------------------------------------------------------------------------
; gpu: buffers, constants, textures and samplers
;---------------------------------------------------------------------------------------------------
; The D3D11 calls the early lessons write out, once each, gathered for the later ones:
;
;   create_buffer            an immutable vertex or index buffer (2.1 hello triangle)
;   create_constant_buffer   a constant buffer the CPU rewrites (3.1 shaders)
;   update_buffer            rewriting it (3.1 shaders)
;   bind_constants           the same constant buffer for every stage (5.1 transformations)
;   load_texture             an image file as a texture with mipmaps (4.1 textures)
;   create_sampler           filtering and wrapping (4.1 textures)
;   bind_texture             one texture in one register
;   unbind_textures          t0..t7 cleared, before drawing into a texture that was being read
;   set_viewport             the part of the render target drawn into
;   create_render_target     a texture to draw into and then read (5.1 framebuffers)
;   create_depth_buffer      a depth buffer of any size (5.1 framebuffers)
;   load_cubemap             six images as a cubemap (6.1 cubemaps)
;   load_hdr                 a Radiance .hdr as a float texture
;   create_shadow_sampler    a comparison sampler for shadow maps
;
; They work on the device and context that window_create made.
ifndef gpu_asm
gpu_asm = 0

include macros.asm
include cstr.asm
include print.asm
include image.asm
include learn\window.asm

.code
; rcx: bind flags, rdx: data, r8: size -> rax: ID3D11Buffer
;
; An immutable buffer: filled once at creation, never written by the CPU again.
align 16
create_buffer proc bind:qword, data:qword, data_size:qword
    local desc:D3D11_BUFFER_DESC, init:D3D11_SUBRESOURCE_DATA, buffer:qword
    invoke mem_zero, ADDR desc, sizeof D3D11_BUFFER_DESC
    mov eax, dword ptr data_size
    mov desc.ByteWidth, eax
    mov desc.Usage, D3D11_USAGE_IMMUTABLE
    mov eax, dword ptr bind
    mov desc.BindFlags, eax
    invoke mem_zero, ADDR init, sizeof D3D11_SUBRESOURCE_DATA
    mov rax, data
    mov init.pSysMem, rax
    vcall device, ID3D11Device_CreateBuffer, ADDR desc, ADDR init, ADDR buffer
    AssertHr
    mov rax, buffer
    ret
create_buffer endp

; rcx: size -> rax: ID3D11Buffer
;
; A constant buffer the CPU rewrites, usually every frame. Its size must be a multiple of 16
; bytes, the size of one HLSL register.
align 16
create_constant_buffer proc data_size:qword
    local desc:D3D11_BUFFER_DESC, buffer:qword
    invoke mem_zero, ADDR desc, sizeof D3D11_BUFFER_DESC
    mov eax, dword ptr data_size
    mov desc.ByteWidth, eax
    mov desc.Usage, D3D11_USAGE_DYNAMIC
    mov desc.BindFlags, D3D11_BIND_CONSTANT_BUFFER
    mov desc.CPUAccessFlags, D3D11_CPU_ACCESS_WRITE
    vcall device, ID3D11Device_CreateBuffer, ADDR desc, 0, ADDR buffer
    AssertHr
    mov rax, buffer
    ret
create_constant_buffer endp

; rcx: buffer, rdx: data, r8: size
;
; WRITE_DISCARD hands back fresh memory each time, so the GPU never waits on the CPU, and a draw
; already recorded keeps the values it saw.
align 16
update_buffer proc buffer:qword, data:qword, data_size:qword
    local mapped:D3D11_MAPPED_SUBRESOURCE
    vcall context, ID3D11DeviceContext_Map, buffer, 0, D3D11_MAP_WRITE_DISCARD, 0, ADDR mapped
    AssertHr
    invoke mem_copy, mapped.pData, data, data_size
    vcall context, ID3D11DeviceContext_Unmap, buffer, 0
    ret
update_buffer endp

; rcx: register (b0, b1, ...), rdx: buffer
;
; The same buffer in the same register for the vertex, geometry and pixel stages.
align 16
bind_constants proc slot:qword, buffer:qword
    vcall context, ID3D11DeviceContext_VSSetConstantBuffers, slot, 1, ADDR buffer
    vcall context, ID3D11DeviceContext_GSSetConstantBuffers, slot, 1, ADDR buffer
    vcall context, ID3D11DeviceContext_PSSetConstantBuffers, slot, 1, ADDR buffer
    ret
bind_constants endp

; rcx: path, rdx: 1 for colour data -> rax: ID3D11ShaderResourceView
;
; A 2D texture from an image file, with a full mip chain. `srgb`: the file stores colours, gamma
; encoded, and sampling should decode them to linear. Data such as normals or roughness is
; linear already.
align 16
load_texture proc path:qword, srgb:qword
    local img:image, desc:D3D11_TEXTURE2D_DESC, texture:qword, srv:qword, pitch:qword
    invoke image_load, ADDR img, path
    test rax, rax
    jnz loaded
        print "Texture failed to load at path: %s\n", path
        invoke ExitProcess, 1
    loaded:
    invoke mem_zero, ADDR desc, sizeof D3D11_TEXTURE2D_DESC
    mov eax, img._width
    mov desc._Width, eax
    mov eax, img.height
    mov desc.Height, eax
    mov desc.MipLevels, 0                   ; the whole chain
    mov desc.ArraySize, 1
    mov desc.Format, DXGI_FORMAT_R8G8B8A8_UNORM
    cmp srgb, 0
    je linear
        mov desc.Format, DXGI_FORMAT_R8G8B8A8_UNORM_SRGB
    linear:
    mov desc.SampleDesc.Count, 1
    ; Generating mips draws into the texture, so it is a render target too.
    mov desc.BindFlags, D3D11_BIND_SHADER_RESOURCE or D3D11_BIND_RENDER_TARGET
    mov desc.MiscFlags, D3D11_RESOURCE_MISC_GENERATE_MIPS
    vcall device, ID3D11Device_CreateTexture2D, ADDR desc, 0, ADDR texture
    AssertHr
    vcall device, ID3D11Device_CreateShaderResourceView, texture, 0, ADDR srv
    mov eax, img._width
    shl eax, 2
    mov pitch, rax
    vcall context, ID3D11DeviceContext_UpdateSubresource, texture, 0, 0, img.pixels, pitch, 0
    vcall context, ID3D11DeviceContext_GenerateMips, srv
    release texture                         ; the view keeps it alive
    mov rax, srv
    ret
load_texture endp

; rcx: register (t0, t1, ...), rdx: ID3D11ShaderResourceView, for the pixel shader
align 16
bind_texture proc slot:qword, srv:qword
    vcall context, ID3D11DeviceContext_PSSetShaderResources, slot, 1, ADDR srv
    ret
bind_texture endp

; Clears the pixel shader's texture registers t0..t7. A texture cannot be read and drawn into at
; once, so this runs before drawing into one that was just being read.
align 16
unbind_textures proc
    local views[8]:qword
    invoke mem_zero, ADDR views, 8 * 8
    vcall context, ID3D11DeviceContext_PSSetShaderResources, 0, 8, ADDR views
    ret
unbind_textures endp

; rcx: width, rdx: height (pixels). Draw into that much of the render target.
align 16
set_viewport proc w:qword, h:qword
    local vp:D3D11_VIEWPORT
    invoke mem_zero, ADDR vp, sizeof D3D11_VIEWPORT
    cvtsi2ss xmm0, dword ptr w
    movss vp._Width, xmm0
    cvtsi2ss xmm0, dword ptr h
    movss vp.Height, xmm0
    storef vp.MaxDepth, 1.0
    vcall context, ID3D11DeviceContext_RSSetViewports, 1, ADDR vp
    ret
set_viewport endp

; A texture that can be drawn into (rtv) and then read (srv): GL's framebuffer colour attachment.
render_target struct
    texture qword ?     ; ID3D11Texture2D
    rtv qword ?         ; ID3D11RenderTargetView
    srv qword ?         ; ID3D11ShaderResourceView
render_target ends

; rcx: &render_target, rdx: width, r8: height, r9: format, [rsp+32]: samples (1 unless MSAA)
align 16
create_render_target proc out_ref:qword, w:qword, h:qword, format:qword, samples:qword
    local desc:D3D11_TEXTURE2D_DESC
    USING rbx
    SaveRegs
    mov rbx, out_ref
    invoke mem_zero, ADDR desc, sizeof D3D11_TEXTURE2D_DESC
    mov eax, dword ptr w
    mov desc._Width, eax
    mov eax, dword ptr h
    mov desc.Height, eax
    mov desc.MipLevels, 1
    mov desc.ArraySize, 1
    mov eax, dword ptr format
    mov desc.Format, eax
    mov eax, dword ptr samples
    mov desc.SampleDesc.Count, eax
    mov desc.BindFlags, D3D11_BIND_RENDER_TARGET or D3D11_BIND_SHADER_RESOURCE
    lea rax, [rbx].render_target.texture
    vcall device, ID3D11Device_CreateTexture2D, ADDR desc, 0, rax
    AssertHr
    lea rax, [rbx].render_target.rtv
    vcall device, ID3D11Device_CreateRenderTargetView, qword ptr [rbx].render_target.texture, 0, rax
    lea rax, [rbx].render_target.srv
    vcall device, ID3D11Device_CreateShaderResourceView, qword ptr [rbx].render_target.texture, 0, rax
    RestoreRegs
    ret
create_render_target endp

; rcx: width, rdx: height, r8: samples -> rax: ID3D11DepthStencilView of a new depth buffer,
; 24 bits of depth and 8 of stencil
align 16
create_depth_buffer proc w:qword, h:qword, samples:qword
    local desc:D3D11_TEXTURE2D_DESC, texture:qword, dsv:qword
    invoke mem_zero, ADDR desc, sizeof D3D11_TEXTURE2D_DESC
    mov eax, dword ptr w
    mov desc._Width, eax
    mov eax, dword ptr h
    mov desc.Height, eax
    mov desc.MipLevels, 1
    mov desc.ArraySize, 1
    mov desc.Format, DXGI_FORMAT_D24_UNORM_S8_UINT
    mov eax, dword ptr samples
    mov desc.SampleDesc.Count, eax
    mov desc.BindFlags, D3D11_BIND_DEPTH_STENCIL
    vcall device, ID3D11Device_CreateTexture2D, ADDR desc, 0, ADDR texture
    AssertHr
    vcall device, ID3D11Device_CreateDepthStencilView, texture, 0, ADDR dsv
    release texture                         ; the view keeps it alive
    mov rax, dsv
    ret
create_depth_buffer endp

; rcx: six image paths (an array of pointers: +x, -x, +y, -y, +z, -z) -> rax: a cubemap's view
;
; A cubemap is a texture array of six squares with a flag saying it is a cube; its faces are in
; the same order as GL's.
align 16
load_cubemap proc paths:qword
    local data[6]:D3D11_SUBRESOURCE_DATA, img:image, desc:D3D11_TEXTURE2D_DESC, view:D3D11_SHADER_RESOURCE_VIEW_DESC
    local texture:qword, srv:qword, face_size:dword
    USING rbx, rsi
    SaveRegs
    xor ebx, ebx
    lea rsi, data
    faces:
        mov rax, paths
        mov rdx, [rax + rbx * 8]
        invoke image_load, ADDR img, rdx
        test rax, rax
        jnz loaded
            mov rax, paths
            mov rdx, [rax + rbx * 8]
            print "Cubemap texture failed to load at path: %s\n", rdx
            invoke ExitProcess, 1
        loaded:
        mov [rsi].D3D11_SUBRESOURCE_DATA.pSysMem, rax
        mov eax, img._width
        mov face_size, eax
        shl eax, 2
        mov [rsi].D3D11_SUBRESOURCE_DATA.SysMemPitch, eax
        mov [rsi].D3D11_SUBRESOURCE_DATA.SysMemSlicePitch, 0
        add rsi, sizeof D3D11_SUBRESOURCE_DATA
        inc ebx
        cmp ebx, 6
        jb faces
    invoke mem_zero, ADDR desc, sizeof D3D11_TEXTURE2D_DESC
    mov eax, face_size
    mov desc._Width, eax
    mov desc.Height, eax
    mov desc.MipLevels, 1
    mov desc.ArraySize, 6
    mov desc.Format, DXGI_FORMAT_R8G8B8A8_UNORM
    mov desc.SampleDesc.Count, 1
    mov desc.BindFlags, D3D11_BIND_SHADER_RESOURCE
    mov desc.MiscFlags, D3D11_RESOURCE_MISC_TEXTURECUBE
    vcall device, ID3D11Device_CreateTexture2D, ADDR desc, ADDR data, ADDR texture
    AssertHr
    invoke mem_zero, ADDR view, sizeof D3D11_SHADER_RESOURCE_VIEW_DESC
    mov view.Format, DXGI_FORMAT_R8G8B8A8_UNORM
    mov view.ViewDimension, D3D11_SRV_DIMENSION_TEXTURECUBE
    mov view.TextureCube.MipLevels, 1
    vcall device, ID3D11Device_CreateShaderResourceView, texture, ADDR view, ADDR srv
    release texture
    mov rax, srv
    RestoreRegs
    ret
load_cubemap endp

; rcx: path of a Radiance .hdr -> rax: its view, as linear float RGBA
align 16
load_hdr proc path:qword
    local img:image, desc:D3D11_TEXTURE2D_DESC, init:D3D11_SUBRESOURCE_DATA, texture:qword, srv:qword
    invoke image_load_hdr, ADDR img, path
    test rax, rax
    jnz loaded
        print "Failed to load HDR image: %s\n", path
        invoke ExitProcess, 1
    loaded:
    invoke mem_zero, ADDR desc, sizeof D3D11_TEXTURE2D_DESC
    mov eax, img._width
    mov desc._Width, eax
    mov eax, img.height
    mov desc.Height, eax
    mov desc.MipLevels, 1
    mov desc.ArraySize, 1
    mov desc.Format, DXGI_FORMAT_R32G32B32A32_FLOAT
    mov desc.SampleDesc.Count, 1
    mov desc.BindFlags, D3D11_BIND_SHADER_RESOURCE
    invoke mem_zero, ADDR init, sizeof D3D11_SUBRESOURCE_DATA
    mov rax, img.pixels
    mov init.pSysMem, rax
    mov eax, img._width
    shl eax, 4                              ; 16 bytes a pixel
    mov init.SysMemPitch, eax
    vcall device, ID3D11Device_CreateTexture2D, ADDR desc, ADDR init, ADDR texture
    AssertHr
    vcall device, ID3D11Device_CreateShaderResourceView, texture, 0, ADDR srv
    release texture
    mov rax, srv
    ret
load_hdr endp

; -> rax: a sampler that compares instead of filtering, for shadow maps: hardware PCF. Outside the
; map the border is 1, the far plane, so nothing there is in shadow.
align 16
create_shadow_sampler proc
    local desc:D3D11_SAMPLER_DESC, sampler:qword
    invoke mem_zero, ADDR desc, sizeof D3D11_SAMPLER_DESC
    mov desc.Filter, D3D11_FILTER_COMPARISON_MIN_MAG_LINEAR_MIP_POINT
    mov desc.AddressU, D3D11_TEXTURE_ADDRESS_BORDER
    mov desc.AddressV, D3D11_TEXTURE_ADDRESS_BORDER
    mov desc.AddressW, D3D11_TEXTURE_ADDRESS_BORDER
    mov desc.ComparisonFunc, D3D11_COMPARISON_LESS_EQUAL
    mov eax, 3F800000h                      ; 1.0
    mov dword ptr desc.BorderColor[0], eax
    mov dword ptr desc.BorderColor[4], eax
    mov dword ptr desc.BorderColor[8], eax
    mov dword ptr desc.BorderColor[12], eax
    mov dword ptr desc.MaxLOD, 7F7FFFFFh    ; D3D11_FLOAT32_MAX
    vcall device, ID3D11Device_CreateSamplerState, ADDR desc, ADDR sampler
    AssertHr
    mov rax, sampler
    ret
create_shadow_sampler endp

; rcx: filter, rdx: address mode -> rax: ID3D11SamplerState
;
; How textures are filtered, and what happens past their edges.
align 16
create_sampler proc filter:qword, address:qword
    local desc:D3D11_SAMPLER_DESC, sampler:qword
    invoke mem_zero, ADDR desc, sizeof D3D11_SAMPLER_DESC
    mov eax, dword ptr filter
    mov desc.Filter, eax
    mov eax, dword ptr address
    mov desc.AddressU, eax
    mov desc.AddressV, eax
    mov desc.AddressW, eax
    mov desc.MaxAnisotropy, 8
    mov desc.ComparisonFunc, D3D11_COMPARISON_NEVER
    mov dword ptr desc.MaxLOD, 7F7FFFFFh    ; D3D11_FLOAT32_MAX
    vcall device, ID3D11Device_CreateSamplerState, ADDR desc, ADDR sampler
    AssertHr
    mov rax, sampler
    ret
create_sampler endp

endif
