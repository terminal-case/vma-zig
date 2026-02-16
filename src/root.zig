//! Zig bindings for Vulkan Memory Allocator (VMA).
//! Idiomatic API over the subset needed for typical buffer/image allocation.
const std = @import("std");
const vk = @import("vulkan");

const c = @cImport({
    @cInclude("vk_mem_alloc.h");
});

/// Opaque VMA allocation handle; pass to destroyBuffer/destroyImage/freeMemory/mapMemory.
pub const Allocation = c.VmaAllocation;

/// Opaque VMA pool handle; pass to createPool/destroyPool and AllocationCreateInfo.pool.
pub const Pool = c.VmaPool;

pub const PoolCreateInfo = struct {
    memory_type_index: u32,
    flags: PoolCreateFlags = .{},
    block_size: vk.DeviceSize = 0,
    min_block_count: usize = 0,
    max_block_count: usize = 0,
    frame_in_use_count: u32 = 0,
    priority: f32 = 0.5,
    min_allocation_alignment: vk.DeviceSize = 0,

    pub const PoolCreateFlags = struct {
        ignore_buffer_image_granularity: bool = false,
        linear_algorithm: bool = false,

        fn toC(flags: PoolCreateFlags) c.VmaPoolCreateFlags {
            var f: c.VmaPoolCreateFlags = 0;
            if (flags.ignore_buffer_image_granularity) f |= c.VMA_POOL_CREATE_IGNORE_BUFFER_IMAGE_GRANULARITY_BIT;
            if (flags.linear_algorithm) f |= c.VMA_POOL_CREATE_LINEAR_ALGORITHM_BIT;
            return f;
        }
    };
};

fn poolCreateFlagsToC(flags: PoolCreateInfo.PoolCreateFlags) c.VmaPoolCreateFlags {
    return PoolCreateInfo.PoolCreateFlags.toC(flags);
}

/// Opaque defragmentation context; use with Allocator.beginDefragmentationPass/endDefragmentationPass/endDefragmentation.
pub const DefragmentationContext = struct {
    handle: c.VmaDefragmentationContext,
};

pub const DefragmentationInfo = struct {
    flags: DefragmentationFlags = .{},
    pool: ?Pool = null,
    max_cpu_allocation_count: u32 = 0,
    max_cpu_bytes_to_move: vk.DeviceSize = 0,
    max_gpu_allocation_count: u32 = 0,
    max_gpu_bytes_to_move: vk.DeviceSize = 0,

    pub const DefragmentationFlags = struct {
        incremental: bool = false,

        fn toC(flags: DefragmentationFlags) c.VmaDefragmentationFlags {
            var f: c.VmaDefragmentationFlags = 0;
            if (flags.incremental) f |= c.VMA_DEFRAGMENTATION_FLAG_INCREMENTAL;
            return f;
        }
    };
};

fn defragmentationFlagsToC(flags: DefragmentationInfo.DefragmentationFlags) c.VmaDefragmentationFlags {
    return DefragmentationInfo.DefragmentationFlags.toC(flags);
}

/// Pass move info filled by beginDefragmentationPass; p_moves points to move_count DefragmentationMove entries (C array).
pub const DefragmentationPassMoveInfo = struct {
    move_count: u32,
    p_moves: ?[*]const c.VmaDefragmentationMove,
};

