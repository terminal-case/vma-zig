const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vulkan_headers_dep = b.dependency("Vulkan-Headers", .{});
    const vulkan_dep = b.dependency("vulkan", .{
        .registry = vulkan_headers_dep.path("registry/vk.xml"),
    });
    const vulkan_mod = vulkan_dep.module("vulkan-zig");
    const vma_dep = b.dependency("vma", .{});
    const vma_include = vma_dep.path("include");
    const vk_include = vulkan_headers_dep.path("include");

    const vma_lib = b.addLibrary(.{
        .name = "vma-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/empty.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    vma_lib.root_module.addIncludePath(vma_include);
    vma_lib.root_module.addIncludePath(vk_include);
    vma_lib.addCSourceFile(.{
        .file = b.path("src/vma_cpp.cpp"),
        .flags = &.{
            "-std=c++17",
            "-DVMA_STATIC_VULKAN_FUNCTIONS=0",
        },
    });
    vma_lib.linkLibCpp();
    b.installArtifact(vma_lib);

    const vma_mod = b.addModule("vma", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    vma_mod.addImport("vulkan", vulkan_mod);
    vma_mod.addIncludePath(vma_include);
    vma_mod.addIncludePath(vk_include);

    // Test that the vma module compiles (no run, just build)
    const vma_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    vma_test.root_module.addImport("vulkan", vulkan_mod);
    vma_test.root_module.addIncludePath(vma_include);
    vma_test.root_module.addIncludePath(vk_include);
    vma_test.linkLibrary(vma_lib);
    vma_test.linkLibCpp();
    const test_step = b.step("test", "Run vma-zig tests");
    test_step.dependOn(&vma_test.step);
}
