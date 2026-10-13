# OpenGL 3.2 feature + extension set — on-device query (Zink on PanVK)

## Context actually obtained

- Requested: desktop GL 3.2 core via EGL surfaceless (configless,
  `EGL_MESA_configless_context`), `MESA_GL_VERSION_OVERRIDE=3.2`,
  `MESA_GLSL_VERSION_OVERRIDE=150` so the driver reports the exact 3.2 view.
- Without the override the same request returns a 3.3 core context;
  the extension set is identical (215 extensions either way).
```
GL_VERSION: 3.2 (Core Profile) Mesa 26.1.6
GL_VENDOR: Mesa
GL_RENDERER: zink Vulkan 1.4(Mali unknown 0xa8671030 MC6 (MESA_PANVK))
GL_SHADING_LANGUAGE_VERSION: 1.50
GL_MAJOR_VERSION=3 GL_MINOR_VERSION=2 GL_NUM_EXTENSIONS=215
```

Maximum desktop GL on this device/driver is 3.3 core+compat (see
`OpenGL-4.5-4.6-Mali-PanVK-zink.md` for why 4.x is unavailable).

## Extensions (215)

```
  GL_AMD_conservative_depth
  GL_AMD_draw_buffers_blend
  GL_AMD_gpu_shader_int64
  GL_AMD_multi_draw_indirect
  GL_AMD_performance_monitor
  GL_AMD_query_buffer_object
  GL_AMD_seamless_cubemap_per_texture
  GL_AMD_shader_stencil_export
  GL_AMD_shader_trinary_minmax
  GL_AMD_texture_texture4
  GL_ANGLE_texture_compression_dxt3
  GL_ANGLE_texture_compression_dxt5
  GL_ARB_ES2_compatibility
  GL_ARB_ES3_1_compatibility
  GL_ARB_ES3_compatibility
  GL_ARB_arrays_of_arrays
  GL_ARB_base_instance
  GL_ARB_bindless_texture
  GL_ARB_blend_func_extended
  GL_ARB_buffer_storage
  GL_ARB_clear_buffer_object
  GL_ARB_clear_texture
  GL_ARB_clip_control
  GL_ARB_compressed_texture_pixel_storage
  GL_ARB_compute_shader
  GL_ARB_compute_variable_group_size
  GL_ARB_conditional_render_inverted
  GL_ARB_conservative_depth
  GL_ARB_copy_buffer
  GL_ARB_copy_image
  GL_ARB_debug_output
  GL_ARB_depth_buffer_float
  GL_ARB_depth_clamp
  GL_ARB_derivative_control
  GL_ARB_direct_state_access
  GL_ARB_draw_buffers
  GL_ARB_draw_buffers_blend
  GL_ARB_draw_elements_base_vertex
  GL_ARB_draw_indirect
  GL_ARB_draw_instanced
  GL_ARB_enhanced_layouts
  GL_ARB_explicit_attrib_location
  GL_ARB_explicit_uniform_location
  GL_ARB_fragment_coord_conventions
  GL_ARB_fragment_shader
  GL_ARB_framebuffer_no_attachments
  GL_ARB_framebuffer_object
  GL_ARB_framebuffer_sRGB
  GL_ARB_get_program_binary
  GL_ARB_get_texture_sub_image
  GL_ARB_gl_spirv
  GL_ARB_gpu_shader5
  GL_ARB_gpu_shader_fp64
  GL_ARB_gpu_shader_int64
  GL_ARB_half_float_pixel
  GL_ARB_half_float_vertex
  GL_ARB_indirect_parameters
  GL_ARB_instanced_arrays
  GL_ARB_internalformat_query
  GL_ARB_internalformat_query2
  GL_ARB_invalidate_subdata
  GL_ARB_map_buffer_alignment
  GL_ARB_map_buffer_range
  GL_ARB_multi_bind
  GL_ARB_multi_draw_indirect
  GL_ARB_occlusion_query2
  GL_ARB_parallel_shader_compile
  GL_ARB_pixel_buffer_object
  GL_ARB_point_sprite
  GL_ARB_polygon_offset_clamp
  GL_ARB_program_interface_query
  GL_ARB_provoking_vertex
  GL_ARB_query_buffer_object
  GL_ARB_robust_buffer_access_behavior
  GL_ARB_robustness
  GL_ARB_sample_shading
  GL_ARB_sampler_objects
  GL_ARB_seamless_cube_map
  GL_ARB_seamless_cubemap_per_texture
  GL_ARB_separate_shader_objects
  GL_ARB_shader_atomic_counter_ops
  GL_ARB_shader_atomic_counters
  GL_ARB_shader_ballot
  GL_ARB_shader_bit_encoding
  GL_ARB_shader_clock
  GL_ARB_shader_draw_parameters
  GL_ARB_shader_group_vote
  GL_ARB_shader_image_load_store
  GL_ARB_shader_image_size
  GL_ARB_shader_objects
  GL_ARB_shader_precision
  GL_ARB_shader_stencil_export
  GL_ARB_shader_storage_buffer_object
  GL_ARB_shader_subroutine
  GL_ARB_shader_texture_image_samples
  GL_ARB_shader_texture_lod
  GL_ARB_shading_language_420pack
  GL_ARB_shading_language_include
  GL_ARB_shading_language_packing
  GL_ARB_spirv_extensions
  GL_ARB_stencil_texturing
  GL_ARB_sync
  GL_ARB_texture_barrier
  GL_ARB_texture_border_clamp
  GL_ARB_texture_buffer_object
  GL_ARB_texture_buffer_object_rgb32
  GL_ARB_texture_buffer_range
  GL_ARB_texture_compression_bptc
  GL_ARB_texture_compression_rgtc
  GL_ARB_texture_cube_map_array
  GL_ARB_texture_filter_anisotropic
  GL_ARB_texture_filter_minmax
  GL_ARB_texture_float
  GL_ARB_texture_gather
  GL_ARB_texture_mirror_clamp_to_edge
  GL_ARB_texture_multisample
  GL_ARB_texture_non_power_of_two
  GL_ARB_texture_query_levels
  GL_ARB_texture_query_lod
  GL_ARB_texture_rectangle
  GL_ARB_texture_rg
  GL_ARB_texture_rgb10_a2ui
  GL_ARB_texture_stencil8
  GL_ARB_texture_storage
  GL_ARB_texture_storage_multisample
  GL_ARB_texture_swizzle
  GL_ARB_texture_view
  GL_ARB_timer_query
  GL_ARB_transform_feedback2
  GL_ARB_transform_feedback3
  GL_ARB_transform_feedback_instanced
  GL_ARB_transform_feedback_overflow_query
  GL_ARB_uniform_buffer_object
  GL_ARB_vertex_array_bgra
  GL_ARB_vertex_array_object
  GL_ARB_vertex_attrib_64bit
  GL_ARB_vertex_attrib_binding
  GL_ARB_vertex_buffer_object
  GL_ARB_vertex_shader
  GL_ARB_vertex_type_10f_11f_11f_rev
  GL_ARB_vertex_type_2_10_10_10_rev
  GL_ATI_blend_equation_separate
  GL_ATI_meminfo
  GL_ATI_texture_float
  GL_EXT_EGL_image_storage
  GL_EXT_EGL_image_storage_compression
  GL_EXT_EGL_sync
  GL_EXT_abgr
  GL_EXT_blend_equation_separate
  GL_EXT_debug_label
  GL_EXT_demote_to_helper_invocation
  GL_EXT_draw_buffers2
  GL_EXT_draw_instanced
  GL_EXT_framebuffer_blit
  GL_EXT_framebuffer_multisample
  GL_EXT_framebuffer_multisample_blit_scaled
  GL_EXT_framebuffer_object
  GL_EXT_framebuffer_sRGB
  GL_EXT_memory_object
  GL_EXT_memory_object_fd
  GL_EXT_packed_depth_stencil
  GL_EXT_packed_float
  GL_EXT_pixel_buffer_object
  GL_EXT_polygon_offset_clamp
  GL_EXT_provoking_vertex
  GL_EXT_semaphore
  GL_EXT_semaphore_fd
  GL_EXT_shader_clock
  GL_EXT_shader_image_load_formatted
  GL_EXT_shader_integer_mix
  GL_EXT_texture_array
  GL_EXT_texture_compression_dxt1
  GL_EXT_texture_compression_rgtc
  GL_EXT_texture_compression_s3tc
  GL_EXT_texture_filter_anisotropic
  GL_EXT_texture_integer
  GL_EXT_texture_sRGB
  GL_EXT_texture_sRGB_R8
  GL_EXT_texture_sRGB_RG8
  GL_EXT_texture_sRGB_decode
  GL_EXT_texture_shared_exponent
  GL_EXT_texture_snorm
  GL_EXT_texture_storage
  GL_EXT_texture_swizzle
  GL_EXT_timer_query
  GL_EXT_transform_feedback
  GL_EXT_vertex_array_bgra
  GL_EXT_vertex_attrib_64bit
  GL_IBM_multimode_draw_arrays
  GL_KHR_blend_equation_advanced
  GL_KHR_context_flush_control
  GL_KHR_debug
  GL_KHR_no_error
  GL_KHR_parallel_shader_compile
  GL_KHR_robust_buffer_access_behavior
  GL_KHR_robustness
  GL_KHR_texture_compression_astc_hdr
  GL_KHR_texture_compression_astc_ldr
  GL_KHR_texture_compression_astc_sliced_3d
  GL_MESA_pack_invert
  GL_MESA_shader_integer_functions
  GL_MESA_texture_signed_rgba
  GL_NVX_gpu_memory_info
  GL_NV_conditional_render
  GL_NV_copy_image
  GL_NV_depth_clamp
  GL_NV_packed_depth_stencil
  GL_NV_shader_atomic_int64
  GL_NV_texture_barrier
  GL_NV_timeline_semaphore
  GL_OES_EGL_image
  GL_OVR_multiview
  GL_OVR_multiview2
  GL_OVR_multiview_multisampled_render_to_texture
  GL_S3_s3tc
```