pub const Allocator = struct {
    handle: c.VmaAllocator,

    pub const InitInfo = struct {
        flags: AllocatorCreateFlags = .{},
        instance: vk.Instance,
        physical_device: vk.PhysicalDevice,
        device: vk.Device,
        vulkan_api_version: u32 = @bitCast(vk.API_VERSION_1_3),
        preferred_large_heap_block_size: u64 = 0,
        heap_size_limit: ?u64 = null,
        get_instance_proc_addr: vk.PfnGetInstanceProcAddr,
    };

    pub fn init(allocator: std.mem.Allocator, info: InitInfo) !Allocator {
        _ = allocator;
        var vulkan_functions: c.VmaVulkanFunctions = std.mem.zeroes(c.VmaVulkanFunctions);
        const get_instance_proc_addr = @as(*const fn (vk.Instance, [*:0]const u8) callconv(.c) vk.PfnVoidFunction, @ptrCast(info.get_instance_proc_addr));
        vulkan_functions.vkGetInstanceProcAddr = @ptrCast(get_instance_proc_addr);
        const get_device_proc_addr_ptr = get_instance_proc_addr(info.instance, "vkGetDeviceProcAddr");
        if (get_device_proc_addr_ptr == null) return error.VmaGetDeviceProcAddrFailed;
        vulkan_functions.vkGetDeviceProcAddr = @ptrCast(get_device_proc_addr_ptr);

        var create_info: c.VmaAllocatorCreateInfo = std.mem.zeroes(c.VmaAllocatorCreateInfo);
        create_info.flags = flagsToC(info.flags);
        create_info.instance = @ptrFromInt(@intFromEnum(info.instance));
        create_info.physicalDevice = @ptrFromInt(@intFromEnum(info.physical_device));
        create_info.device = @ptrFromInt(@intFromEnum(info.device));
        create_info.vulkanApiVersion = info.vulkan_api_version;
        create_info.preferredLargeHeapBlockSize = info.preferred_large_heap_block_size;
        create_info.pHeapSizeLimit = if (info.heap_size_limit) |limit| limit else null;
        create_info.pAllocationCallbacks = null;
        create_info.pDeviceMemoryCallbacks = null;
        create_info.pVulkanFunctions = &vulkan_functions;
        create_info.pTypeExternalMemoryHandleTypes = null;

        var allocator_handle: c.VmaAllocator = null;
        const result = c.vmaCreateAllocator(&create_info, &allocator_handle);
        if (result != c.VK_SUCCESS) return error.VmaAllocatorCreateFailed;
        return .{ .handle = allocator_handle.? };
    }

    pub fn deinit(self: *Allocator) void {
        if (self.handle != null) {
            c.vmaDestroyAllocator(self.handle);
            self.handle = null;
        }
    }

    pub fn createBuffer(
        self: Allocator,
        buffer_create_info: vk.BufferCreateInfo,
        allocation_create_info: AllocationCreateInfo,
    ) !BufferAllocation {
        var buf: c.VkBuffer = undefined;
        var allocation: c.VmaAllocation = null;
        var alloc_info: c.VmaAllocationInfo = undefined;
        const buf_ci = bufferCreateInfoToC(buffer_create_info);
        var alloc_ci = allocationCreateInfoToC(allocation_create_info);
        const result = c.vmaCreateBuffer(
            self.handle,
            &buf_ci,
            &alloc_ci,
            &buf,
            &allocation,
            &alloc_info,
        );
        if (result != c.VK_SUCCESS) return error.VmaBufferCreateFailed;
        return .{
            .buffer = @enumFromInt(@intFromPtr(buf)),
            .allocation = allocation.?,
            .allocator = self.handle,
        };
    }

    pub fn destroyBuffer(self: Allocator, buffer: vk.Buffer, allocation: c.VmaAllocation) void {
        c.vmaDestroyBuffer(self.handle, @ptrFromInt(@intFromEnum(buffer)), allocation);
    }

    pub fn createImage(
        self: Allocator,
        image_create_info: vk.ImageCreateInfo,
        allocation_create_info: AllocationCreateInfo,
    ) !ImageAllocation {
        var img: c.VkImage = undefined;
        var allocation: c.VmaAllocation = null;
        var alloc_info: c.VmaAllocationInfo = undefined;
        const img_ci = imageCreateInfoToC(image_create_info);
        var alloc_ci = allocationCreateInfoToC(allocation_create_info);
        const result = c.vmaCreateImage(
            self.handle,
            &img_ci,
            &alloc_ci,
            &img,
            &allocation,
            &alloc_info,
        );
        if (result != c.VK_SUCCESS) return error.VmaImageCreateFailed;
        return .{
            .image = @enumFromInt(@intFromPtr(img)),
            .allocation = allocation.?,
            .allocator = self.handle,
        };
    }

    pub fn destroyImage(self: Allocator, image: vk.Image, allocation: c.VmaAllocation) void {
        c.vmaDestroyImage(self.handle, @ptrFromInt(@intFromEnum(image)), allocation);
    }

    pub fn freeMemory(self: Allocator, allocation: c.VmaAllocation) void {
        c.vmaFreeMemory(self.handle, allocation);
    }

    pub fn mapMemory(self: Allocator, allocation: c.VmaAllocation) ![*]u8 {
        var ptr: ?*anyopaque = null;
        const result = c.vmaMapMemory(self.handle, allocation, &ptr);
        if (result != c.VK_SUCCESS) return error.VmaMapFailed;
        return @ptrCast(ptr.?);
    }

    pub fn unmapMemory(self: Allocator, allocation: c.VmaAllocation) void {
        c.vmaUnmapMemory(self.handle, allocation);
    }

    pub fn getAllocationInfo(self: Allocator, allocation: c.VmaAllocation) AllocationInfo {
        var info: c.VmaAllocationInfo = undefined;
        c.vmaGetAllocationInfo(self.handle, allocation, &info);
        return .{
            .memory_type = info.memoryType,
            .device_memory = @enumFromInt(@intFromPtr(info.deviceMemory)),
            .offset = info.offset,
            .size = info.size,
            .p_mapped_data = if (info.pMappedData != null) @ptrCast(info.pMappedData) else null,
        };
    }

    /// Returns heap budget info for each memory heap. Caller must pass heap_count from
    /// vkGetPhysicalDeviceMemoryProperties(physical_device).memory_heap_count.
    /// Caller owns the returned slice; free with allocator.free().
    pub fn getHeapBudgets(self: Allocator, allocator: std.mem.Allocator, heap_count: u32) ![]HeapBudget {
        const slice = try allocator.alloc(HeapBudget, heap_count);
        var c_budgets: [c.VK_MAX_MEMORY_HEAPS]c.VmaBudget = undefined;
        c.vmaGetHeapBudgets(self.handle, &c_budgets);
        for (slice, c_budgets[0..heap_count]) |*z, cb| {
            z.* = .{
                .block_bytes = cb.statistics.blockBytes,
                .allocation_bytes = cb.statistics.allocationBytes,
                .usage = cb.usage,
                .budget = cb.budget,
            };
        }
        return slice;
    }

    /// Build a human-readable stats string (e.g. for debug overlay or console).
    /// Caller owns the returned slice; free with freeStatsString(allocator, slice).
    /// detailed_map: when true, includes detailed block map in the string.
    pub fn buildStatsString(self: Allocator, allocator: std.mem.Allocator, detailed_map: bool) ![]const u8 {
        var c_str: ?[*:0]const u8 = null;
        c.vmaBuildStatsString(self.handle, @ptrCast(&c_str), @intFromBool(detailed_map));
        const ptr = c_str orelse return error.VmaBuildStatsStringFailed;
        const len = std.mem.len(ptr);
        const copy = try allocator.dupe(u8, ptr[0..len]);
        c.vmaFreeStatsString(self.handle, @ptrCast(ptr));
        return copy;
    }

    /// Free a stats string returned by buildStatsString.
    pub fn freeStatsString(self: Allocator, allocator: std.mem.Allocator, str: []const u8) void {
        _ = self;
        allocator.free(str);
    }

    /// Create a custom memory pool. Use AllocationCreateInfo.pool to allocate from it.
    pub fn createPool(self: Allocator, create_info: PoolCreateInfo) !Pool {
        var ci: c.VmaPoolCreateInfo = .{
            .memoryTypeIndex = create_info.memory_type_index,
            .flags = poolCreateFlagsToC(create_info.flags),
            .blockSize = create_info.block_size,
            .minBlockCount = create_info.min_block_count,
            .maxBlockCount = create_info.max_block_count,
            .frameInUseCount = create_info.frame_in_use_count,
            .priority = create_info.priority,
            .minAllocationAlignment = create_info.min_allocation_alignment,
            .pMemoryAllocateNext = null,
        };
        var pool: c.VmaPool = null;
        const result = c.vmaCreatePool(self.handle, &ci, &pool);
        if (result != c.VK_SUCCESS) return error.VmaPoolCreateFailed;
        return pool.?;
    }

    /// Destroy a custom pool. All allocations from the pool must be freed first.
    pub fn destroyPool(self: Allocator, pool: Pool) void {
        c.vmaDestroyPool(self.handle, pool);
    }

    /// Begin defragmentation. Returns a context to use with beginDefragmentationPass/endDefragmentationPass, then endDefragmentation.
    pub fn beginDefragmentation(self: Allocator, info: DefragmentationInfo) !DefragmentationContext {
        var ci: c.VmaDefragmentationInfo = .{
            .flags = defragmentationFlagsToC(info.flags),
            .pool = if (info.pool) |p| p else null,
            .maxCpuAllocationCount = info.max_cpu_allocation_count,
            .maxCpuBytesToMove = info.max_cpu_bytes_to_move,
            .maxGpuAllocationCount = info.max_gpu_allocation_count,
            .maxGpuBytesToMove = info.max_gpu_bytes_to_move,
        };
        var ctx: c.VmaDefragmentationContext = null;
        const result = c.vmaBeginDefragmentation(self.handle, &ci, &ctx);
        if (result != c.VK_SUCCESS) return error.VmaDefragmentationBeginFailed;
        return .{ .handle = ctx.? };
    }

    /// End defragmentation and free the context.
    pub fn endDefragmentation(self: Allocator, context: DefragmentationContext) void {
        c.vmaEndDefragmentation(self.handle, context.handle);
    }

    /// Begin a defragmentation pass. Fills pass_info with moves to perform; execute them (e.g. copy buffer/image), then call endDefragmentationPass.
    pub fn beginDefragmentationPass(self: Allocator, context: DefragmentationContext, pass_info: *DefragmentationPassMoveInfo) !void {
        var c_pass: c.VmaDefragmentationPassMoveInfo = .{
            .moveCount = 0,
            .pMoves = null,
        };
        const result = c.vmaBeginDefragmentationPass(self.handle, context.handle, &c_pass);
        if (result != c.VK_SUCCESS) return error.VmaDefragmentationPassFailed;
        pass_info.move_count = c_pass.moveCount;
        pass_info.p_moves = if (c_pass.pMoves) |p| @ptrCast(p) else null;
    }

    /// End a defragmentation pass after performing the moves.
    pub fn endDefragmentationPass(self: Allocator, context: DefragmentationContext, pass_info: *DefragmentationPassMoveInfo) !void {
        var c_pass: c.VmaDefragmentationPassMoveInfo = .{
            .moveCount = pass_info.move_count,
            .pMoves = if (pass_info.p_moves) |p| @ptrCast(p) else null,
        };
        const result = c.vmaEndDefragmentationPass(self.handle, context.handle, &c_pass);
        if (result != c.VK_SUCCESS) return error.VmaDefragmentationPassFailed;
    }
};

