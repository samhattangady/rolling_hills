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
const PLAYER_WIDTH = 14;
const PLAYER_HEIGHT = 14;
const BLIT_FLAG = 1; // BLIT_2BPP
const player_sprites = @import("player_sprites.zig").player_sprites;
const title_sprites = @import("title_sprites.zig").title_sprites;
const title_sprites_bounds = @import("title_sprites.zig").sprite_bounds;
const moon_sprites = @import("moon_sprites.zig");
const GAME_TICKS = 3600 + 240;

// main offset of all the moon sprites
const moon_pos = [_]u8{
    86,
    0,
};

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

const Trail = struct {
    y: i8,
    val: u8,
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
var player_vel: Vec2 = .{ .x = 1, .y = 0 };
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
var trails: [30]Trail = undefined;
var prev_trail_update: u32 = 0;
var mode: Mode = .menu;
var dist: [6]u8 = undefined;
var stars: [8]Star = undefined;

const NUM_WAVE_POINTS = SCREEN_WIDTH * TERRAIN_WIDTH;

var terrain: [NUM_WAVE_POINTS]f32 = undefined;

const Mode = enum {
    menu,
    intro,
    game,
    end,
    post_end,
};

const Note = enum {
    Gl,
    C,
    D,
    E,
    F,
    G,
    A,
    B,
    Ch,

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
            .Ch => 524,
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

const final: [5]Note = [_]Note{ .C, .E, .G, .B, .Ch };

export fn start() void {
    update_terrain();
    w4.PALETTE.* = .{
        0x555599,
        0x7777bb,
        0x9999dd,
        0xddddff,
    };
    mode = .menu;
    stars[0] = Star{ .x = @floatToInt(i32, map(0, 1, 0, 50, random_float())), .y = @floatToInt(i32, map(0, 1, 0, 90, random_float())), .beat = @floatToInt(u8, map(0, 1, 30, 54, random_float())) };
    stars[1] = Star{ .x = @floatToInt(i32, map(0, 1, 0, 50, random_float())), .y = @floatToInt(i32, map(0, 1, 0, 90, random_float())), .beat = @floatToInt(u8, map(0, 1, 30, 54, random_float())) };
    stars[2] = Star{ .x = @floatToInt(i32, map(0, 1, 50, 100, random_float())), .y = @floatToInt(i32, map(0, 1, 0, 90, random_float())), .beat = @floatToInt(u8, map(0, 1, 30, 54, random_float())) };
    stars[3] = Star{ .x = @floatToInt(i32, map(0, 1, 50, 100, random_float())), .y = @floatToInt(i32, map(0, 1, 0, 90, random_float())), .beat = @floatToInt(u8, map(0, 1, 30, 54, random_float())) };
    stars[4] = Star{ .x = @floatToInt(i32, map(0, 1, 50, 100, random_float())), .y = @floatToInt(i32, map(0, 1, 0, 90, random_float())), .beat = @floatToInt(u8, map(0, 1, 30, 54, random_float())) };
    stars[5] = Star{ .x = @floatToInt(i32, map(0, 1, 50, 100, random_float())), .y = @floatToInt(i32, map(0, 1, 0, 90, random_float())), .beat = @floatToInt(u8, map(0, 1, 30, 54, random_float())) };
    stars[6] = Star{ .x = @floatToInt(i32, map(0, 1, 100, 160, random_float())), .y = @floatToInt(i32, map(0, 1, 0, 90, random_float())), .beat = @floatToInt(u8, map(0, 1, 30, 54, random_float())) };
    stars[7] = Star{ .x = @floatToInt(i32, map(0, 1, 100, 160, random_float())), .y = @floatToInt(i32, map(0, 1, 0, 90, random_float())), .beat = @floatToInt(u8, map(0, 1, 30, 54, random_float())) };
}

export fn update() void {
    switch (mode) {
        .menu => menu_update(),
        .intro => intro_update(),
        .game => game_update(),
        .end => end_update(),
        .post_end => game_update(),
    }
}

fn menu_update() void {
    draw_background();
    w4.DRAW_COLORS.* = 0x4130;
    var i: u8 = 0;
    while (i < title_sprites.len) : (i += 1) {
        const sprite = title_sprites[i];
        const bound = title_sprites_bounds[i];
        w4.blit(sprite[0..].ptr, bound[0], bound[1], bound[2], bound[3], BLIT_FLAG);
    }
    w4.DRAW_COLORS.* = 0x01;
    if (ticks % 48 > 24) w4.text("Press X", 80, 142);
    if (ticks % 24 == 0) {
        const note = get_note_reverse();
        if (note) |freq| {
            w4.tone(freq / 2, 6 | (12 << 8), 3, w4.TONE_PULSE1);
            w4.tone(freq, 12 | (12 << 8), 3, w4.TONE_PULSE2);
            w4.tone(freq, 6 | (60 << 8), 10, w4.TONE_TRIANGLE);
        }
    }
    ticks += 1;
    const gamepad = w4.GAMEPAD1.*;
    const pressed_this_frame = gamepad & (gamepad ^ prev_gamepad);
    _ = gamepad & pressed_this_frame;
    const button_down = gamepad & w4.BUTTON_1 != 0;
    if (button_down) {
        ticks = 0;
        mode = .intro;
        note_index = 0;
    }
}

fn intro_update() void {
    draw_background();
    const offset = @floatToInt(u8, map(0, 240, 80, 0, @intToFloat(f32, ticks)));
    draw_hills(offset);
    const y_offset = @floatToInt(i32, map(0, 240, 0, 500, @intToFloat(f32, ticks)));
    w4.DRAW_COLORS.* = 0x4130;
    var i: u8 = 0;
    while (i < title_sprites.len - 1) : (i += 1) {
        const sprite = title_sprites[i];
        const bound = title_sprites_bounds[i];
        w4.blit(sprite[0..].ptr, bound[0], bound[1] - y_offset, bound[2], bound[3], BLIT_FLAG);
    }
    const text_offset = @floatToInt(i32, map(0, 100, 50, 0, @intToFloat(f32, std.math.min(100, ticks))));
    w4.DRAW_COLORS.* = 0x01;
    w4.text("Hold X to dive", 23, 132);
    w4.text("Release X to soar", 13, 142);
    w4.DRAW_COLORS.* = 0x04;
    w4.text("The moon", 43, 20 + text_offset);
    w4.text("calls for you", 25, 30 + text_offset);
    w4.DRAW_COLORS.* = 0x0310;
    const sprite = player_sprites[1][0..].ptr;
    const x = @floatToInt(i32, map(0, 240, -120, 30, @intToFloat(f32, ticks)));
    w4.blit(sprite, x - PLAYER_RADIUS, player_pos.yi() - PLAYER_RADIUS, PLAYER_WIDTH, PLAYER_HEIGHT, BLIT_FLAG);
    ticks += 1;
    if (ticks == 240) {
        w4.tone(660, 6 | (100 << 8), 30, w4.TONE_TRIANGLE);
        mode = .game;
        // ticks = 0;
        return;
    }
    if (ticks % 60 == 0) w4.tone(330, 6 | (60 << 8), 10, w4.TONE_TRIANGLE);
}

fn end_update() void {
    draw_background();
    draw_hills(0);
    if (ticks < GAME_TICKS + 300) {
        if ((ticks - GAME_TICKS) % 60 == 10 and note_index < final.len) {
            w4.tone(final[note_index].to_freq(), 6 | (100 << 8), 30, w4.TONE_TRIANGLE);
            note_index += 1;
        }
    } else {
        if ((ticks - GAME_TICKS) % 8 == 4 and note_index < final.len) {
            w4.tone(final[note_index].to_freq(), 6 | (100 << 8), 30, w4.TONE_TRIANGLE);
            note_index += 1;
        }
    }
    ticks += 1;
    var num: u8 = 0;
    w4.DRAW_COLORS.* = 0x04;
    if ((ticks - GAME_TICKS) > 10) w4.text("the", 16, 20);
    if ((ticks - GAME_TICKS) > 70) w4.text("moon", 48, 20);
    if ((ticks - GAME_TICKS) > 130) w4.text("called", 88, 20);
    if ((ticks - GAME_TICKS) > 190) w4.text("you", 30, 30);
    if ((ticks - GAME_TICKS) > 250) w4.text("answered", 62, 30);
    if (ticks > GAME_TICKS + 300) {
        if ((ticks - GAME_TICKS - 300) > 4) num = 1;
        if ((ticks - GAME_TICKS - 300) > 12) num = 2;
        if ((ticks - GAME_TICKS - 300) > 20) num = 3;
        if ((ticks - GAME_TICKS - 300) > 28) num = 4;
        if ((ticks - GAME_TICKS - 300) > 36) num = 5;
    }
    calculate_dist(num);

    w4.DRAW_COLORS.* = 0x01;
    w4.text("Distance:", 15, 100);
    w4.text(dist[0..], 90, 100);

    draw_player_trails();
    w4.DRAW_COLORS.* = 0x0310;
    const sprite = player_sprites[1][0..].ptr;
    w4.blit(sprite, player_pos.xi() - PLAYER_RADIUS, player_pos.yi() - PLAYER_RADIUS, PLAYER_WIDTH, PLAYER_HEIGHT, BLIT_FLAG);
    if (ticks == GAME_TICKS + 300) {
        note_index = 0;
    }

    if (ticks > GAME_TICKS + 300) {
        w4.DRAW_COLORS.* = 0x04;
        w4.blit(&smiley, 76, 70, 8, 8, w4.BLIT_1BPP);
        w4.DRAW_COLORS.* = 0x02;
        w4.text("Press X to continue", 6, 137);
        w4.text("Press R to restart", 10, 147);
        const gamepad = w4.GAMEPAD1.*;
        const pressed_this_frame = gamepad & (gamepad ^ prev_gamepad);
        _ = gamepad & pressed_this_frame;
        const button_down = gamepad & w4.BUTTON_1 != 0;
        if (button_down) {
            mode = .post_end;
        }
    }
}

fn game_update() void {
    var ground_contact: bool = false;
    var slope_dir: TerrainDirection = .up;

    const gamepad = w4.GAMEPAD1.*;
    const pressed_this_frame = gamepad & (gamepad ^ prev_gamepad);
    _ = gamepad & pressed_this_frame;
    const button_down = gamepad & w4.BUTTON_1 != 0;
    const button_released = (prev_gamepad & w4.BUTTON_1 != 0) and (!button_down);
    const button_pressed = (prev_gamepad & w4.BUTTON_1 == 0) and (button_down);
    if (button_released) prev_released = ticks;

    if (mode == .game and ticks > GAME_TICKS) {
        mode = .end;
        note_index = 0;
        boost_player_trails();
    }

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
                if (ticks - prev_released < 20) player_vel.y *= max(player_vel.x / 2.0, 1.2);
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
    draw_background();
    draw_hills(0);
    if (ticks < 600) {
        w4.DRAW_COLORS.* = 0x02;
        w4.text("Hold X to dive", 23, 132);
        w4.text("Release X to soar", 13, 142);
    }
    if (mode == .game) draw_timer();
    update_player_trails();
    draw_player_trails();
    if (ticks - prev_slow < 5) {
        w4.DRAW_COLORS.* = 0x0440;
    } else {
        w4.DRAW_COLORS.* = 0x0310;
    }
    const sprite = player_sprites[get_sprite_index(button_down, terrain_height)][0..].ptr;
    w4.blit(sprite, player_pos.xi() - PLAYER_RADIUS, player_pos.yi() - PLAYER_RADIUS, PLAYER_WIDTH, PLAYER_HEIGHT, BLIT_FLAG);
    speed_average[ticks % speed_average.len] = player_vel.x;
    if (prev_slow == ticks) w4.tone(100, 5 | (20 << 8), music_volume(), w4.TONE_NOISE);
    if (mode == .post_end) {
        calculate_dist(5);
        w4.DRAW_COLORS.* = 0x02;
        w4.text(dist[0..], 110, 150);
    }
    handle_music();
    prev_gamepad = w4.GAMEPAD1.*;
    ticks += 1;
    x_pos += player_vel.x;
    player_vel.x -= 0.001;
    prev_ground = ground_contact;
}

fn draw_background() void {
    w4.DRAW_COLORS.* = 0x22;
    w4.rect(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT);
    draw_moon();
    draw_stars();
}

fn draw_stars() void {
    w4.DRAW_COLORS.* = 0x33;
    for (stars) |star| {
        if ((ticks + 50) % star.beat > 3) {
            w4.hline(star.x - 1, star.y, 3);
            w4.vline(star.x, star.y - 1, 3);
        }
    }
}

fn draw_moon() void {
    w4.DRAW_COLORS.* = 0x4130;
    {
        const sprite = moon_sprites.moon_sprites[0];
        const bound = moon_sprites.moon_bounds[0];
        w4.blit(sprite[0..].ptr, moon_pos[0] + bound[0], moon_pos[1] + bound[1], bound[2], bound[3], BLIT_FLAG);
    }
    // 0 is neutral, 1 is very happy, 2 is crash
    var mood_index: usize = 0;
    switch (mode) {
        .game, .post_end => {
            if (ticks - prev_slow < 50) {
                mood_index = 2;
            } else if (music_volume() > 40) {
                mood_index = 1;
            }
        },
        .end => mood_index = 1,
        else => {},
    }
    {
        const sprite = moon_sprites.moon_mood_sprites[mood_index];
        const bound = moon_sprites.moon_mood_bounds[mood_index];
        w4.blit(sprite[0..].ptr, moon_pos[0] + bound[0], moon_pos[1] + bound[1], bound[2], bound[3], BLIT_FLAG);
    }
    // no eyeballs when crash
    if (mood_index == 2) return;
    // 0 is low, 1 is mid, 2 is high
    var eyeball_index: usize = 0;
    switch (mode) {
        .intro => eyeball_index = 2,
        .game, .post_end, .end => {
            if (player_pos.y < 50) {
                eyeball_index = 2;
            } else if (player_pos.y < 100) {
                eyeball_index = 1;
            }
        },
        else => {},
    }
    {
        const sprite = moon_sprites.moon_eyeball_sprites[eyeball_index];
        const bound = moon_sprites.moon_eyeball_bounds[eyeball_index];
        w4.blit(sprite[0..].ptr, moon_pos[0] + bound[0], moon_pos[1] + bound[1], bound[2], bound[3], BLIT_FLAG);
    }
}

fn draw_timer() void {
    w4.DRAW_COLORS.* = 0x10;
    w4.rect(20, 5, 122, 4);
    var width: u32 = 0;
    if (ticks < GAME_TICKS) {
        const pct = (GAME_TICKS - @intToFloat(f32, ticks)) / GAME_TICKS;
        width = @floatToInt(u32, pct * 120);
    }
    w4.DRAW_COLORS.* = 0x33;
    if (width < 30 and ticks % 60 < 30) w4.DRAW_COLORS.* = 0x44;
    w4.rect(21, 6, width, 2);
}

fn draw_hills(offset: u8) void {
    var i: u16 = 0;
    while (i < SCREEN_WIDTH) : (i += 1) {
        const terrain_index = (i + @floatToInt(u16, x_pos));
        const y = terrain_height_at(terrain_index) + offset;
        w4.DRAW_COLORS.* = 0x33;
        w4.vline(@intCast(i32, i), y, SCREEN_HEIGHT);
        if (terrain_index % SCREEN_WIDTH == 7) {
            // draw far street lamp
            w4.DRAW_COLORS.* = 0x33;
            w4.vline(@intCast(i32, i), y - 15, 25);
            w4.vline(@intCast(i32, i) + 1, y - 15, 25);
            w4.DRAW_COLORS.* = 0x44;
            w4.hline(@intCast(i32, i) + 1, y - 15, 3);
            w4.DRAW_COLORS.* = 0x33;
            w4.hline(@intCast(i32, i), y - 16, 4);
        }
    }
    if (mode == .end) return;
    i = 0;
    while (i < SCREEN_WIDTH) : (i += 1) {
        // draw foreground street lamp
        const terrain_index2 = (i + @floatToInt(u16, 1.8 * x_pos));
        if (terrain_index2 % (SCREEN_WIDTH * 3) == (SCREEN_WIDTH + 25)) {
            // TODO (20 Jan 2022 sam): Import the sprite here instead?
            w4.DRAW_COLORS.* = 0x11;
            w4.rect(@intCast(i32, i), 97, 5, 63);
            w4.hline(@intCast(i32, i), 96, 12);
            w4.hline(@intCast(i32, i), 95, 13);
            w4.hline(@intCast(i32, i), 94, 13);
            w4.hline(@intCast(i32, i), 93, 13);
            w4.hline(@intCast(i32, i) + 1, 92, 11);
            w4.hline(@intCast(i32, i) + 3, 91, 7);
            w4.DRAW_COLORS.* = 0x44;
            w4.hline(@intCast(i32, i) + 3, 96, 8);
            w4.hline(@intCast(i32, i) + 4, 95, 6);
        }
    }
}

fn update_player_trails() void {
    if (@floatToInt(u32, x_pos) == prev_trail_update) return;
    const shift = @floatToInt(u32, x_pos) - prev_trail_update;
    prev_trail_update = @floatToInt(u32, x_pos);
    assert(shift != 0);
    var i: u8 = 0;
    while (i < trails.len - shift) : (i += 1) {
        trails[i] = trails[i + shift];
        // taper the trail as it leaves the screen
        trails[i].val = min(trails[i].val, i / 2);
    }
    const prev_y = trails[i - 1].y;
    const amount = min(1.0, @intToFloat(f32, music_volume2()) / 40.0);
    while (i < trails.len) : (i += 1) {
        // lerp from prev y.
        const fract = 1.0 - (@intToFloat(f32, trails.len - i) / @intToFloat(f32, shift));
        const y: i8 = @floatToInt(i8, lerp(@intToFloat(f32, prev_y), player_pos.y, fract));
        trails[i] = Trail{ .y = y, .val = @floatToInt(u8, map(0, 1, 0, 12, amount)) };
    }
}

fn boost_player_trails() void {
    for (trails) |*trail| {
        trail.val = 12;
    }
}

fn calculate_dist(num: u8) void {
    dist[5] = 'm';
    var xpos = @floatToInt(usize, x_pos);
    var i: usize = 4;
    while (true) : (i -= 1) {
        dist[i] = @intCast(u8, xpos % 10) + 48;
        xpos = xpos / 10;
        if (i == 0) break;
    }
    i = 0;
    while (i < 5) : (i += 1) {
        if (i >= num) dist[i] = ' ';
    }
}

fn draw_player_trails() void {
    w4.DRAW_COLORS.* = 0x4444;
    for (trails) |trail, x| {
        // taper the trail
        const val = if (trails.len - x < 3) min(trail.val, (trails.len - x) * 5) else trail.val;
        const y = trail.y - @divFloor(@intCast(i8, val), 2);
        w4.vline(@intCast(i32, x), @intCast(i32, y), val);
    }
}

fn get_sprite_index(button_down: bool, terrain_height: i32) usize {
    // 0 - flat
    // 2 - 45 facing down (y_front - y_back = 3)
    // 4 - 45 facing up   (y_front - y_back = -3)
    // +0 if button is down
    // +1 if button is released
    var index: usize = 0;
    const terrain_height_back = terrain_height_at(@floatToInt(u16, x_pos) + @intCast(u16, player_pos.xi()) - 3) - PLAYER_RADIUS;
    const terrain_height_front = terrain_height_at(@floatToInt(u16, x_pos) + @intCast(u16, player_pos.xi()) + 3) - PLAYER_RADIUS;
    const ydiff = terrain_height_front - terrain_height_back;
    if (ydiff > 2) {
        index = 2;
    } else if (ydiff < -2) {
        index = 4;
    } else {
        index = 0;
    }
    // if in the air, use the velocity dir
    if (@intToFloat(f32, terrain_height) - player_pos.y > PLAYER_RADIUS) {
        if (player_vel.y > player_vel.x) {
            index = 2;
        } else if (-player_vel.y > player_vel.x) {
            index = 4;
        } else {
            index = 0;
        }
    }
    if (!button_down) index += 1;
    return index;
}

fn handle_music() void {
    const avg = avg_speed();
    const interval = @floatToInt(i32, map(PLAYER_MIN_X_SPEED, PLAYER_MAX_X_SPEED, 36, 6, avg));
    if (ticks - prev_note_played >= interval) {
        prev_note_played = ticks;
        const note = get_note();
        if (note) |freq| {
            const volume = music_volume();
            w4.tone(freq / 2, 6 | (12 << 8), 1 + (volume / 10), w4.TONE_PULSE1);
            w4.tone(freq, 12 | (12 << 8), 1 + (volume / 10), w4.TONE_PULSE2);
            w4.tone(freq, 6 | (60 << 8), music_volume2(), w4.TONE_TRIANGLE);
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

fn get_note_reverse() ?u32 {
    if (note_index == 0) {
        note_index = ode_to_joy[0..].len - 1;
    } else {
        note_index -= 1;
    }
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

fn music_volume2() u32 {
    if (false) return 60;
    const vol = music_volume();
    if (vol > 30) {
        const vol2 = @floatToInt(u32, map(30, 80, 0, 60, @intToFloat(f32, vol)));
        return vol2;
    } else {
        return 0;
    }
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

fn lerp(start_val: f32, end_val: f32, t: f32) f32 {
    return (start_val * (1.0 - t)) + (end_val * t);
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

const Star = struct {
    x: i32,
    y: i32,
    beat: u8,
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