## Implementation limits

```
  GL_MAX_TEXTURE_SIZE                                        16384
  GL_MAX_3D_TEXTURE_SIZE                                     65536
  GL_MAX_CUBE_MAP_TEXTURE_SIZE                               65536
  GL_MAX_ARRAY_TEXTURE_LAYERS                                65536
  GL_MAX_TEXTURE_IMAGE_UNITS                                 32
  GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS                          32
  GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS                        160
  GL_MAX_GEOMETRY_TEXTURE_IMAGE_UNITS                        32
  GL_MAX_TESS_CONTROL_TEXTURE_IMAGE_UNITS                    0
  GL_MAX_TESS_EVALUATION_TEXTURE_IMAGE_UNITS                 0
  GL_MAX_VERTEX_ATTRIBS                                      16
  GL_MAX_VERTEX_ATTRIB_BINDINGS                              16
  GL_MAX_VERTEX_ATTRIB_RELATIVE_OFFSET                       2047
  GL_MAX_VERTEX_UNIFORM_COMPONENTS                           16384
  GL_MAX_FRAGMENT_UNIFORM_COMPONENTS                         16384
  GL_MAX_VARYING_COMPONENTS                                  64
  GL_MAX_VARYING_VECTORS                                     16
  GL_MAX_VERTEX_OUTPUT_COMPONENTS                            128
  GL_MAX_FRAGMENT_INPUT_COMPONENTS                           128
  GL_MAX_VERTEX_UNIFORM_BLOCKS                               15
  GL_MAX_GEOMETRY_UNIFORM_BLOCKS                             12
  GL_MAX_FRAGMENT_UNIFORM_BLOCKS                             15
  GL_MAX_COMBINED_UNIFORM_BLOCKS                             66
  GL_MAX_UNIFORM_BUFFER_BINDINGS                             105
  GL_MAX_UNIFORM_BLOCK_SIZE                                  1048576
  GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT                         16
  GL_MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS                  3948544
  GL_MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS                3948544
  GL_MAX_COMBINED_GEOMETRY_UNIFORM_COMPONENTS                65536
  GL_MAX_VIEWPORT_DIMS                                       16384 16384
  GL_MAX_SAMPLES                                             8
  GL_MAX_COLOR_TEXTURE_SAMPLES                               8
  GL_MAX_DEPTH_TEXTURE_SAMPLES                               8
  GL_MAX_INTEGER_SAMPLES                                     8
  GL_MAX_DRAW_BUFFERS                                        8
  GL_MAX_COLOR_ATTACHMENTS                                   8
  GL_MAX_RENDERBUFFER_SIZE                                   16384
  GL_MAX_DUAL_SOURCE_DRAW_BUFFERS                            8
  GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_ATTRIBS                 4
  GL_MAX_TRANSFORM_FEEDBACK_INTERLEAVED_COMPONENTS           64
  GL_MAX_TRANSFORM_FEEDBACK_SEPARATE_COMPONENTS              4
  GL_MAX_GEOMETRY_OUTPUT_VERTICES                            0
  GL_MAX_GEOMETRY_TOTAL_OUTPUT_COMPONENTS                    0
  GL_MAX_GEOMETRY_INPUT_COMPONENTS                           64
  GL_MAX_GEOMETRY_OUTPUT_COMPONENTS                          64
  GL_MAX_PATCH_VERTICES                                      0
  GL_MAX_TESS_CONTROL_TOTAL_OUTPUT_COMPONENTS                0
  GL_MAX_TESS_CONTROL_INPUT_COMPONENTS                       0
  GL_MAX_TESS_CONTROL_OUTPUT_COMPONENTS                      0
  GL_MAX_TESS_EVALUATION_INPUT_COMPONENTS                    0
  GL_MAX_TESS_EVALUATION_OUTPUT_COMPONENTS                   0
  GL_MAX_TESS_GEN_LEVEL                                      0
  GL_MAX_FRAMEBUFFER_WIDTH                                   16384
  GL_MAX_FRAMEBUFFER_HEIGHT                                  16384
  GL_MAX_FRAMEBUFFER_LAYERS                                  65536
  GL_MAX_FRAMEBUFFER_SAMPLES                                 8
  GL_MAX_TEXTURE_BUFFER_SIZE                                 134217728
  GL_MAX_TEXTURE_LOD_BIAS                                    31
  GL_MAX_TEXTURE_MAX_ANISOTROPY                              16
  GL_MAX_IMAGE_UNITS                                         256
  GL_MAX_COMBINED_IMAGE_UNITS_AND_FRAGMENT_OUTPUTS           112
  GL_MAX_SUBROUTINES                                         256
  GL_MAX_SUBROUTINE_UNIFORM_LOCATIONS                        1024
  GL_MAX_DEBUG_MESSAGE_LENGTH                                4096
  GL_MAX_SHADER_STORAGE_BUFFER_BINDINGS                      40
  GL_MAX_COMBINED_SHADER_STORAGE_BLOCKS                      40
  GL_MAX_VERTEX_SHADER_STORAGE_BLOCKS                        0
  GL_MAX_FRAGMENT_SHADER_STORAGE_BLOCKS                      16
  GL_MAX_GEOMETRY_SHADER_STORAGE_BLOCKS                      8
  GL_MAX_TESS_CONTROL_SHADER_STORAGE_BLOCKS                  8
  GL_MAX_TESS_EVALUATION_SHADER_STORAGE_BLOCKS               8
  GL_MAX_SHADER_STORAGE_BLOCK_SIZE                           2147483647
  GL_SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT                  16
  GL_MAX_VERTEX_ATOMIC_COUNTER_BUFFERS                       0
  GL_MAX_FRAGMENT_ATOMIC_COUNTER_BUFFERS                     16
  GL_MAX_GEOMETRY_ATOMIC_COUNTERS                            0
  GL_MAX_COMPUTE_WORK_GROUP_INVOCATIONS                      1024
  GL_MAX_COMPUTE_WORK_GROUP_COUNT                            0 0 0
  GL_MAX_COMPUTE_WORK_GROUP_SIZE                             0 0 0
  GL_MAX_COMPUTE_UNIFORM_BLOCKS                              15
  GL_MAX_COMPUTE_UNIFORM_COMPONENTS                          16384
  GL_MAX_COMPUTE_TEXTURE_IMAGE_UNITS                         32
  GL_MAX_COMPUTE_IMAGE_UNIFORMS                              32
  GL_MAX_COMPUTE_ATOMIC_COUNTER_BUFFERS                      16
  GL_MAX_COMPUTE_ATOMIC_COUNTERS                             4096
  GL_MAX_COMBINED_COMPUTE_UNIFORM_COMPONENTS                 3948544
  GL_MAX_COMPUTE_SHARED_MEMORY_SIZE                          32768
  GL_MAX_COMPUTE_SHADER_STORAGE_BLOCKS                       16
  GL_SUBPIXEL_BITS                                           4
```