pub const BufferAllocation = struct {
    buffer: vk.Buffer,
    allocation: c.VmaAllocation,
    allocator: c.VmaAllocator,
};

pub const ImageAllocation = struct {
    image: vk.Image,
    allocation: c.VmaAllocation,
    allocator: c.VmaAllocator,
};

pub const AllocationInfo = struct {
    memory_type: u32,
    device_memory: vk.DeviceMemory,
    offset: u64,
    size: u64,
    p_mapped_data: ?[*]u8,
};

/// Per-heap budget info from vmaGetHeapBudgets. Use with Allocator.getHeapBudgets().
pub const HeapBudget = struct {
    block_bytes: u64,
    allocation_bytes: u64,
    usage: u64,
    budget: u64,
};

pub const AllocationCreateInfo = struct {
    usage: MemoryUsage = .auto,
    flags: AllocationCreateFlags = .{},
    /// For VK_EXT_memory_priority: priority in [0,1]; default 0.5. Ignored if allocator not created with ext_memory_priority.
    priority: f32 = 0.0,
    /// Required memory property flags; 0 means no requirement.
    required_flags: vk.MemoryPropertyFlags = .{},
    /// Preferred memory property flags; 0 means no preference.
    preferred_flags: vk.MemoryPropertyFlags = .{},
    /// Optional pool to allocate from; null = default pool.
    pool: ?Pool = null,

    pub const MemoryUsage = enum(c_int) {
        unknown = c.VMA_MEMORY_USAGE_UNKNOWN,
        gpu_only = c.VMA_MEMORY_USAGE_GPU_ONLY,
        cpu_only = c.VMA_MEMORY_USAGE_CPU_ONLY,
        cpu_to_gpu = c.VMA_MEMORY_USAGE_CPU_TO_GPU,
        gpu_to_cpu = c.VMA_MEMORY_USAGE_GPU_TO_CPU,
        cpu_copy = c.VMA_MEMORY_USAGE_CPU_COPY,
        gpu_lazily_allocated = c.VMA_MEMORY_USAGE_GPU_LAZILY_ALLOCATED,
        auto = c.VMA_MEMORY_USAGE_AUTO,
        auto_prefer_device = c.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
        auto_prefer_host = c.VMA_MEMORY_USAGE_AUTO_PREFER_HOST,
    };

    pub const AllocationCreateFlags = struct {
        dedicated_memory: bool = false,
        never_allocate: bool = false,
        mapped: bool = false,
        user_data_copy_string: bool = false,
        upper_address: bool = false,
        dont_bind: bool = false,
        within_budget: bool = false,
        can_alias: bool = false,
        host_access_sequential_write: bool = false,
        host_access_random: bool = false,

        fn toC(flags: AllocationCreateFlags) c.VmaAllocationCreateFlags {
            var f: c.VmaAllocationCreateFlags = 0;
            if (flags.dedicated_memory) f |= c.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT;
            if (flags.never_allocate) f |= c.VMA_ALLOCATION_CREATE_NEVER_ALLOCATE_BIT;
            if (flags.mapped) f |= c.VMA_ALLOCATION_CREATE_MAPPED_BIT;
            if (flags.user_data_copy_string) f |= c.VMA_ALLOCATION_CREATE_USER_DATA_COPY_STRING_BIT;
            if (flags.upper_address) f |= c.VMA_ALLOCATION_CREATE_UPPER_ADDRESS_BIT;
            if (flags.dont_bind) f |= c.VMA_ALLOCATION_CREATE_DONT_BIND_BIT;
            if (flags.within_budget) f |= c.VMA_ALLOCATION_CREATE_WITHIN_BUDGET_BIT;
            if (flags.can_alias) f |= c.VMA_ALLOCATION_CREATE_CAN_ALIAS_BIT;
            if (flags.host_access_sequential_write) f |= c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
            if (flags.host_access_random) f |= c.VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT;
            return f;
        }
    };
};

