//! List themes and their preview
//! read from their config file (theme.conf).

const std = @import("std");
const mem = @import("std").mem; // will be used to compare bytes
/// https://github.com/ziglibs/ini
const ini = @import("ini");

/// https://ziglearn.org/chapter-2/#allocators
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const Concatu8Result = struct {
    /// The value saved in memory
    result: []u8,

    alloc: std.mem.Allocator,

    /// Free memory
    pub fn deinit(self: *const Concatu8Result) void {
        self.alloc.free(self.result);
    }
};

const GetEnvVarsResult = struct {
    alloc: std.heap.ArenaAllocator,
    env_map: *std.process.EnvMap,

    /// Get an env variable value
    pub fn get(self: *const GetEnvVarsResult, key: []const u8) ?[]const u8 {
        return self.env_map.get(key);
    }

    /// Free memory
    pub fn deinit(self: *const GetEnvVarsResult) void {
        self.env_map.deinit();
        self.alloc.deinit();
    }
};

/// Concats a + b
pub fn concat_u8(a: []const u8, b: []const u8) !Concatu8Result {
    const alloc = gpa.allocator();
    const result = try std.fmt.allocPrint(alloc, "{s}{s}", .{ a, b });
    return Concatu8Result{ .result = result, .alloc = alloc };
}

pub fn get_env_vars() !GetEnvVarsResult {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const env_map = try arena.allocator().create(std.process.EnvMap);
    env_map.* = try std.process.getEnvMap(arena.allocator());
    return GetEnvVarsResult{
        .alloc = arena,
        .env_map = env_map,
    };
}

fn display_theme_and_preview(theme_conf_path: []const u8, theme_name: []const u8) !void {
    const file = try std.fs.cwd().openFile(theme_conf_path, .{});
    defer file.close();

    const allocator = gpa.allocator();

    var parser = ini.parse(allocator, file.reader());
    defer parser.deinit();

    const section_to_find = "main";
    const key_to_find = "preview";

    var section_found: bool = false;
    var key_found: bool = false;

    var writer = std.io.getStdOut().writer();

    while (try parser.next()) |record| {
        switch (record) {
            .section => |heading| {
                if (section_found and !mem.eql(u8, heading, section_to_find)) {
                    break;
                }
                if (mem.eql(u8, heading, section_to_find)) {
                    section_found = true;
                }
            },
            .property => |kv| {
                if (section_found and mem.eql(u8, kv.key, key_to_find)) {
                    try writer.print("{s} {s}\n", .{ theme_name, kv.value });
                    key_found = true;
                }
                if (key_found) {
                    break;
                }
            },
            .enumeration => |_| continue,
        }
    }
}

pub fn display_main_info(themes_dir: []const u8, theme_name: []const u8) !void {
    var theme_conf: []u8 = undefined;

    const concat4 = try concat_u8("/", theme_name);
    theme_conf = concat4.result;
    defer concat4.deinit();

    const concat5 = try concat_u8(theme_conf, "/config/theme.conf");
    theme_conf = concat5.result;
    defer concat5.deinit();

    const concat6 = try concat_u8(themes_dir, theme_conf);
    theme_conf = concat6.result;
    defer concat6.deinit();

    // check if file exists and parse it

    const file_stat = std.fs.cwd().statFile(theme_conf);

    if (file_stat) |_| {
        try display_theme_and_preview(theme_conf, theme_name);
    } else |_| {
        try std.io.getStdOut().writer().print("{s}\n", .{theme_name});
    }
}

pub fn main() !void {
    const env_vars = try get_env_vars();
    defer env_vars.deinit();

    const HOME_DIR = env_vars.get("HOME") orelse "";

    const concat1 = try concat_u8(HOME_DIR, "/.config/sway");
    const SWAY_DIR = concat1.result;
    defer concat1.deinit();

    const concat2 = try concat_u8(SWAY_DIR, "/themes");
    const SWAY_THEMES_DIR = concat2.result;
    defer concat2.deinit();

    const concat3 = try concat_u8(SWAY_THEMES_DIR, "/themes.txt");
    const THEMES_FILE = concat3.result;
    defer concat3.deinit();

    var themes_file = try std.fs.cwd().openFile(THEMES_FILE, .{});
    defer themes_file.close();

    var buf_reader = std.io.bufferedReader(themes_file.reader());
    var in_stream = buf_reader.reader();

    var buf: [1024]u8 = undefined;
    while (try in_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if (mem.eql(u8, line, "")) {
            break;
        }
        try display_main_info(SWAY_THEMES_DIR, line);
    }
}