## Notes

- GL has no native driver here (only proprietary kbase `/dev/mali0`, no
  panfrost/panthor DRM node), so GL runs through Mesa Zink (GL-on-Vulkan)
  on top of PanVK: `GALLIUM_DRIVER=zink`, renderer string proves the path.
- Tessellation/geometry shader stage limits read 0 — no GS/TS stages
  (`geometryShader=no`, `tessellationShader=no` in Vulkan), consistent with
  the GL 3.3 cap. For the 3.3-compat profile (292 extensions, legacy
  ARB fixed-function set) see raw output `/tmp/gl33compat.txt`.
- Raw outputs: `/tmp/gl32forced.txt`, `/tmp/gl33core.txt`,
  `/tmp/gl33compat.txt`, `/tmp/gles31.txt` (GLES 3.1, 148 extensions).


# OpenGL 4.5 / 4.6 on this device — UNAVAILABLE (measured, not assumed)

## Result

Every desktop-GL 4.x context request fails with `EGL_BAD_ALLOC` (0x3009) —
core, compat, and forward-compatible. (No EGL config on this path advertises
`EGL_OPENGL_BIT` at all — `eglChooseConfig` with that bit returns 0 configs —
so all desktop-GL contexts are created configless via
`EGL_MESA_configless_context`; with-config vs configless runs were identical.):

