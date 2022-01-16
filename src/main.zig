const w4 = @import("wasm4.zig");
const std = @import("std");
const SCREEN_WIDTH = 160;
const SCREEN_HEIGHT = 160;
const TERRAIN_WIDTH = 2;
const TERRAIN_MIN_MIN = -1.0;
const TERRAIN_MIN_MAX = -0.6;
const TERRAIN_MAX_MIN = 0.6;
const TERRAIN_MAX_MAX = 1.0;
const TERRAIN_WIDTH_MIN = 0.7;
const TERRAIN_WIDTH_MAX = 1.3;
const PLAYER_RADIUS = 7;
comptime {
    std.debug.assert(TERRAIN_WIDTH > 1);
}

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

const TerrainDirection = enum {
    up,
    down,

    pub fn toggle(self: *const TerrainDirection) TerrainDirection {
        return switch (self.*) {
            .up => .down,
            .down => .up,
        };
    }

    pub fn needs_change(self: *const TerrainDirection, change: f32) bool {
        return switch (self.*) {
            .up => return change < 0,
            .down => return change > 0,
        };
    }
};

var prev_gamepad: u8 = 0;
var ticks: u32 = 0;
var x_pos: f32 = 0;
var wave_slope: f32 = 1.0;
var wave_depth: f32 = 1.0;
var wave_current_index: usize = 0;
var terrain_current_index: f32 = 0;
var prev_terrain_section_generated: u8 = TERRAIN_WIDTH - 1;
var terrain_direction: TerrainDirection = .down;
var terrain_width_scale: f32 = 1.0;
var terrain_min: f32 = -1.0;
var terrain_max: f32 = 0.4;
var player_pos: Vec2 = .{ .x = 30, .y = 30 };
var player_vel: Vec2 = .{ .x = 1, .y = 1 };
var button_down_x_vel: f32 = 1.0;
var prev_ground: bool = false;
var prev_slow: u32 = 0;
var prev_released: u32 = 0;
var left_ground: u32 = 0;
var buffer: [128]u8 = undefined;
var rng = std.rand.DefaultPrng.init(0);

const NUM_WAVE_POINTS = SCREEN_WIDTH * TERRAIN_WIDTH;

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
    var ground_contact: bool = false;
    var slope_dir: TerrainDirection = .up;

    const gamepad = w4.GAMEPAD1.*;
    const pressed_this_frame = gamepad & (gamepad ^ prev_gamepad);
    _ = gamepad & pressed_this_frame;
    const button_down = gamepad & w4.BUTTON_1 != 0;
    const button_released = (prev_gamepad & w4.BUTTON_1 != 0) and (!button_down);
    const button_pressed = (prev_gamepad & w4.BUTTON_1 == 0) and (button_down);
    if (button_released) prev_released = ticks;

    player_pos.y += player_vel.y;
    if (button_down) {
        player_vel.y += 0.31;
    } else {
        // player_pos.y -= 1;
    }

    if (button_pressed) button_down_x_vel = player_vel.x;

    const terrain_height = terrain_height_at(@floatToInt(usize, x_pos) + @intCast(usize, player_pos.xi())) - PLAYER_RADIUS;
    if (@floatToInt(i32, player_pos.y) > terrain_height) {
        ground_contact = true;
        player_pos.y = @intToFloat(f32, terrain_height);
    }
    if (@floatToInt(i32, player_pos.y) < 0) player_pos.y = @intToFloat(f32, 0);
    const terrain_height_next = terrain_height_at(@floatToInt(usize, x_pos + 1) + @intCast(usize, player_pos.xi())) - PLAYER_RADIUS;
    slope_dir = if (terrain_height_next > terrain_height) TerrainDirection.down else TerrainDirection.up;

    // if player just hit ground, as is on up slope, then they need to slow down their xvel
    if ((ticks - prev_slow > 60) and (ticks - prev_released > 20) and prev_ground and !ground_contact and slope_dir == .up) {
        player_vel.x *= 0.7;
        player_vel.x = std.math.clamp(player_vel.x, 0.4, 2.0);
        prev_slow = ticks;
    }
    if (prev_ground and !ground_contact) left_ground = ticks;

    if (ground_contact and button_down) {
        // speed up the player if going down slope
        // slow down if going up slope
        switch (slope_dir) {
            .down => player_vel.x += 0.06,
            .up => {
                // if the player is few frames late in releasing, we don't want to punish.
                // just want to dissuade holding down the button. so check the slope 5 frames ago
                const terrain_height_prev = terrain_height_at(@floatToInt(usize, x_pos - 5 * player_vel.x) + @intCast(usize, player_pos.xi())) - PLAYER_RADIUS;
                if (terrain_height_prev > terrain_height) player_vel.x -= 0.06;
            },
        }
    } else if (ground_contact) {
        // if we are on up slope
        // player y should be updated according to their x speed.
        // what if we are on down slope?
        switch (slope_dir) {
            .up => {
                const terrain_height_prev = terrain_height_at(@floatToInt(usize, x_pos - player_vel.x) + @intCast(usize, player_pos.xi())) - PLAYER_RADIUS;
                const y_diff = terrain_height - terrain_height_prev;
                player_vel.y = @intToFloat(f32, y_diff) * 1.2;
                player_vel.y = std.math.clamp(player_vel.y, -player_vel.x * 2, -player_vel.x * 0.5);
            },
            .down => {
                if (button_released) {
                    player_vel.x = std.math.clamp(player_vel.x, button_down_x_vel, 2 * button_down_x_vel);
                    // convert yvel into xvel
                    // player_vel.x = player_vel.y;
                    // player_vel.x = std.math.clamp(player_vel.x, 0.4, 3.5);
                }
            },
        }
    } else {}
    player_vel.x = std.math.clamp(player_vel.x, 0.4, 3.5);
    player_vel.y += 0.11;
    if (prev_slow == ticks and player_vel.y < -0.4)
        player_vel.y = -0.4;

    const index_text = std.fmt.bufPrint(&buffer, "{d:.4} {b} {s}", .{ player_vel.x, (ground_contact and button_down), @tagName(slope_dir) }) catch unreachable;
    w4.DRAW_COLORS.* = 0x03;
    w4.text(index_text, 10, 10);
    update_terrain();
    {
        var i: usize = 0;
        while (i < SCREEN_WIDTH) : (i += 1) {
            const terrain_index = (i + @floatToInt(usize, x_pos));
            const y = terrain_height_at(terrain_index);
            w4.DRAW_COLORS.* = 0x44;
            w4.vline(@intCast(i32, i), y, SCREEN_HEIGHT);
        }
    }
    if (@intToFloat(f32, terrain_height) - player_pos.y < PLAYER_RADIUS * 1.5) {
        w4.DRAW_COLORS.* = 0x22;
    } else {
        w4.DRAW_COLORS.* = 0x20;
    }
    w4.oval(player_pos.xi() - PLAYER_RADIUS, player_pos.yi() - PLAYER_RADIUS, PLAYER_RADIUS * 2, PLAYER_RADIUS * 2);
    if (prev_slow == ticks) {
        w4.DRAW_COLORS.* = 0x44;
        w4.oval(player_pos.xi() - 2, player_pos.yi() - 2, 4, 4);
    }
    prev_gamepad = w4.GAMEPAD1.*;
    ticks += 1;
    x_pos += player_vel.x;
    prev_ground = ground_contact;
}

