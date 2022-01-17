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
const START_NOTE_FREQ = 440;
const PLAYER_MIN_X_SPEED = 0.4;
const PLAYER_MAX_X_SPEED = 3.5;
comptime {
    assert(TERRAIN_WIDTH > 1);
}
const pi = 3.14159265358979323846264338327950288419716939937510;
const bunny_width = 14;
const bunny_height = 16;
const bunny_flags = 1; // BLIT_2BPP
const bunny = [_]u8{ 0x00, 0x18, 0x0b, 0x00, 0x00, 0x56, 0x2a, 0xc0, 0x00, 0x56, 0x2a, 0xc0, 0x00, 0xd6, 0x2a, 0xc0, 0x00, 0xd6, 0xfe, 0xc0, 0x00, 0x56, 0x57, 0xc0, 0x03, 0x55, 0x55, 0x40, 0x01, 0x55, 0xf5, 0xf0, 0x0a, 0x95, 0x55, 0x70, 0x03, 0x65, 0x55, 0x70, 0x00, 0x95, 0x56, 0xc0, 0x00, 0xd9, 0x6b, 0x00, 0x03, 0x65, 0xd5, 0xc0, 0x03, 0x75, 0xd5, 0xc0, 0x00, 0xdf, 0x57, 0x00, 0x00, 0x35, 0x5c, 0x00 };
const assets = @import("../assets/aseprite_import.zig");

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
var prev_note: ?u32 = null;
var ticks: u32 = 0;
var x_pos: f32 = 0;
var wave_slope: f32 = 1.0;
var wave_depth: f32 = 1.0;
var wave_current_index: u16 = 0;
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
var seed: f32 = 12490813.0;
var note_index: u32 = 0;
var speed_average: [60]f32 = undefined;
var prev_note_played: u32 = 0;

const NUM_WAVE_POINTS = SCREEN_WIDTH * TERRAIN_WIDTH;

var terrain: [NUM_WAVE_POINTS]f32 = undefined;

const Note = enum {
    Gl,
    C,
    D,
    E,
    F,
    G,
    A,
    B,

    fn to_freq(self: *const Note) u32 {
        return switch (self.*) {
            .Gl => 196,
            .C => 262,
            .D => 294,
            .E => 330,
            .F => 349,
            .G => 392,
            .A => 440,
            .B => 494,
        };
    }
};

// .E, null, .E, null, .F, null, .G, null, .G, null, .F, null, .E, null, .D, null,
// .C, null, .C, null. .D, null, .E, null, .E, null, .D, null, .D, null, null, null,
// .E, null, .E, null, .F, null, .G, null, .G, null, .F, null, .E, null, .D, null,
// .C, null, .C, null, .D, null, .E, null, .D, null, .C, null, .C, null, null, null,
// .D, null, .D, null, .E, null, .C, null, .D, null, .E, .F,   .E, null, .C, null,
// .D, null, .E, .F,   .E, null, .D, null, .C, null, .D, null, .Gl, null, null, null,
// .E, null, .E, null, .F, null, .G, null, .G, null, .F, null, .E, null, .D, null,
// .C, null, .C, null, .D, null, .E, null, .D, null, .C, null, .C, null, null, null,
const ode_to_joy: [128]?Note = [_]?Note{
    .E, null, .E, null, .F, null, .G, null, .G, null, .F,   null, .E,  null, .D,   null,
    .C, null, .C, null, .D, null, .E, null, .E, null, null, .D,   .D,  null, null, null,
    .E, null, .E, null, .F, null, .G, null, .G, null, .F,   null, .E,  null, .D,   null,
    .C, null, .C, null, .D, null, .E, null, .D, null, null, .C,   .C,  null, null, null,
    .D, null, .D, null, .E, null, .C, null, .D, null, .E,   .F,   .E,  null, .C,   null,
    .D, null, .E, .F,   .E, null, .D, null, .C, null, .D,   null, .Gl, null, .E,   null,
    .E, null, .E, null, .F, null, .G, null, .G, null, .F,   null, .E,  null, .D,   null,
    .C, null, .C, null, .D, null, .E, null, .D, null, null, .C,   .C,  null, null, null,
};