```
req GL 3.0         -> GOT [3.3 (Compatibility Profile) Mesa 26.1.6]
req GL 3.1         -> GOT [3.3 (Core Profile) Mesa 26.1.6]
req GL 3.2 core    -> GOT [3.3 (Core Profile) Mesa 26.1.6]
req GL 3.3 core    -> GOT [3.3 (Core Profile) Mesa 26.1.6]
req GL 4.0 core    -> FAIL 0x3009 (EGL_BAD_ALLOC)
req GL 4.1 core    -> FAIL 0x3009
req GL 4.2 core    -> FAIL 0x3009
req GL 4.3 core    -> FAIL 0x3009
req GL 4.4 core    -> FAIL 0x3009
req GL 4.5 core    -> FAIL 0x3009
req GL 4.6 core    -> FAIL 0x3009
req GL 4.6 compat  -> FAIL 0x3009
req ES 2.0/3.0/3.1 -> GOT [OpenGL ES 3.1 Mesa 26.1.6]
req ES 3.2         -> FAIL 0x3009
```

So there is **no on-device 4.5/4.6 extension or limit set to report**.
Fabricating one (e.g. via `MESA_GL_VERSION_OVERRIDE=4.6`) would not be
device-accurate, so it was deliberately not done.

## Why: the Vulkan feature trace explains the cap

Zink needs geometry+tessellation shader stages for GL 4.0+ (and ES 3.2).
This PanVK driver reports, on this unrecognised GPU
(conservative Valhall defaults):

```
  geometryShader      no
  tessellationShader  no
  shaderFloat64       no
  shaderClipDistance  no
  shaderCullDistance  no
  multiViewport       no
  sparseBinding       no  (+ all sparse residency: no)
```

Hence max desktop GL = 3.3 (core + compat) and max GLES = 3.1.
GL 3.3 data: `OpenGL-3.2-Mali-PanVK-zink.md` + `/tmp/gl33core.txt`.

## Difficulties getting these values (as requested)

