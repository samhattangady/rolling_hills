const std = @import("std");
const player_sprites_raw = @import("player_sprites_raw.zig");
const title_sprites_raw = @import("title_sprite_raw.zig");
const moon_sprites_raw = @import("moon_sprite_raw.zig");
const PLAYER_SPRITE_SIZE = 14;
// pub const sprites = [_][]const u8{
//     "0000022100000002220000002200000022202000022211121002222211000121010010111012011110100001011110000111",
//     "000002210000000222000000220000000222200000222020000222000200022211101000222011000121020010111012011110100001011110000111",
// };
// pub const spr_bounds = [_][]const u8{
//     "2 2 10 10",
//     "2 0 10 12",
// };

fn in_bounds(x: u8, y: u8, xpos: u8, ypos: u8, w: u8, h: u8) bool {
    return (x >= xpos and x < xpos + w and y >= ypos and y < ypos + h);
}

fn as_u8(pixels: [4]u8) u8 {
    return @as(u8, (pixels[0] << 6) | (pixels[1] << 4) | (pixels[2] << 2) | (pixels[3] << 0));
}

fn to_2bpp(sprite: []const u8, bounds: []const u8, size: usize, allocator: std.mem.Allocator) []u8 {
    // the bounds is a string with format "{x} {y} {width} {height}"
    var contents = std.mem.split(u8, bounds, " ");
    const xpos = std.fmt.parseInt(u8, contents.next().?, 10) catch unreachable;
    const ypos = std.fmt.parseInt(u8, contents.next().?, 10) catch unreachable;
    const w = std.fmt.parseInt(u8, contents.next().?, 10) catch unreachable;
    const h = std.fmt.parseInt(u8, contents.next().?, 10) catch unreachable;
    std.debug.assert(sprite.len == @intCast(usize, w) * @intCast(usize, h));
    const num_bits = size * size * 2;
    const data_size = if (num_bits % 8 == 0) num_bits / 8 else 1 + (num_bits / 8);
    var bytes = allocator.alloc(u8, data_size) catch unreachable;
    var byte_index: usize = 0;
    var spr_index: usize = 0;
    var counter: usize = 0;
    var tmp: [4]u8 = undefined;
    var y: u8 = 0;
    while (y < size) : (y += 1) {
        var x: u8 = 0;
        while (x < size) : (x += 1) {
            if (in_bounds(x, y, xpos, ypos, w, h)) {
                tmp[counter] = sprite[spr_index] - 48;
                std.debug.assert(tmp[counter] < 4);
                counter += 1;
                spr_index += 1;
            } else {
                tmp[counter] = 0;
                counter += 1;
            }
            if (counter == 4) {
                counter = 0;
                bytes[byte_index] = as_u8(tmp);
                // std.debug.print("{any} as {d}\n", .{ tmp, bytes[byte_index] });
                byte_index += 1;
            }
        }
    }
    if (byte_index < data_size - 1) bytes[byte_index] = as_u8(tmp);
    return bytes;
}

fn to_2bpp_no_padding(sprite: []const u8, bounds: []const u8, size: usize, allocator: std.mem.Allocator) []u8 {
    _ = size;
    // the bounds is a string with format "{x} {y} {width} {height}"
    var contents = std.mem.split(u8, bounds, " ");
    const xpos = std.fmt.parseInt(u8, contents.next().?, 10) catch unreachable;
    const ypos = std.fmt.parseInt(u8, contents.next().?, 10) catch unreachable;
    const w = std.fmt.parseInt(u8, contents.next().?, 10) catch unreachable;
    const h = std.fmt.parseInt(u8, contents.next().?, 10) catch unreachable;
    std.debug.assert(sprite.len == @intCast(usize, w) * @intCast(usize, h));
    const num_bits = @intCast(usize, w) * @intCast(usize, h) * 2;
    const data_size = if (num_bits % 8 == 0) num_bits / 8 else 1 + (num_bits / 8);
    var bytes = allocator.alloc(u8, data_size) catch unreachable;
    var byte_index: usize = 0;
    var spr_index: usize = 0;
    var counter: usize = 0;
    var tmp: [4]u8 = undefined;
    var y: u8 = ypos;
    while (y < ypos + h) : (y += 1) {
        var x: u8 = xpos;
        while (x < xpos + w) : (x += 1) {
            if (in_bounds(x, y, xpos, ypos, w, h)) {
                tmp[counter] = sprite[spr_index] - 48;
                std.debug.assert(tmp[counter] < 4);
                counter += 1;
                spr_index += 1;
            } else {
                tmp[counter] = 0;
                counter += 1;
            }
            if (counter == 4) {
                counter = 0;
                bytes[byte_index] = as_u8(tmp);
                // std.debug.print("{any} as {d}\n", .{ tmp, bytes[byte_index] });
                byte_index += 1;
            }
        }
    }
    if (byte_index < data_size - 1) bytes[byte_index] = as_u8(tmp);
    return bytes;
}