pub const AllocatorCreateFlags = struct {
    externally_synchronized: bool = false,
    khr_dedicated_allocation: bool = false,
    khr_bind_memory2: bool = false,
    ext_memory_budget: bool = false,
    amd_device_coherent_memory: bool = false,
    buffer_device_address: bool = false,
    ext_memory_priority: bool = false,
    khr_maintenance4: bool = false,
    khr_maintenance5: bool = false,
    khr_external_memory_win32: bool = false,
};

fn flagsToC(flags: AllocatorCreateFlags) c.VmaAllocatorCreateFlags {
    var f: c.VmaAllocatorCreateFlags = 0;
    if (flags.externally_synchronized) f |= c.VMA_ALLOCATOR_CREATE_EXTERNALLY_SYNCHRONIZED_BIT;
    if (flags.khr_dedicated_allocation) f |= c.VMA_ALLOCATOR_CREATE_KHR_DEDICATED_ALLOCATION_BIT;
    if (flags.khr_bind_memory2) f |= c.VMA_ALLOCATOR_CREATE_KHR_BIND_MEMORY2_BIT;
    if (flags.ext_memory_budget) f |= c.VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT;
    if (flags.amd_device_coherent_memory) f |= c.VMA_ALLOCATOR_CREATE_AMD_DEVICE_COHERENT_MEMORY_BIT;
    if (flags.buffer_device_address) f |= c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT;
    if (flags.ext_memory_priority) f |= c.VMA_ALLOCATOR_CREATE_EXT_MEMORY_PRIORITY_BIT;
    if (flags.khr_maintenance4) f |= c.VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE4_BIT;
    if (flags.khr_maintenance5) f |= c.VMA_ALLOCATOR_CREATE_KHR_MAINTENANCE5_BIT;
    if (flags.khr_external_memory_win32) f |= c.VMA_ALLOCATOR_CREATE_KHR_EXTERNAL_MEMORY_WIN32_BIT;
    return f;
}