fn update_terrain() void {
    const current_terrain_section: usize = @floatToInt(usize, x_pos) / SCREEN_WIDTH;
    const terrain_section_to_be_generated = (current_terrain_section + 1) % TERRAIN_WIDTH;
    if (ticks != 0) {
        if (terrain_section_to_be_generated == prev_terrain_section_generated) return;
    } else {
        gen_terrain(0);
    }
    gen_terrain(terrain_section_to_be_generated);
}

fn gen_terrain(terrain_section_to_be_generated: usize) void {
    prev_terrain_section_generated = @intCast(u8, terrain_section_to_be_generated);
    const start_i: usize = terrain_section_to_be_generated * SCREEN_WIDTH;
    var prev_val = get_current_terrain_height();
    var i: usize = start_i;
    while (i < start_i + SCREEN_WIDTH) : (i += 1) {
        terrain[i] = get_current_terrain_height();
        defer prev_val = terrain[i];
        defer terrain_current_index += 0.3 * terrain_width_scale;
        const change = terrain[i] - prev_val;
        if (terrain_direction.needs_change(change)) {
            switch (terrain_direction) {
                .up => {
                    terrain_max = map(0, 1, TERRAIN_MAX_MIN, TERRAIN_MAX_MAX, rng.random().float(f32));
                },
                .down => {
                    terrain_min = map(0, 1, TERRAIN_MIN_MIN, TERRAIN_MIN_MAX, rng.random().float(f32));
                },
            }
            terrain_width_scale = map(0, 1, TERRAIN_WIDTH_MIN, TERRAIN_WIDTH_MAX, rng.random().float(f32));
            terrain_direction = terrain_direction.toggle();
        }
    }
    wave_current_index += SCREEN_WIDTH;
}

fn get_current_terrain_height() f32 {
    return -map(-1, 1, terrain_min, terrain_max, std.math.cos(terrain_current_index / std.math.pi));
}

fn print(comptime str: []const u8, args: anytype) void {
    const msg = std.fmt.bufPrint(&buffer, str, args) catch unreachable;
    w4.trace(msg);
}

fn map(start_in: f32, end_in: f32, start_out: f32, end_out: f32, val: f32) f32 {
    std.debug.assert(start_in != end_in);
    std.debug.assert(start_out != end_out);
    const t = (val - start_in) / (end_in - start_in);
    return (start_out * (1.0 - t)) + (end_out * t);
}

fn terrain_height_at(terrain_index: usize) i32 {
    const height = terrain[terrain_index % terrain.len];
    const y: i32 = 2 * SCREEN_HEIGHT / 3 + @floatToInt(i32, (height * @intToFloat(f32, SCREEN_HEIGHT / 8)));
    return y;
}

const Vec2 = struct {
    const Self = @This();
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub fn xi(self: *const Self) i32 {
        return @floatToInt(i32, self.x);
    }
    pub fn yi(self: *const Self) i32 {
        return @floatToInt(i32, self.y);
    }
};