const sprite_comment = "// this was generated using the aseprite_importer.zig (and aseprite_importer.lua) functions\n\n";

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    var allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }
    {
        // player sprites
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();
        string.appendSlice(sprite_comment) catch unreachable;
        string.appendSlice("pub const player_sprites = &[_][]const u8{\n") catch unreachable;
        for (player_sprites_raw.sprites) |sprite, i| {
            const w4_2bpp = to_2bpp(sprite[0..], player_sprites_raw.bounds[i][0..], PLAYER_SPRITE_SIZE, allocator);
            defer allocator.free(w4_2bpp);
            string.appendSlice("&.{") catch unreachable;
            for (w4_2bpp) |byte| {
                var buffer: [8]u8 = undefined;
                const p = std.fmt.bufPrint(buffer[0..], "{d}, ", .{byte}) catch unreachable;
                string.appendSlice(p) catch unreachable;
            }
            string.appendSlice("},\n") catch unreachable;
        }
        string.appendSlice("};\n") catch unreachable;
        var sprite_file = try std.fs.cwd().createFile("src/player_sprites.zig", .{});
        defer sprite_file.close();
        _ = sprite_file.writeAll(string.items) catch unreachable;
    }
    {
        // title sprites
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();
        string.appendSlice(sprite_comment) catch unreachable;
        string.appendSlice("pub const title_sprites = &[_][]const u8{\n") catch unreachable;
        for (title_sprites_raw.sprites) |sprite, i| {
            const w4_2bpp = to_2bpp_no_padding(sprite[0..], title_sprites_raw.bounds[i][0..], 160, allocator);
            defer allocator.free(w4_2bpp);
            string.appendSlice("&.{") catch unreachable;
            for (w4_2bpp) |byte| {
                var buffer: [8]u8 = undefined;
                const p = std.fmt.bufPrint(buffer[0..], "{d}, ", .{byte}) catch unreachable;
                string.appendSlice(p) catch unreachable;
            }
            string.appendSlice("},\n") catch unreachable;
        }
        string.appendSlice("};\n") catch unreachable;
        string.appendSlice("pub const sprite_bounds = &[_][]const u8{\n") catch unreachable;
        for (title_sprites_raw.bounds) |bounds, i| {
            string.appendSlice("&.{") catch unreachable;
            std.debug.print("parsing bounds {d} = {s}\n", .{ i, bounds });
            var nums = std.mem.split(u8, bounds, " ");
            while (nums.next()) |num| {
                std.debug.print("{d}\t", .{num});
                var buffer: [8]u8 = undefined;
                const p = std.fmt.bufPrint(buffer[0..], "{s}, ", .{num}) catch unreachable;
                string.appendSlice(p) catch unreachable;
            }
            std.debug.print("\n", .{});
            string.appendSlice("},\n") catch unreachable;
        }
        string.appendSlice("};\n") catch unreachable;
        var sprite_file = try std.fs.cwd().createFile("src/title_sprites.zig", .{});
        defer sprite_file.close();
        _ = sprite_file.writeAll(string.items) catch unreachable;
    }
    {
        // moon sprites
        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();
        string.appendSlice(sprite_comment) catch unreachable;
        string.appendSlice("pub const moon_sprites = &[_][]const u8{\n") catch unreachable;
        for (moon_sprites_raw.sprites) |sprite, i| {
            const w4_2bpp = to_2bpp_no_padding(sprite[0..], moon_sprites_raw.bounds[i][0..], 160, allocator);
            defer allocator.free(w4_2bpp);
            string.appendSlice("&.{") catch unreachable;
            for (w4_2bpp) |byte| {
                var buffer: [8]u8 = undefined;
                const p = std.fmt.bufPrint(buffer[0..], "{d}, ", .{byte}) catch unreachable;
                string.appendSlice(p) catch unreachable;
            }
            string.appendSlice("},\n") catch unreachable;
        }
        string.appendSlice("};\n") catch unreachable;
        string.appendSlice("pub const moon_bounds = &[_][]const u8{\n") catch unreachable;
        for (moon_sprites_raw.bounds) |bounds, i| {
            string.appendSlice("&.{") catch unreachable;
            std.debug.print("parsing bounds {d} = {s}\n", .{ i, bounds });
            var nums = std.mem.split(u8, bounds, " ");
            while (nums.next()) |num| {
                std.debug.print("{d}\t", .{num});
                var buffer: [8]u8 = undefined;
                const p = std.fmt.bufPrint(buffer[0..], "{s}, ", .{num}) catch unreachable;
                string.appendSlice(p) catch unreachable;
            }
            std.debug.print("\n", .{});
            string.appendSlice("},\n") catch unreachable;
        }
        string.appendSlice("};\n") catch unreachable;
        string.appendSlice("pub const moon_mood_sprites = &[_][]const u8{\n") catch unreachable;
        for (moon_sprites_raw.mood_sprites) |sprite, i| {
            const w4_2bpp = to_2bpp_no_padding(sprite[0..], moon_sprites_raw.mood_bounds[i][0..], 160, allocator);
            defer allocator.free(w4_2bpp);
            string.appendSlice("&.{") catch unreachable;
            for (w4_2bpp) |byte| {
                var buffer: [8]u8 = undefined;
                const p = std.fmt.bufPrint(buffer[0..], "{d}, ", .{byte}) catch unreachable;
                string.appendSlice(p) catch unreachable;
            }
            string.appendSlice("},\n") catch unreachable;
        }
        string.appendSlice("};\n") catch unreachable;
        string.appendSlice("pub const moon_mood_bounds = &[_][]const u8{\n") catch unreachable;
        for (moon_sprites_raw.mood_bounds) |bounds, i| {
            string.appendSlice("&.{") catch unreachable;
            std.debug.print("parsing bounds {d} = {s}\n", .{ i, bounds });
            var nums = std.mem.split(u8, bounds, " ");
            while (nums.next()) |num| {
                std.debug.print("{d}\t", .{num});
                var buffer: [8]u8 = undefined;
                const p = std.fmt.bufPrint(buffer[0..], "{s}, ", .{num}) catch unreachable;
                string.appendSlice(p) catch unreachable;
            }
            std.debug.print("\n", .{});
            string.appendSlice("},\n") catch unreachable;
        }
        string.appendSlice("};\n") catch unreachable;
        string.appendSlice("pub const moon_eyeball_sprites = &[_][]const u8{\n") catch unreachable;
        for (moon_sprites_raw.eyeball_sprites) |sprite, i| {
            const w4_2bpp = to_2bpp_no_padding(sprite[0..], moon_sprites_raw.eyeball_bounds[i][0..], 160, allocator);
            defer allocator.free(w4_2bpp);
            string.appendSlice("&.{") catch unreachable;
            for (w4_2bpp) |byte| {
                var buffer: [8]u8 = undefined;
                const p = std.fmt.bufPrint(buffer[0..], "{d}, ", .{byte}) catch unreachable;
                string.appendSlice(p) catch unreachable;
            }
            string.appendSlice("},\n") catch unreachable;
        }
        string.appendSlice("};\n") catch unreachable;
        string.appendSlice("pub const moon_eyeball_bounds = &[_][]const u8{\n") catch unreachable;
        for (moon_sprites_raw.eyeball_bounds) |bounds, i| {
            string.appendSlice("&.{") catch unreachable;
            std.debug.print("parsing bounds {d} = {s}\n", .{ i, bounds });
            var nums = std.mem.split(u8, bounds, " ");
            while (nums.next()) |num| {
                std.debug.print("{d}\t", .{num});
                var buffer: [8]u8 = undefined;
                const p = std.fmt.bufPrint(buffer[0..], "{s}, ", .{num}) catch unreachable;
                string.appendSlice(p) catch unreachable;
            }
            std.debug.print("\n", .{});
            string.appendSlice("},\n") catch unreachable;
        }
        string.appendSlice("};\n") catch unreachable;
        var sprite_file = try std.fs.cwd().createFile("src/moon_sprites.zig", .{});
        defer sprite_file.close();
        _ = sprite_file.writeAll(string.items) catch unreachable;
    }
}
