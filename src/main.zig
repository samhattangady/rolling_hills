const w4 = @import("wasm4.zig");
const std = @import("std");
const SCREEN_WIDTH = 160;
const SCREEN_HEIGHT = 160;

const smiley = [8]u8{
    0b11000011,
    0b10000001,
    0b00100100,
    0b00100100,
    0b00000000,
    0b00100100,
    0b10011001,
    0b11000011,
};

var prev_gamepad: u8 = 0;
var ticks: u32 = 0;
var index: f32 = 0;
var wave_slope: f32 = 1.0;
var wave_depth: f32 = 1.0;
var wave_current_index: usize = 0;
var terrain_current_index: f32 = 0;

const NUM_WAVE_POINTS = SCREEN_WIDTH * 2;

var terrain: [NUM_WAVE_POINTS]f32 = undefined;

export fn start() void {
    update_terrain();
    w4.PALETTE.* = .{
        0x312137,
        0x1a2129,
        0x713141,
        0x512839,
    };
}

export fn update() void {
    defer prev_gamepad = w4.GAMEPAD1.*;
    defer ticks += 1;
    defer index += 0.7;

    const gamepad = w4.GAMEPAD1.*;
    const pressed_this_frame = gamepad & (gamepad ^ prev_gamepad);
    _ = gamepad & pressed_this_frame;

    var buffer: [128]u8 = undefined;
    const index_text = std.fmt.bufPrint(&buffer, "{d}", .{@floatToInt(usize, index) / SCREEN_WIDTH}) catch unreachable;
    w4.DRAW_COLORS.* = 0x03;
    w4.text(index_text, 10, 10);
    if (@floatToInt(usize, index) % SCREEN_WIDTH == 0) update_terrain();
    {
        var i: usize = 0;
        while (i < SCREEN_WIDTH) : (i += 1) {
            const terrain_index = (i + @floatToInt(usize, index)) % terrain.len;
            const height = terrain[terrain_index];
            const y: i32 = 2 * SCREEN_HEIGHT / 3 + @floatToInt(i32, (height * @intToFloat(f32, SCREEN_HEIGHT / 8)));
            w4.DRAW_COLORS.* = 0x44;
            w4.vline(@intCast(i32, i), y, SCREEN_HEIGHT);
            if (terrain_index % SCREEN_WIDTH == 0) {
                w4.DRAW_COLORS.* = 0x33;
                w4.vline(@intCast(i32, i), 0, SCREEN_HEIGHT);
            }
        }
    }
}

fn update_terrain() void {
    var buffer: [128]u8 = undefined;
    var i: usize = wave_current_index % NUM_WAVE_POINTS;
    w4.trace(std.fmt.bufPrint(&buffer, "gen terrain from {d} to {d}", .{ i, i + SCREEN_WIDTH }) catch unreachable);
    while (i < (wave_current_index % NUM_WAVE_POINTS) + SCREEN_WIDTH) : (i += 1) {
        terrain[i] = std.math.cos(terrain_current_index / std.math.pi);
        terrain_current_index += 0.3;
    }
    wave_current_index += SCREEN_WIDTH;
}
