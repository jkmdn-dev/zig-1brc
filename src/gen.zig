const std = @import("std");

const debug = std.debug;
const panic = debug.panic;
const assert = debug.assert;

const fmt = std.fmt;

const fs = std.fs;
const max_path_bytes = fs.max_path_bytes;

const stations = @import("stations.zig");

const MesurmentsFileOptions = struct {
    dir: []const u8 = "data",
    name: []const u8 = "mesurments.txt",
    clear_file: bool = false,
};

fn openFile(dir: fs.Dir, file_name: []const u8) !fs.File {
    return dir.openFile(file_name, .{ .mode = .read_write });
}

fn createFile(dir: fs.Dir, file_name: []const u8) !fs.File {
    return dir.createFile(file_name, .{});
}

fn mesurmentsFile(options: MesurmentsFileOptions) fs.File {
    const data_dir_path = options.dir;
    const file_name = options.name;

    const fileOp = if (options.clear_file) &createFile else &openFile;

    const cwd = fs.cwd();
    const file = file_blk: {
        if (cwd.openDir(data_dir_path, .{})) |data_dir| {
            break :file_blk fileOp(data_dir, file_name) catch |open_mesur_err| {
                switch (open_mesur_err) {
                    error.FileNotFound => {
                        // safe since the file didn't exist before
                        break :file_blk data_dir.createFile(file_name, .{}) catch unreachable;
                    },
                    else => {
                        panic(
                            "can't handle open mesurments.txe with error: {any}",
                            .{open_mesur_err},
                        );
                    },
                }
            };
        } else |open_data_err| {
            switch (open_data_err) {
                error.FileNotFound => {
                    cwd.makeDir("data") catch |mk_data_err| std.debug.panic(
                        "can't create data dir with error: {any}",
                        .{mk_data_err},
                    );

                    // safe since we hnow "data" was created by this point
                    var new_dir = cwd.openDir(data_dir_path, .{}) catch unreachable;
                    defer new_dir.close();

                    //safe due to data dir didn't exist;
                    break :file_blk new_dir.createFile(file_name, .{}) catch unreachable;
                },
                else => {
                    panic(
                        "can't handle open data dir with error: {any}",
                        .{open_data_err},
                    );
                },
            }
        }
    };
    if (options.clear_file) {
        const file_size = stat_blk: {
            // safe: file exist from above
            const stat = file.stat() catch unreachable;
            break :stat_blk stat.size;
        };

        assert(file_size == 0);
        assert(file.getEndPos() catch unreachable == 0);
    }

    assert(file.getPos() catch unreachable == 0);

    return file;
}
pub const Measurement = struct {
    name: []const u8,
    temp: f32,

    const Self = @This();
    const max_serialized_bytes = 128;
    var buffer: [max_serialized_bytes]u8 = undefined;

    pub fn serialize(self: Self, comptime newline: bool) []const u8 {
        const format: []const u8 = comptime if (newline) "{s};{d:.1}\n" else "{s};{d:.1}";

        const output = fmt.bufPrint(
            &buffer,
            format,
            .{ self.name, self.temp },
        ) catch unreachable;
        // defer buffer = undefined;

        assert(output.len < max_serialized_bytes);
        assert(output.len > 0);

        return output;
    }
};

pub const TemperatureDefinition = struct {
    mean: f32,
    standard_deviation: ?f32 = null,
};

pub const StationOptions = struct {
    temp_def: TemperatureDefinition,
    rng_seed: ?u64 = null,
};

const GlobalSeed = struct {
    var seed: ?u64 = null;
};

fn setGlobalSeed(seed: u64) void {
    GlobalSeed.seed = seed;
}

fn initSeed(maybe_seed: ?u64) u64 {
    return maybe_seed orelse seed_blk: {
        break :seed_blk GlobalSeed.seed orelse {
            const timestamp: u128 = @bitCast(std.time.nanoTimestamp());
            break :seed_blk @truncate(timestamp);
        };
    };
}

const Container = struct {
    var stations: [413]StationDefinition = undefined;
};

pub const StationDefinition = struct {
    name: []const u8,
    mean: f32,
    standard_deviation: f32,
    seed: u64,
    rng: std.Random.Xoshiro256,

    const Self = @This();
    const stations: [413]Self = undefined;

    pub fn init(name: []const u8, options: StationOptions) Self {
        const seed: u64 = initSeed(options.rng_seed);
        const standard_deviation = options.temp_def.standard_deviation orelse 10;

        return Self{
            .name = name,
            .mean = options.temp_def.mean,
            .standard_deviation = standard_deviation,
            .seed = seed,
            .rng = std.Random.DefaultPrng.init(seed),
        };
    }

    fn randomTemp(self: *StationDefinition) f32 {
        // using central limit theorem to approx. a normal distribution

        var temp: f32 = 0;

        const n = 10;
        for (0..n - 1) |_| {
            const num: f32 = @floatFromInt(self.rng.next());
            const denum: f32 = @floatFromInt(std.math.maxInt(u64));
            temp += num / denum;
        }

        assert(temp > 0);
        assert(temp < n);

        // correct the mean
        temp -= n / 2;

        assert(temp > -5);
        assert(temp < 5);

        // correct the std to one
        temp *= sqrt_blk: {
            const num: f32 = @floatFromInt(n);
            assert(num > 0.0);

            const sd: f32 = @sqrt(num / 12.0);
            break :sqrt_blk sd;
        };

        // adjust std and mean
        return temp * self.standard_deviation + self.mean;
    }

    fn randomMaeasurement(self: *StationDefinition) Measurement {
        return Measurement{
            .temp = self.randomTemp(),
            .name = self.name,
        };
    }
};

