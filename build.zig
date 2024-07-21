const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen = b.addExecutable(.{
        .name = "gen",
        .root_source_file = b.path("src/gen.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(gen);

    const run_cmd = b.addRunArtifact(gen);

    run_cmd.step.dependOn(b.getInstallStep());

    const gen_step = b.step("gen", "Generate the data");
    gen_step.dependOn(&run_cmd.step);

    const gen_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/gen.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(gen_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