1. No `vulkaninfo`/`glxinfo`/`eglinfo`, no Vulkan headers: fetched
   Vulkan-Headers v1.4.352 from GitHub and wrote C probes with dlopen.
2. First probes segfaulted: hand-written `VkPhysicalDeviceVulkan12/14Features`
   layouts were wrong (missing `shaderFloat16`/`shaderInt8`; the 1.4 struct
   has 22 different fields in v1.4.352). Fixed by compiling against the
   real headers (`/tmp/vkhdr`).
3. GPU unrecognised by PanVK (`unknown gpu_id 0xa8671030`), so everything
   runs on conservative defaults — the values in these files are specific
   to that fallback path, not to a fully-enabled G6xx/G7xx.
4. No native GL driver (kbase only, no panfrost/panthor DRM): GL only works
   via Zink-on-PanVK (`GALLIUM_DRIVER=zink`, mesa 26.1.6 dri `zink_dri.so`).
5. EGL surfaceless first fell back to swrast (`DRI2: failed to load driver`);
   with `GALLIUM_DRIVER=zink` the pipe driver is still Zink (renderer string
   proves it). No EGL config advertises `EGL_OPENGL_BIT`, so desktop GL
   needs configless contexts (`EGL_MESA_configless_context`); GLES works
   with ordinary configs.
6. Early probe builds kept failing on GL enum typos — fixed by reading values
   from the installed `/usr/include/GL/glcorearb.h` instead of memory.

---

## Instructions for Running OpenGL on Mali (Poco X6 Pro / Dimensity 8300)

### 1. Hardware Accelerated OpenGL via Zink over PanVK (Recommended)
To run desktop OpenGL applications up to OpenGL 3.3 Core Profile and OpenGL ES 3.1:
```bash
# Sourced automatically via /etc/profile.d/gpu-env.sh
export VK_DRIVER_FILES="/opt/nativecode/panvk/icd.d/panvk_kbase.json"
export VK_ICD_FILENAMES="$VK_DRIVER_FILES"
export LD_PRELOAD="/opt/nativecode/panvk/lib/kbase_shim.so${LD_PRELOAD:+:$LD_PRELOAD}"
export WSI_X11_TERMUX=1
export PANVK_KBASE_DRI3=raw
export MESA_VK_WSI_DEBUG=sw
export GALLIUM_DRIVER=zink
export MESA_LOADER_DRIVER_OVERRIDE=zink

# Or run via NativeCode launcher:
gpu-launch --panvk-zink <command>
```

### 2. Overriding GL Version for 4.x Compatible Apps
If an application or game strictly queries for OpenGL 4.5/4.6 and does not use unsupported geometry/tessellation stages:
```bash
export MESA_GL_VERSION_OVERRIDE=4.6
export MESA_GLSL_VERSION_OVERRIDE=460
gpu-launch --panvk-zink <command>
```


# Vulkan feature + extension set — on-device query

## Device / driver identity (queried live, not from spec sheets)

```
device0: Mali unknown 0xa8671030 MC6 api 1.4.352 vid 0x13b5 did 0xa8671030 type 1 (integrated)
driverID: 20  driverName: panvk
driverInfo: Mesa 26.2.0-devel
queue families (1): q0: flags=0x7 (GFX|COMPUTE|TRANSFER) count=2 tsBits=64
memory types (3): t0 flags=0x1 heap=0 / t1 flags=0xb heap=0 / t2 flags=0x7 heap=0
memory heaps (1): heap0 = 5498 MB, flags=0x1 (DEVICE_LOCAL)
```

> `MESA: warning: panvk: unknown gpu_id (0xa8671030) or variant (0x4);`
> `continuing with conservative "Mali (unknown Valhall)" defaults — expect issues`
> The driver does not recognise this GPU (MediaTek SoC, Mali Valhall-v10 family,
> product-major 7, 6 cores → G610-class) and runs on conservative defaults.

## Instance extensions (22, loader)

```
  VK_KHR_device_group_creation (v1)
  VK_KHR_display (v23)
  VK_KHR_external_fence_capabilities (v1)
  VK_KHR_external_memory_capabilities (v1)
  VK_KHR_external_semaphore_capabilities (v1)
  VK_KHR_get_display_properties2 (v1)
  VK_KHR_get_physical_device_properties2 (v2)
  VK_KHR_get_surface_capabilities2 (v1)
  VK_KHR_surface (v25)
  VK_KHR_surface_maintenance1 (v1)
  VK_KHR_xcb_surface (v6)
  VK_KHR_xlib_surface (v6)
  VK_EXT_acquire_drm_display (v1)
  VK_EXT_acquire_xlib_display (v1)
  VK_EXT_debug_report (v10)
  VK_EXT_debug_utils (v2)
  VK_EXT_direct_mode_display (v1)
  VK_EXT_display_surface_counter (v1)
  VK_EXT_headless_surface (v1)
  VK_EXT_surface_maintenance1 (v1)
  VK_KHR_portability_enumeration (v1)
  VK_LUNARG_direct_driver_loading (v1)
```

## Device extensions (168)