fn setStations() void {
    Container.stations = stations.get();
}

const RandomMaeasurementOptions = struct {
    amount: usize = 100_000,
    rng_seed: ?u64 = null,
};

const RandomMaeasurements = struct {
    amount: usize,
    seed: u64,
    rng: std.Random.Xoshiro256,
    current: usize,

    const Self = @This();

    pub fn init(options: RandomMaeasurementOptions) Self {
        const seed = initSeed(options.rng_seed);
        return Self{
            .seed = seed,
            .rng = std.Random.Xoshiro256.init(seed),
            .amount = options.amount,
            .current = 0,
        };
    }

    pub fn next(self: *Self) ?Measurement {
        if (self.current >= self.amount) return null;
        self.current += 1;

        // make sure norm_rand will never be exactly 1.0!
        const rand_num = rand_num_blk: {
            const tmp_rand_num = self.rng.next();
            if (tmp_rand_num == std.math.maxInt(u64)) break :rand_num_blk tmp_rand_num - 1;
            break :rand_num_blk tmp_rand_num;
        };
        assert(rand_num < std.math.maxInt(u64));

        const norm_rand = @as(f64, @floatFromInt(rand_num)) / @as(f64, @floatFromInt(std.math.maxInt(u64)));
        assert(norm_rand < 1);
        assert(norm_rand >= 0);

        const idx: usize = @as(u64, @intFromFloat(@floor(norm_rand * Container.stations.len)));
        assert(idx < Container.stations.len);

        return Container.stations[idx].randomMaeasurement();
    }
};

pub const MakeMeasurementsFileOptions = struct {
    amount: usize = 100_000,
    data_dir_path: []const u8 = "data",
    file_name: []const u8 = "mesurments.txt",
    clear_file: bool = false,
    use_global_seed: bool = false,
    global_seed: u64 = 123456789,
};

pub fn makeMeasurementsFile(options: MakeMeasurementsFileOptions) !void {
    if (options.use_global_seed) setGlobalSeed(options.global_seed);

    setStations();

    const mesurments_file = mesurmentsFile(.{
        .name = options.file_name,
        .dir = options.data_dir_path,
        .clear_file = options.clear_file,
    });
    defer mesurments_file.close();

    var random_maeasurements = RandomMaeasurements.init(.{ .amount = options.amount });
    while (random_maeasurements.next()) |m| {
        const bytes = m.serialize(true);
        const bytes_written = try mesurments_file.write(bytes);
        assert(bytes_written == bytes.len);
    }
}

pub fn main() !void {
    try makeMeasurementsFile(.{});
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectEqualStrings = testing.expectEqualStrings;

test "some random mesurments" {
    setGlobalSeed(123456789);
    setStations();

    var random_maeasurements = RandomMaeasurements.init(
        .{ .amount = 10 },
    );

    var buffer: [Measurement.max_serialized_bytes * 10]u8 = undefined;
    var idx: usize = 0;

    while (random_maeasurements.next()) |m| {
        const serd = m.serialize(false);
        const result = try fmt.bufPrint(buffer[idx..], "{s}\n", .{serd});
        idx += result.len;
    }

    const expectedOuput =
        \\Moscow;-4.7
        \\Reykjavík;-6.2
        \\İzmir;7.4
        \\Kathmandu;7.8
        \\Hargeisa;11.2
        \\Budapest;0.8
        \\Vilnius;-4.5
        \\Addis Ababa;5.5
        \\Changsha;6.9
        \\Frankfurt;0.1
        \\
    ;

    try expectEqualStrings(expectedOuput, buffer[0..idx]);
}

const io = std.io;

test "make measurements file" {
    const file_name = "make_mesurments_file_test.txt";
    try makeMeasurementsFile(.{
        .amount = 10,
        .file_name = file_name,
        .clear_file = true,
        .use_global_seed = true,
    });

    const cwd = fs.cwd();

    const file = cwd.openFile("data/" ++ file_name, .{ .mode = .read_only }) catch unreachable;
    defer file.close();

    var buffered_reader = io.bufferedReader(file.reader());
    const reader = buffered_reader.reader();

    var file_content: [4096]u8 = undefined;
    var idx: usize = 0;
    var line_count: usize = 0;
    while (try reader.readUntilDelimiterOrEof(file_content[idx..], '\n')) |line| {
        file_content[idx + line.len] = '\n';
        idx += line.len + 1;
        line_count += 1;
    }

    try expectEqual(10, line_count);

    const expectedOuput =
        \\Moscow;-4.7
        \\Reykjavík;-6.2
        \\İzmir;7.4
        \\Kathmandu;7.8
        \\Hargeisa;11.2
        \\Budapest;0.8
        \\Vilnius;-4.5
        \\Addis Ababa;5.5
        \\Changsha;6.9
        \\Frankfurt;0.1
        \\
    ;

    try expectEqualStrings(expectedOuput, file_content[0..idx]);
}