export fn start() void {
    update_terrain();
    w4.PALETTE.* = .{
        0x555577,
        0x777799,
        0x9999bb,
        0xbbbbdd,
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

    const terrain_height = terrain_height_at(@floatToInt(u16, x_pos) + @intCast(u16, player_pos.xi())) - PLAYER_RADIUS;
    if (@floatToInt(i32, player_pos.y) > terrain_height) {
        ground_contact = true;
        player_pos.y = @intToFloat(f32, terrain_height);
    }
    if (@floatToInt(i32, player_pos.y) < 0) player_pos.y = @intToFloat(f32, 0);
    const terrain_height_next = terrain_height_at(@floatToInt(u16, x_pos + 1) + @intCast(u16, player_pos.xi())) - PLAYER_RADIUS;
    slope_dir = if (terrain_height_next > terrain_height) TerrainDirection.down else TerrainDirection.up;

    // if player just hit ground, as is on up slope, then they need to slow down their xvel
    if ((ticks - prev_slow > 60) and (ticks - prev_released > 20) and !prev_ground and ground_contact and slope_dir == .up) {
        player_vel.x *= 0.7;
        player_vel.x = clamp(player_vel.x, PLAYER_MIN_X_SPEED, 2.0);
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
                const terrain_height_prev = terrain_height_at(@floatToInt(u16, x_pos - 5 * player_vel.x) + @intCast(u16, player_pos.xi())) - PLAYER_RADIUS;
                if (terrain_height_prev > terrain_height) player_vel.x -= 0.06;
            },
        }
    } else if (ground_contact) {
        // if we are on up slope
        // player y should be updated according to their x speed.
        // what if we are on down slope?
        switch (slope_dir) {
            .up => {
                const terrain_height_prev = terrain_height_at(@floatToInt(u16, x_pos - player_vel.x) + @intCast(u16, player_pos.xi())) - PLAYER_RADIUS;
                const y_diff = terrain_height - terrain_height_prev;
                player_vel.y = @intToFloat(f32, y_diff);
                if (ticks - prev_released < 20) player_vel.y *= 1.2;
                player_vel.y = clamp(player_vel.y, -player_vel.x * 2, -player_vel.x * 0.5);
            },
            .down => {
                if (button_released) {
                    player_vel.x = clamp(player_vel.x, button_down_x_vel, 2 * button_down_x_vel);
                    // convert yvel into xvel
                    // player_vel.x = player_vel.y;
                    // player_vel.x = std.math.clamp(player_vel.x, 0.4, 3.5);
                }
            },
        }
    } else {}
    player_vel.x = clamp(player_vel.x, PLAYER_MIN_X_SPEED, PLAYER_MAX_X_SPEED);
    player_vel.y += 0.11;
    if (ground_contact and !prev_ground and slope_dir == .up) player_vel.y *= 0.8;
    if (prev_slow == ticks and player_vel.y < -PLAYER_MIN_X_SPEED)
        player_vel.y = -PLAYER_MIN_X_SPEED;

    update_terrain();
    w4.DRAW_COLORS.* = 0x33;
    w4.rect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);
    {
        var i: u16 = 0;
        while (i < SCREEN_WIDTH) : (i += 1) {
            const terrain_index = (i + @floatToInt(u16, x_pos));
            const y = terrain_height_at(terrain_index);
            w4.DRAW_COLORS.* = 0x22;
            w4.vline(@intCast(i32, i), y, SCREEN_HEIGHT);
        }
    }
    if (@intToFloat(f32, terrain_height) - player_pos.y < PLAYER_RADIUS * 1.5) {
        w4.DRAW_COLORS.* = 0x11;
    } else {
        w4.DRAW_COLORS.* = 0x10;
    }
    w4.oval(player_pos.xi() - PLAYER_RADIUS, player_pos.yi() - PLAYER_RADIUS, PLAYER_RADIUS * 2, PLAYER_RADIUS * 2);
    w4.DRAW_COLORS.* = 0x2013;
    w4.blit(bunny[0..], 10, 10, bunny_width, bunny_height, bunny_flags);
    if (prev_slow == ticks) {
        w4.DRAW_COLORS.* = 0x44;
        w4.oval(player_pos.xi() - 2, player_pos.yi() - 2, 4, 4);
        w4.tone(100, 5 | (20 << 8), music_volume(), w4.TONE_NOISE);
    }
    speed_average[ticks % speed_average.len] = player_vel.x;
    handle_music();
    prev_gamepad = w4.GAMEPAD1.*;
    ticks += 1;
    x_pos += player_vel.x;
    player_vel.x -= 0.001;
    prev_ground = ground_contact;
}