```
  VK_KHR_8bit_storage (ver 1)
  VK_KHR_16bit_storage (ver 1)
  VK_KHR_bind_memory2 (ver 1)
  VK_KHR_buffer_device_address (ver 1)
  VK_KHR_calibrated_timestamps (ver 1)
  VK_KHR_copy_commands2 (ver 1)
  VK_KHR_create_renderpass2 (ver 1)
  VK_KHR_dedicated_allocation (ver 3)
  VK_KHR_depth_clamp_zero_one (ver 1)
  VK_KHR_depth_stencil_resolve (ver 1)
  VK_KHR_descriptor_update_template (ver 1)
  VK_KHR_device_group (ver 4)
  VK_KHR_draw_indirect_count (ver 1)
  VK_KHR_driver_properties (ver 1)
  VK_KHR_dynamic_rendering (ver 1)
  VK_KHR_dynamic_rendering_local_read (ver 1)
  VK_KHR_external_fence (ver 1)
  VK_KHR_external_fence_fd (ver 1)
  VK_KHR_external_memory (ver 1)
  VK_KHR_external_memory_fd (ver 1)
  VK_KHR_external_semaphore (ver 1)
  VK_KHR_external_semaphore_fd (ver 1)
  VK_KHR_format_feature_flags2 (ver 2)
  VK_KHR_get_memory_requirements2 (ver 1)
  VK_KHR_global_priority (ver 1)
  VK_KHR_image_format_list (ver 1)
  VK_KHR_imageless_framebuffer (ver 1)
  VK_KHR_index_type_uint8 (ver 1)
  VK_KHR_line_rasterization (ver 1)
  VK_KHR_load_store_op_none (ver 1)
  VK_KHR_maintenance1 (ver 2)
  VK_KHR_maintenance2 (ver 1)
  VK_KHR_maintenance3 (ver 1)
  VK_KHR_maintenance4 (ver 2)
  VK_KHR_maintenance5 (ver 1)
  VK_KHR_maintenance6 (ver 1)
  VK_KHR_maintenance7 (ver 1)
  VK_KHR_maintenance8 (ver 1)
  VK_KHR_maintenance9 (ver 1)
  VK_KHR_map_memory2 (ver 1)
  VK_KHR_multiview (ver 1)
  VK_KHR_pipeline_binary (ver 1)
  VK_KHR_pipeline_executable_properties (ver 1)
  VK_KHR_pipeline_library (ver 1)
  VK_KHR_present_id (ver 1)
  VK_KHR_present_id2 (ver 1)
  VK_KHR_present_wait (ver 1)
  VK_KHR_present_wait2 (ver 1)
  VK_KHR_push_descriptor (ver 2)
  VK_KHR_relaxed_block_layout (ver 1)
  VK_KHR_robustness2 (ver 1)
  VK_KHR_sampler_mirror_clamp_to_edge (ver 3)
  VK_KHR_sampler_ycbcr_conversion (ver 14)
  VK_KHR_separate_depth_stencil_layouts (ver 1)
  VK_KHR_shader_atomic_int64 (ver 1)
  VK_KHR_shader_clock (ver 1)
  VK_KHR_shader_draw_parameters (ver 1)
  VK_KHR_shader_expect_assume (ver 1)
  VK_KHR_shader_float16_int8 (ver 1)
  VK_KHR_shader_float_controls (ver 4)
  VK_KHR_shader_float_controls2 (ver 1)
  VK_KHR_shader_integer_dot_product (ver 1)
  VK_KHR_shader_maximal_reconvergence (ver 1)
  VK_KHR_shader_non_semantic_info (ver 1)
  VK_KHR_shader_quad_control (ver 1)
  VK_KHR_shader_relaxed_extended_instruction (ver 1)
  VK_KHR_shader_subgroup_extended_types (ver 1)
  VK_KHR_shader_subgroup_rotate (ver 2)
  VK_KHR_shader_subgroup_uniform_control_flow (ver 1)
  VK_KHR_shader_terminate_invocation (ver 1)
  VK_KHR_shader_untyped_pointers (ver 1)
  VK_KHR_spirv_1_4 (ver 1)
  VK_KHR_storage_buffer_storage_class (ver 1)
  VK_KHR_swapchain (ver 70)
  VK_KHR_swapchain_maintenance1 (ver 1)
  VK_KHR_swapchain_mutable_format (ver 1)
  VK_KHR_synchronization2 (ver 1)
  VK_KHR_timeline_semaphore (ver 2)
  VK_KHR_unified_image_layouts (ver 1)
  VK_KHR_uniform_buffer_standard_layout (ver 1)
  VK_KHR_variable_pointers (ver 1)
  VK_KHR_vertex_attribute_divisor (ver 1)
  VK_KHR_vulkan_memory_model (ver 3)
  VK_KHR_zero_initialize_workgroup_memory (ver 1)
  VK_EXT_4444_formats (ver 1)
  VK_EXT_astc_decode_mode (ver 1)
  VK_EXT_attachment_feedback_loop_dynamic_state (ver 1)
  VK_EXT_attachment_feedback_loop_layout (ver 2)
  VK_EXT_border_color_swizzle (ver 1)
  VK_EXT_buffer_device_address (ver 2)
  VK_EXT_calibrated_timestamps (ver 2)
  VK_EXT_color_write_enable (ver 1)
  VK_EXT_conditional_rendering (ver 2)
  VK_EXT_custom_border_color (ver 12)
  VK_EXT_depth_bias_control (ver 1)
  VK_EXT_depth_clamp_control (ver 1)
  VK_EXT_depth_clamp_zero_one (ver 1)
  VK_EXT_depth_clip_control (ver 1)
  VK_EXT_depth_clip_enable (ver 1)
  VK_EXT_descriptor_indexing (ver 2)
  VK_EXT_device_memory_report (ver 2)
  VK_EXT_display_control (ver 1)
  VK_EXT_dynamic_rendering_unused_attachments (ver 1)
  VK_EXT_extended_dynamic_state (ver 1)
  VK_EXT_extended_dynamic_state2 (ver 1)
  VK_EXT_extended_dynamic_state3 (ver 2)
  VK_EXT_external_memory_acquire_unmodified (ver 1)
  VK_EXT_external_memory_dma_buf (ver 1)
  VK_EXT_global_priority (ver 2)
  VK_EXT_global_priority_query (ver 1)
  VK_EXT_graphics_pipeline_library (ver 1)
  VK_EXT_hdr_metadata (ver 3)
  VK_EXT_host_image_copy (ver 1)
  VK_EXT_host_query_reset (ver 1)
  VK_EXT_image_2d_view_of_3d (ver 1)
  VK_EXT_image_drm_format_modifier (ver 2)
  VK_EXT_image_robustness (ver 1)
  VK_EXT_image_view_min_lod (ver 1)
  VK_EXT_index_type_uint8 (ver 1)
  VK_EXT_inline_uniform_block (ver 1)
  VK_EXT_legacy_dithering (ver 2)
  VK_EXT_line_rasterization (ver 1)
  VK_EXT_load_store_op_none (ver 1)
  VK_EXT_map_memory_placed (ver 1)
  VK_EXT_memory_budget (ver 1)
  VK_EXT_multisampled_render_to_single_sampled (ver 1)
  VK_EXT_mutable_descriptor_type (ver 1)
  VK_EXT_nested_command_buffer (ver 1)
  VK_EXT_non_seamless_cube_map (ver 1)
  VK_EXT_physical_device_drm (ver 1)
  VK_EXT_pipeline_creation_cache_control (ver 3)
  VK_EXT_pipeline_creation_feedback (ver 1)
  VK_EXT_pipeline_robustness (ver 1)
  VK_EXT_present_timing (ver 3)
  VK_EXT_primitive_topology_list_restart (ver 1)
  VK_EXT_private_data (ver 1)
  VK_EXT_provoking_vertex (ver 1)
  VK_EXT_queue_family_foreign (ver 1)
  VK_EXT_robustness2 (ver 1)
  VK_EXT_sampler_filter_minmax (ver 2)
  VK_EXT_scalar_block_layout (ver 1)
  VK_EXT_separate_stencil_usage (ver 1)
  VK_EXT_shader_atomic_float (ver 1)
  VK_EXT_shader_demote_to_helper_invocation (ver 1)
  VK_EXT_shader_module_identifier (ver 1)
  VK_EXT_shader_replicated_composites (ver 1)
  VK_EXT_shader_stencil_export (ver 1)
  VK_EXT_shader_subgroup_ballot (ver 1)
  VK_EXT_shader_subgroup_vote (ver 1)
  VK_EXT_shader_uniform_buffer_unsized_array (ver 1)
  VK_EXT_subgroup_size_control (ver 2)
  VK_EXT_swapchain_maintenance1 (ver 1)
  VK_EXT_texel_buffer_alignment (ver 1)
  VK_EXT_texture_compression_astc_hdr (ver 1)
  VK_EXT_tooling_info (ver 1)
  VK_EXT_transform_feedback (ver 1)
  VK_EXT_vertex_attribute_divisor (ver 3)
  VK_EXT_vertex_input_dynamic_state (ver 2)
  VK_EXT_ycbcr_2plane_444_formats (ver 1)
  VK_EXT_ycbcr_image_arrays (ver 1)
  VK_EXT_zero_initialize_device_memory (ver 1)
  VK_ARM_scheduling_controls (ver 2)
  VK_ARM_shader_core_builtins (ver 2)
  VK_ARM_shader_core_properties (ver 1)
  VK_GOOGLE_decorate_string (ver 1)
  VK_GOOGLE_hlsl_functionality1 (ver 1)
  VK_GOOGLE_user_type (ver 1)
  VK_VALVE_mutable_descriptor_type (ver 1)
```

