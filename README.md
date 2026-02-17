# vma-zig

Zig bindings for [Vulkan Memory Allocator (VMA)](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator), designed to work with [vulkan-zig](https://github.com/Snektron/vulkan-zig). MIT licensed.

VMA is vendored at tag **v3.3.0** through the Zig build system. Compatible with Vulkan 1.0–1.4 and Vulkan-Headers v1.4.335.

## Features

- **Allocator**: Create/destroy with `Instance` + `Device` + `PhysicalDevice`; vma-zig fills `VmaVulkanFunctions` from your `vkGetInstanceProcAddr` loader. Use `AllocatorCreateFlags.ext_memory_budget` when the device supports `VK_EXT_memory_budget` for accurate heap budgets.
- **Buffers**: `createBuffer` / `destroyBuffer` (create + allocate + bind in one call).
- **Images**: `createImage` / `destroyImage`.
- **Memory**: `freeMemory`, `mapMemory`, `unmapMemory`, `getAllocationInfo`.
- **Heap budget**: `getHeapBudgets(allocator, heap_count)` returns `[]HeapBudget` (usage, budget, block/allocation bytes per heap). Pass `heap_count` from `vkGetPhysicalDeviceMemoryProperties(physical_device).memory_heap_count`.
- **Statistics string**: `buildStatsString(allocator, detailed_map)` and `freeStatsString(allocator, str)` for debug dumps.
- **Allocation options**: `AllocationCreateInfo.priority`, `required_flags`, `preferred_flags`, and `pool` (optional pool for pool-based allocation).
- **Custom pools**: `createPool`, `destroyPool`, and allocating buffers/images from a pool via `AllocationCreateInfo.pool`.
- **Defragmentation**: `beginDefragmentation`, `endDefragmentation`, `beginDefragmentationPass`, `endDefragmentationPass`, and `DefragmentationContext` / `DefragmentationInfo` / `DefragmentationPassMoveInfo`.
- Results are translated to `vk.Result`; API uses vulkan-zig types (`vk.Buffer`, `vk.Device`, etc.).

## Usage

1. Add the dependency in `build.zig.zon`. I recommend using `zig fetch --save git+https://github.com/terminal-case/vma-zig.git` rather than manual add.

2. In `build.zig`:

   ```zig
   const vma_zig = b.dependency("vma_zig", .{ .target = target, .optimize = optimize });
   exe.root_module.addImport("vma", vma_zig.module("vma"));
   exe.linkLibrary(vma_zig.artifact("vma-zig"));
   exe.linkLibCpp();
   ```

3. Create an allocator (e.g. in your Vulkan init), then use it for buffers/images:

   ```zig
   const vma = @import("vma");

   var allocator = try vma.Allocator.init(allocator, .{
       .instance = ctx.instance,
       .physical_device = ctx.physical_device,
       .device = ctx.device,
       .get_instance_proc_addr = myGetInstanceProcAddr,
       .vulkan_api_version = vk.API_VERSION_1_3,
   });
   defer allocator.deinit();

   const buf_allocation = try allocator.createBuffer(
       .{ .size = 65536, .usage = .{ .vertex_buffer_bit = true, .transfer_dst_bit = true }, .sharing_mode = .exclusive },
       .{ .usage = .auto },
   );
   defer allocator.destroyBuffer(buf_allocation.buffer, buf_allocation.allocation);
   ```

## Build

- Build: `zig build`
- Run tests (compile-only check of the bindings): `zig build test`

## API not yet implemented

The following VMA API areas are **not** yet wrapped in vma-zig. Contributions welcome.

- **Virtual allocator**: `vmaCreateVirtualBlock`, `vmaDestroyVirtualBlock`, and the virtual allocation API
- **Flush/invalidate**: `vmaFlushAllocation`, `vmaInvalidateAllocation`, `vmaFlushAllocations`, `vmaInvalidateAllocations`
- **Allocation names/user data**: `vmaSetAllocationName`, `vmaGetAllocationName`, and user-data helpers beyond what is in `VmaAllocationCreateInfo`
- **Sparse binding/residency**: Sparse buffer/image and residency APIs
- **Sibling helpers**: `vmaCreateBufferWithAlignment`, `vmaCreateAliasingBuffer`, `vmaCreateAliasingBuffer2`, `vmaCreateAliasingImage`, `vmaCreateAliasingImage2`
- **Bind with offset/pNext**: `vmaBindBufferMemory2`, `vmaBindImageMemory2` (when you need custom bind offset or pNext)
- **Allocation info (extended)**: `vmaGetAllocationInfo2` and `VmaAllocationInfo2`
- **Copy helpers**: `vmaCopyMemoryToAllocation`, `vmaCopyAllocationToMemory`
- **External memory**: Win32 handle export/import and related flags (when using `VMA_ALLOCATOR_CREATE_KHR_EXTERNAL_MEMORY_WIN32_BIT`)