fn handle_music() void {
    const avg = avg_speed();
    const interval = @floatToInt(i32, map(PLAYER_MIN_X_SPEED, PLAYER_MAX_X_SPEED, 24, 6, avg));
    if (ticks - prev_note_played >= interval) {
        prev_note_played = ticks;
        const note = get_note();
        if (note) |freq| {
            const volume = music_volume();
            w4.tone(freq / 2, 6 | (12 << 8), 1 + (volume / 10), w4.TONE_PULSE1);
            w4.tone(freq, 12 | (12 << 8), 1 + (volume / 10), w4.TONE_PULSE2);
            if (music_volume() > 50) {
                const vol2 = @floatToInt(u32, map(50, 80, 0, 60, @intToFloat(f32, volume)));
                w4.tone(freq, 6 | (60 << 8), vol2, w4.TONE_TRIANGLE);
            }
        }
        prev_note = note;
    }
}

fn get_note() ?u32 {
    note_index += 1;
    note_index = note_index % ode_to_joy[0..].len;
    if (ode_to_joy[note_index]) |n| return n.to_freq();
    return null;
}

fn avg_speed() f32 {
    const num = min(speed_average.len, ticks);
    if (num == 0) return PLAYER_MIN_X_SPEED;
    var avg: f32 = 0.0;
    var i: u8 = 0;
    while (i < num) : (i += 1) avg += speed_average[i];
    avg /= @intToFloat(f32, num);
    return avg;
}

fn music_volume() u32 {
    if (false) return 50;
    const avg = avg_speed();
    if (avg < 1.3) return 10;
    return @floatToInt(u32, map(1.3, PLAYER_MAX_X_SPEED, 10, 80, avg));
}

fn update_terrain() void {
    const current_terrain_section: u16 = @floatToInt(u16, x_pos) / SCREEN_WIDTH;
    const terrain_section_to_be_generated = (current_terrain_section + 1) % TERRAIN_WIDTH;
    if (ticks != 0) {
        if (terrain_section_to_be_generated == prev_terrain_section_generated) return;
    } else {
        gen_terrain(0);
    }
    gen_terrain(terrain_section_to_be_generated);
}

fn gen_terrain(terrain_section_to_be_generated: u16) void {
    prev_terrain_section_generated = @intCast(u8, terrain_section_to_be_generated);
    const start_i: u16 = terrain_section_to_be_generated * SCREEN_WIDTH;
    var prev_val = get_current_terrain_height();
    var i: u16 = start_i;
    while (i < start_i + SCREEN_WIDTH) : (i += 1) {
        terrain[i] = get_current_terrain_height();
        defer prev_val = terrain[i];
        defer terrain_current_index += 0.3 * terrain_width_scale;
        const change = terrain[i] - prev_val;
        if (terrain_direction.needs_change(change)) {
            switch (terrain_direction) {
                .up => {
                    terrain_max = map(0, 1, TERRAIN_MAX_MIN, TERRAIN_MAX_MAX, random_float());
                },
                .down => {
                    terrain_min = map(0, 1, TERRAIN_MIN_MIN, TERRAIN_MIN_MAX, random_float());
                },
            }
            terrain_width_scale = map(0, 1, TERRAIN_WIDTH_MIN, TERRAIN_WIDTH_MAX, random_float());
            terrain_direction = terrain_direction.toggle();
        }
    }
    wave_current_index += SCREEN_WIDTH;
}

fn get_current_terrain_height() f32 {
    return -map(-1, 1, terrain_min, terrain_max, std.math.cos(terrain_current_index / pi));
}

fn map(start_in: f32, end_in: f32, start_out: f32, end_out: f32, val: f32) f32 {
    assert(start_in != end_in);
    assert(start_out != end_out);
    const t = (val - start_in) / (end_in - start_in);
    return (start_out * (1.0 - t)) + (end_out * t);
}

fn terrain_height_at(terrain_index: u16) i32 {
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

fn assert(condition: bool) void {
    if (!condition) unreachable;
}

fn clamp(val: anytype, lower: anytype, upper: anytype) @TypeOf(val, lower, upper) {
    assert(lower <= upper);
    return max(lower, min(val, upper));
}
fn max(x: anytype, y: anytype) @TypeOf(x, y) {
    return if (x > y) x else y;
}
fn min(x: anytype, y: anytype) @TypeOf(x, y) {
    return if (x < y) x else y;
}

// random number between 0 and 1. https://stackoverflow.com/a/9492699
// std.rand makes the final size too large.
fn random_float() f32 {
    const a: f32 = 16807;
    const m: f32 = 2147483647;
    seed = @mod((a * seed), m);
    const random = seed / m;
    // const p = std.fmt.bufPrint(buffer[0..], "{d}", .{random}) catch unreachable;
    // w4.trace(p);
    return random;
}