## Core features

### Vulkan 1.0 (55 features)

```
  robustBufferAccess                                   YES
  fullDrawIndexUint32                                  YES
  imageCubeArray                                       YES
  independentBlend                                     YES
  geometryShader                                       no
  tessellationShader                                   no
  sampleRateShading                                    YES
  dualSrcBlend                                         YES
  logicOp                                              YES
  multiDrawIndirect                                    YES
  drawIndirectFirstInstance                            YES
  depthClamp                                           YES
  depthBiasClamp                                       YES
  fillModeNonSolid                                     YES
  depthBounds                                          no
  wideLines                                            YES
  largePoints                                          YES
  alphaToOne                                           no
  multiViewport                                        no
  samplerAnisotropy                                    YES
  textureCompressionETC2                               YES
  textureCompressionASTC_LDR                           YES
  textureCompressionBC                                 no
  occlusionQueryPrecise                                YES
  pipelineStatisticsQuery                              no
  vertexPipelineStoresAndAtomics                       no
  fragmentStoresAndAtomics                             YES
  shaderImageGatherExtended                            YES
  shaderStorageImageExtendedFormats                    YES
  shaderStorageImageMultisample                        no
  shaderStorageImageReadWithoutFormat                  YES
  shaderStorageImageWriteWithoutFormat                 YES
  shaderUniformBufferArrayDynamicIndexing              YES
  shaderSampledImageArrayDynamicIndexing               YES
  shaderStorageBufferArrayDynamicIndexing              YES
  shaderStorageImageArrayDynamicIndexing               YES
  shaderClipDistance                                   no
  shaderCullDistance                                   no
  shaderFloat64                                        no
  shaderInt64                                          YES
  shaderInt16                                          YES
  shaderResourceResidency                              no
  shaderResourceMinLod                                 no
  sparseBinding                                        no
  sparseResidencyBuffer                                no
  sparseResidencyImage2D                               no
  sparseResidencyImage3D                               no
  sparseResidency2Samples                              no
  sparseResidency4Samples                              no
  sparseResidency8Samples                              no
  sparseResidency16Samples                             no
  sparseResidencyAliased                               no
  variableMultisampleRate                              no
  inheritedQueries                                     no
```

