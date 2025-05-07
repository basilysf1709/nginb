const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the user to cross compile.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the user to optimize binary size and speed.
    const optimize = b.standardOptimizeOption(.{});

    // Create the executable artifact.
    const exe = b.addExecutable(.{
        .name = "zig_http_server", // Updated executable name
        .root_source_file = b.path("src/main.zig"), // Path to your main source file
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the standard
    // location when the user invokes the "install" step (the default step).
    b.installArtifact(exe);

    // Creates a step for running the executable.
    const run_cmd = b.addRunArtifact(exe);

    // The run step requires that the executable is built first.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates a "run" step in the build graph, to be executed when the user
    // invokes `zig build run`.
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for running the tests.
    // All .zig files imported by src/main.zig (including those in src/server/ and src/utils/)
    // that contain tests will be included.
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Creates a "test" step in the build graph, to be executed when the user
    // invokes `zig build test`.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
