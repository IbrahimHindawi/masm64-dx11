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