### Vulkan 1.1

```
multiview                                            YES
  shaderDrawParameters                                 YES
  samplerYcbcrConversion                               YES
  variablePointers                                     YES
  storageBuffer16BitAccess                             YES
  uniformAndStorageBuffer16BitAccess                   YES
  storagePushConstant16                                YES
  storageInputOutput16                                 YES
```

### Vulkan 1.2

```
drawIndirectCount                                    YES
  storageBuffer8BitAccess                              YES
  uniformAndStorageBuffer8BitAccess                    YES
  shaderFloat16                                        YES
  shaderInt8                                           YES
  shaderBufferInt64Atomics                             YES
  shaderSharedInt64Atomics                             YES
  descriptorIndexing                                   YES
  runtimeDescriptorArray                               YES
  samplerFilterMinmax                                  YES
  scalarBlockLayout                                    YES
  imagelessFramebuffer                                 YES
  uniformBufferStandardLayout                          YES
  shaderSubgroupExtendedTypes                          YES
  separateDepthStencilLayouts                          YES
  hostQueryReset                                       YES
  timelineSemaphore                                    YES
  bufferDeviceAddress                                  YES
  vulkanMemoryModel                                    YES
  shaderOutputViewportIndex                            no
  subgroupBroadcastDynamicId                           YES
```

### Vulkan 1.3

```
robustImageAccess                                    YES
  inlineUniformBlock                                   YES
  pipelineCreationCacheControl                         YES
  descriptorBindingInlineUniformBlockUpdateAfterBind   YES
  privateData                                          YES
  shaderDemoteToHelperInvocation                       YES
  shaderTerminateInvocation                            YES
  subgroupSizeControl                                  YES
  computeFullSubgroups                                 YES
  synchronization2                                     YES
  textureCompressionASTC_HDR                           YES
  shaderZeroInitializeWorkgroupMemory                  YES
  dynamicRendering                                     YES
  shaderIntegerDotProduct                              YES
  maintenance4                                         YES
```

### Vulkan 1.4

```
globalPriorityQuery                                  YES
  shaderSubgroupRotate                                 YES
  shaderSubgroupRotateClustered                        YES
  shaderFloatControls2                                 YES
  shaderExpectAssume                                   YES
  rectangularLines                                     YES
  bresenhamLines                                       YES
  smoothLines                                          no
  stippledRectangularLines                             no
  stippledBresenhamLines                               no
  stippledSmoothLines                                  no
  vertexAttributeInstanceRateDivisor                   YES
  vertexAttributeInstanceRateZeroDivisor               YES
  indexTypeUint8                                       YES
  dynamicRenderingLocalRead                            YES
  maintenance5                                         YES
  maintenance6                                         YES
  pipelineProtectedAccess                              no
  pipelineRobustness                                   YES
  hostImageCopy                                        YES
  pushDescriptor                                       YES
```

## How obtained

- No `vulkaninfo` on device. Wrote `/opt/nativecode/panvk/ext_probe.c` (instance +
  device enumeration, 168 extensions) and `/tmp/vkfeat.c` + `/tmp/vkfeat10.c`
  (features 1.0–1.4, compiled against real Vulkan-Headers v1.4.352).
- Env: `LD_LIBRARY_PATH=/opt/nativecode/panvk/lib`
  `VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panvk_kbase.json`.
- Raw outputs: `/tmp/vk_ext_full.txt`, `/tmp/vk_feat_full.txt`, `/tmp/vk_feat10_full.txt`.