fn allocationCreateInfoToC(info: AllocationCreateInfo) c.VmaAllocationCreateInfo {
    return .{
        .flags = AllocationCreateInfo.AllocationCreateFlags.toC(info.flags),
        .usage = @intCast(@intFromEnum(info.usage)),
        .requiredFlags = @bitCast(info.required_flags),
        .preferredFlags = @bitCast(info.preferred_flags),
        .memoryTypeBits = 0,
        .pool = if (info.pool) |p| p else null,
        .pUserData = null,
        .priority = info.priority,
    };
}

fn bufferCreateInfoToC(info: vk.BufferCreateInfo) c.VkBufferCreateInfo {
    return .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .pNext = null,
        .flags = @bitCast(info.flags),
        .size = info.size,
        .usage = @bitCast(info.usage),
        .sharingMode = @intCast(@intFromEnum(info.sharing_mode)),
        .queueFamilyIndexCount = info.queue_family_index_count,
        .pQueueFamilyIndices = if (info.p_queue_family_indices) |p| @ptrCast(p) else null,
    };
}

fn imageCreateInfoToC(info: vk.ImageCreateInfo) c.VkImageCreateInfo {
    return .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = null,
        .flags = @bitCast(info.flags),
        .imageType = @intCast(@intFromEnum(info.image_type)),
        .format = @intCast(@intFromEnum(info.format)),
        .extent = .{
            .width = info.extent.width,
            .height = info.extent.height,
            .depth = info.extent.depth,
        },
        .mipLevels = info.mip_levels,
        .arrayLayers = info.array_layers,
        .samples = @intCast(@as(u32, @bitCast(info.samples))),
        .tiling = @intCast(@intFromEnum(info.tiling)),
        .usage = @bitCast(info.usage),
        .sharingMode = @intCast(@intFromEnum(info.sharing_mode)),
        .queueFamilyIndexCount = info.queue_family_index_count,
        .pQueueFamilyIndices = if (info.p_queue_family_indices) |p| @ptrCast(p) else null,
        .initialLayout = @intCast(@intFromEnum(info.initial_layout)),
    };
}

fn vkResultFromC(r: c.VkResult) vk.Result {
    return @enumFromInt(r);
}
