;---------------------------------------------------------------------------------------------------
; srgb: the back buffer seen as sRGB
;---------------------------------------------------------------------------------------------------
; From 5.3 on the shaders work in linear light and write linear values; an _SRGB render target view
; of the back buffer gamma-encodes them on the way in (5.2 gamma correction shows why).
;
;     invoke window_create, "LearnD3D11"
;     call window_use_srgb              ; backbuffer_rtv is now the sRGB view
ifndef srgb_asm
srgb_asm = 0

include macros.asm
include learn\window.asm

.code
align 16
window_use_srgb proc
    local view:D3D11_RENDER_TARGET_VIEW_DESC
    invoke mem_zero, ADDR view, sizeof D3D11_RENDER_TARGET_VIEW_DESC
    mov view.Format, DXGI_FORMAT_R8G8B8A8_UNORM_SRGB
    mov view.ViewDimension, D3D11_RTV_DIMENSION_TEXTURE2D
    release backbuffer_rtv
    vcall device, ID3D11Device_CreateRenderTargetView, backbuffer, ADDR view, ADDR backbuffer_rtv
    AssertHr
    ret
window_use_srgb endp

endif
