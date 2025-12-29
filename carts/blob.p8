pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- bouncing bloob
-- by praghus
------------------------------------------------------------------------------
cartdata("blob_best_times")

function _init()
    Game:init()
end

function _update()
    Game:update()
end

function _draw()
    Game:draw()
end

-- GRAPHICS -------------------------------------------------------------------
tile_sprite_map = { [1] = 32, [2] = 34, [3] = 36, [5] = 42 }
teleport1_bg_sprite = 40
teleport2_bg_sprite = 38
palette = {
    [0] = { 0, 1, 2, 1, 2, 8 },
    [1] = { 0, 1, 1, 1, 1, 13 },
    [2] = { 0, 1, 1, 1, 1, 12 },
    [3] = { 0, 1, 3, 1, 3, 11 },
    [4] = { 0, 1, 2, 1, 2, 14 }
}

tile_meta = {
    -- teleport / special tiles
    [7] = { debris = { 11, 3 }, anim_base = 96 }, -- up
    [8] = { debris = { 11, 3 }, anim_base = 64 }, -- right
    [9] = { debris = { 11, 3 }, anim_base = 112 }, -- down
    [10] = { debris = { 11, 3 }, anim_base = 80 }, -- left
    [11] = { debris = { 12, 1 }, anim_base = 86 }, -- up-right
    [12] = { debris = { 12, 1 }, anim_base = 70 }, -- down-right
    [13] = { debris = { 12, 1 }, anim_base = 118 }, -- down-left
    [14] = { debris = { 12, 1 }, anim_base = 102 } -- up-left
}

-->8
-- PLAYER
-------------------------------------------------------------------------------
Player = Player or {}
Player.__index = Player

function Player.new(x, y)
    local p = setmetatable(
        {
            grid_x = x, grid_y = y,
            old_x = x, old_y = y,
            moving = false, move_timer = 0,
            w = 4, offset_y = 0,
            bounce_timer = 0, fall_timer = 0,
            spawn_timer = 0, spawn_duration = 0.6,
            beam_frac = 0.15, beam_visible = 0.6,
            spawning = not (Game.level_transition or Game:is_showing_messages()),
            pending_spawn = (Game.level_transition or Game:is_showing_messages()),
            can_move = false, input_buffered = false, buffered_dir = 0,
            can_hit = true, prev_size = 4, reached_peak = false
        }, Player
    )
    return p
end

function Player:set_position(x, y)
    self.grid_x = x
    self.grid_y = y
    self.old_x = x
    self.old_y = y
end

function Player:start_spawn_at(x, y)
    self.spawning = true
    self.pending_spawn = false
    self.spawn_timer = 0
    self.spawn_flash = nil
    self.w = self.w or 4
    self.fall_timer = 0
    self.falling = false
    self:set_position(x, y)
    self:reset_flags()
end

function Player:reset_flags()
    self.moving = false
    self.falling = false
    self.move_timer = 0
    self.fall_timer = 0
    self.can_hit = true
    self.prev_size = 4
    self.reached_peak = false
    self.can_move = false
    self.input_buffered = false
    self.buffered_dir = 0
end

function Player:handle_input()
    if self.spawning or (self.spawn_flash and self.spawn_flash > 0) then
        self.input_buffered = false
        self.buffered_dir = 0
        return
    end

    if btn(0) then
        self.buffered_dir = 0
        self.input_buffered = true
    elseif btn(1) then
        self.buffered_dir = 1
        self.input_buffered = true
    elseif btn(2) then
        self.buffered_dir = 2
        self.input_buffered = true
    elseif btn(3) then
        self.buffered_dir = 3
        self.input_buffered = true
    else
        self.input_buffered = false
    end
end

function Player:update()
    self:update_spawn()

    if self.falling then
        self:update_falling()
    elseif self.moving then
        self:update_moving()
    else
        self:handle_input()
    end

    if is_player_visible(self) then
        self:update_bounce()
    end
end

function Player:update_falling()
    self.fall_timer += 0.08
    if self.fall_timer >= 1 then
        Game:set_state("lost")
        sfx(13)
    end
end

function Player:update_moving()
    local p = self
    p.move_timer += 0.08
    if p.move_timer >= 1 then
        p.moving = false
        p.move_timer = 0
        p.old_x = p.grid_x
        p.old_y = p.grid_y

        if p.grid_x < 0 or p.grid_x >= Map.width
                or p.grid_y < 0 or p.grid_y >= Map.height then
            if Game.immortal then
                p.grid_x = p.old_x
                p.grid_y = p.old_y
            else
                p.falling = true
                p.fall_timer = 0
            end
        else
            local tile = Map:get(p.grid_x, p.grid_y)
            if tile == 0 then
                if Game.immortal then
                    p.grid_x = p.old_x
                    p.grid_y = p.old_y
                else
                    p.falling = true
                    p.fall_timer = 0
                end
            else
                p.can_hit = true
                p.reached_peak = false
            end
        end
    end
end

function Player:update_bounce()
    local p = self

    if p.falling then
        local t = p.fall_timer
        local size = 8 * (1 - t) -- from 8 to 0
        p.w = max(1, size)
        p.offset_y = t * 8
        p.prev_bounce = 0
        p.can_move = false
        return
    end

    if not p.bounce_timer then
        p.bounce_timer = 0
    end

    -- stop bounce animation increment if falling
    if not p.falling then
        p.bounce_timer += 0.033
        if p.bounce_timer >= 1 then
            p.bounce_timer = 0
        end
    end

    local t = p.bounce_timer
    local bounce = sin(t * 0.5)

    -- detect jump peak for input (bounce near maximum)
    if not p.moving and not p.falling then
        -- jump peak: t from 0.2 to 0.3 (peak of sinusoid)
        if t > 0.2 and t < 0.3 and not p.can_move then
            p.can_move = true

            -- execute move if input is buffered
            if p.input_buffered then
                local nx, ny = p.grid_x, p.grid_y
                if p.buffered_dir == 0 then
                    nx = p.grid_x - 1
                elseif p.buffered_dir == 1 then
                    nx = p.grid_x + 1
                elseif p.buffered_dir == 2 then
                    ny = p.grid_y - 1
                elseif p.buffered_dir == 3 then
                    ny = p.grid_y + 1
                end
                -- start animated movement
                p.old_x = p.grid_x
                p.old_y = p.grid_y
                p.grid_x = nx
                p.grid_y = ny
                p.moving = true
                p.move_timer = 0
                p.can_move = false

                -- create trail from start to end position
                ParticleSystem:create_trail(p.old_x, p.old_y, nx, ny)
            end
        end

        -- reset can_move when t returns to 0 (prepare for next jump)
        if t < 0.1 or t > 0.9 then
            p.can_move = false
        end
    end

    p.prev_bounce = bounce

    -- ball size: small (4) to large (16) and back
    local min_size = 4
    local max_size = 16
    local zoom_factor = bounce * bounce
    p.w = min_size + (max_size - min_size) * zoom_factor

    -- detect moment of touching tile (smallest size) and hit tile
    if not p.moving and not p.falling then
        local prev_size = p.prev_size or min_size
        -- ball reached smallest size (tile touch)
        if prev_size > min_size and p.w <= min_size then
            if p.can_hit then
                local tile = Map:get(p.grid_x, p.grid_y)
                if tile == 0 then
                    if not Game.immortal then
                        -- empty tile - start falling
                        p.falling = true
                        p.fall_timer = 0
                    else
                        sfx(11)
                    end
                else
                    -- teleport tile - hit it and start teleport animation
                    if tile >= 7 and tile <= 14 then
                        sfx(11)
                        Map:hit_tile(p.grid_x, p.grid_y)
                        local nx2, ny2 = p.grid_x, p.grid_y
                        if tile == 10 then
                            nx2 = p.grid_x - 2 -- left (2 tiles)
                        elseif tile == 8 then
                            nx2 = p.grid_x + 2 -- right (2 tiles)
                        elseif tile == 9 then
                            ny2 = p.grid_y + 2 -- down (2 tiles)
                        elseif tile == 7 then
                            ny2 = p.grid_y - 2 -- up (2 tiles)
                        elseif tile == 14 then
                            nx2, ny2 = p.grid_x - 1, p.grid_y - 1 -- up-left (diag)
                        elseif tile == 11 then
                            nx2, ny2 = p.grid_x + 1, p.grid_y - 1 -- up-right (diag)
                        elseif tile == 13 then
                            nx2, ny2 = p.grid_x - 1, p.grid_y + 1 -- down-left (diag)
                        elseif tile == 12 then
                            nx2, ny2 = p.grid_x + 1, p.grid_y + 1 -- down-right (diag)
                        end

                        p.old_x = p.grid_x
                        p.old_y = p.grid_y
                        p.grid_x = nx2
                        p.grid_y = ny2
                        p.moving = true
                        p.move_timer = 0

                        ParticleSystem:create_trail(p.old_x, p.old_y, nx2, ny2)

                        -- block until next cycle and reset peak
                        p.can_hit = false
                        p.reached_peak = false
                    else
                        -- normal tile - hit it with bounce sound
                        sfx(11)
                        Map:hit_tile(p.grid_x, p.grid_y)
                        -- block until next cycle and reset peak
                        p.can_hit = false
                        p.reached_peak = false
                    end
                end
            else
                -- can't hit but still bouncing - play sound
                sfx(11)
            end
        end
        -- track if ball reached peak (large size > 14)
        if p.w > 14 and not p.can_hit and not p.reached_peak then
            p.reached_peak = true
        end
        -- allow hitting only when ball passed peak and returns down
        if p.reached_peak and p.w < 6 then
            p.can_hit = true
            p.reached_peak = false
        end

        p.prev_size = p.w
    end
    -- Y axis movement: ball always above tile
    -- in lower phase -2, in upper phase -10 (8px difference)
    p.offset_y = -1.5 - bounce * 5
end

function Player:update_spawn()
    local p = self

    -- if spawn was deferred until player is visible, start it now
    if p.pending_spawn and is_player_visible(p) then
        p.pending_spawn = false
        p.spawning = true
        p.spawn_timer = 0
        p.spawn_flash = nil
        p.input_buffered = false
        p.buffered_dir = 0
    end

    if p.spawning then
        p.spawn_timer = (p.spawn_timer or 0) + 1 / 30
    end

    local dur = p.spawn_duration or 0.6
    local prog = (p.spawn_timer or 0) / dur
    local beam_visible = p.beam_visible or ((p.beam_frac or 0.15) * dur)

    if p.spawning and prog >= 1 then
        p.spawning = false
        p.spawn_timer = dur
        p.spawn_flash = p.spawn_flash or 0.2
    end

    if p.spawn_flash and p.spawn_flash > 0 then
        p.spawn_flash -= 1 / 30
        if p.spawn_flash < 0 then p.spawn_flash = 0 end
    end
end

function Player:get_screen_pos()
    local center_x, center_y = 7, 11
    local render_x, render_y
    if self.falling then
        render_x = self.grid_x
        render_y = self.grid_y
    elseif self.moving then
        local t = self.move_timer
        local ease_t = 1 - (1 - t) * (1 - t)
        render_x = self.old_x + (self.grid_x - self.old_x) * ease_t
        render_y = self.old_y + (self.grid_y - self.old_y) * ease_t
    else
        render_x = self.grid_x
        render_y = self.grid_y
    end

    local px = render_x * Map.tile_size + center_x
    local py = render_y * Map.tile_size + center_y
    return px, py, render_x, render_y, center_x, center_y
end

function Player:draw()
    local p = self
    local px, py = p:get_screen_pos()
    local s = ball_render_size(p)
    local ball_y = py + (p.offset_y or 0) - s / 2
    local spawning_active = p and (p.spawning or (p.spawn_flash and p.spawn_flash > 0))
    local spawn_prog = 1

    if not p.falling then
        local tile = Map:get(p.grid_x, p.grid_y)
        if tile ~= 0 and (p.w or 0) <= 7 then
            circfill(p.grid_x * Map.tile_size + 7, p.grid_y * Map.tile_size + 11, 4, 5)
        end
    end

    if spawning_active then
        local spawn_timer = p.spawn_timer or 0
        local dur = p.spawn_duration or 0.6
        spawn_prog = mid(0, spawn_timer / dur, 1)

        local beam_visible = p.beam_visible or ((p.beam_frac or 0.3) * dur)
        local show_beam = spawn_timer < beam_visible or (p.spawn_flash and p.spawn_flash > 0)
        local light_r_max = 40
        local light_r = light_r_max * (1 - spawn_prog)
        if light_r > 1 then
            local lr1 = flr(light_r)
            circfill(px, py, lr1, 14)
            circfill(px, py, flr(lr1 * 0.6), 7)
            circfill(px, py, flr(lr1 * 0.3), 7)
        end

        if show_beam then
            rectfill(px - 4, 0, px + 4, py, 14)
            rectfill(px - 2, 0, px + 2, py, 7)
        end

        circfill(px, py - 1, 2 + spawn_prog * 2, 7)

        if p.spawn_flash and p.spawn_flash > 0 then
            local flash_dur = p.spawn_flash_dur or 0.12
            local fprog = p.spawn_flash / flash_dur
            if fprog > 0 then
                local flash_r = 28 * fprog
                local inner_r = max(1, flr(flash_r * 0.55))
                circfill(px, py, inner_r, 7)
                circ(px, py, flr(flash_r), 15)
                for i = 1, 4 do
                    local sx = px + rnd(flash_r) - flash_r / 2
                    local sy = py + rnd(flash_r) - flash_r / 2
                    circfill(sx, sy, rnd(1.2), 14)
                end
            end
        end
    end

    local s_draw = s * spawn_prog
    if s_draw > 0.5 then
        draw_ball(px, ball_y, s_draw)
    end
end

function draw_ball(px, ball_y, s)
    local highlight_size = max(1.5, s * 0.45)
    local highlight_offset = s * 0.35

    circfill(px, ball_y, s + 1, 0)
    circfill(px, ball_y, s, 8)
    circfill(px + 1, ball_y + s * 0.25, s * 0.7, 2)
    circfill(px + 1 - s * 0.1, ball_y - s * 0.1, s * 0.7, 14)
    circfill(px - highlight_offset, ball_y - highlight_offset, highlight_size, 7)

    if s > 2 then
        circfill(px - highlight_offset * 1.1, ball_y - highlight_offset * 1.1, highlight_size * 0.6, 7)
    end

    if s > 2.5 then
        local sparkle_size = max(0.5, s * 0.15)
        circfill(px - s * 0.5, ball_y - s * 0.5, sparkle_size, 7)
        pset(px - s * 0.5, ball_y - s * 0.5, 7)
    end
end

-->8
-- MAP
-------------------------------------------------------------------------------
Map = {
    current_map = nil,
    width = 8,
    height = 8,
    tile_size = 16,
    start_x = 0,
    start_y = 0,
    old_map = {},
    tiles_left = 0,
    total_tiles = 0
}

function Map:get(x, y)
    if x < 0 or x >= self.width or y < 0 or y >= self.height then return 0 end
    local idx = y * self.width + x + 1
    return self.current_map[idx]
end

function Map:set(x, y, v)
    if x >= 0 and x < self.width and y >= 0 and y < self.height then
        local idx = y * self.width + x + 1
        self.current_map[idx] = v
    end
end

function Map:count_tiles()
    --@todo: optimize tile counting (use lookup table or a small helper to test destructible/teleport ranges)
    local count = 0
    for i = 1, self.width * self.height do
        local v = self.current_map[i]
        if v == 1 or v == 2 or v == 3 or (v >= 7 and v <= 14) then
            count += 1
        end
    end
    return count
end

function Map:reset(skip_respawn)
    local old_current_map = {}
    if self.current_map then
        for i = 1, self.width * self.height do
            old_current_map[i] = self.current_map[i]
        end
    end

    self.current_map = {}
    for i = 1, self.width * self.height do
        self.current_map[i] = 0
    end
    self.start_x = 0
    self.start_y = 0
    for i = 1, self.width * self.height do
        local v = Game.levels[Game.current_level][i]
        if v == 4 then
            local idx0 = i - 1
            self.start_x = idx0 % self.width
            self.start_y = flr(idx0 / self.width)
            v = 5
        end
        self.current_map[i] = v
    end

    if old_current_map and #old_current_map > 0 and not skip_respawn then
        UIManager:setup_tile_respawn_animations(old_current_map)
    end

    self.tiles_left = self:count_tiles()
    self.total_tiles = self.tiles_left
end

function Map:load_levels_from_native_map()
    -- number of blocks that fit horizontally and vertically
    local blocks_x = flr(128 / self.width)
    local blocks_y = flr(32 / self.height)

    for by = 0, blocks_y - 1 do
        for bx = 0, blocks_x - 1 do
            local ox = bx * self.width
            local oy = by * self.height
            local lvl = {}
            local is_empty = true
            for y = 0, self.height - 1 do
                for x = 0, self.width - 1 do
                    local v = mget(ox + x, oy + y)
                    add(lvl, v)
                    if v ~= 0 then is_empty = false end
                end
            end
            -- only add non-empty maps so empty slots in __map__ are ignored
            if not is_empty then
                add(Game.levels, lvl)
            end
        end
    end
    Game:load_best_times()
end

-->8
-- CAMERA
-------------------------------------------------------------------------------
Camera = {
    x = 0,
    y = 0,
    shake_timer = 0,
    shake_intensity = 0
}

function Camera:reset()
    self.x, self.y = 0, 0
end

function Camera:center(offset_y)
    self.x = damp(0, self.x, 0.2)
    self.y = damp(offset_y or 0, self.y, 0.2)
    if abs(self.x) < 0.25 then self.x = 0 end
    if abs(self.y) < 0.25 then self.y = 0 end
end

function Camera:trigger_shake()
    self.shake_timer = 6
    self.shake_intensity = 2
end

function Camera:update_shake()
    if self.shake_timer > 0 then
        self.shake_timer -= 1
    end
end

function Camera:get_shake()
    if self.shake_timer > 0 then
        local sx = rnd(self.shake_intensity) - self.shake_intensity / 2
        local sy = rnd(self.shake_intensity) - self.shake_intensity / 2
        return sx, sy
    end
    return 0, 0
end

function Camera:update()
    local target_x = self.x
    local target_y = self.y

    if not Game.level_transition and Game.player then
        local on_left = (Game.player.grid_x == 0)
        local on_right = (Game.player.grid_x == Map.width - 1)
        local on_top = (Game.player.grid_y == 0)
        local on_bottom = (Game.player.grid_y == Map.height - 1)

        if on_left or on_right or on_top or on_bottom then
            local px, py = tile_to_px(Game.player.grid_x, Game.player.grid_y)
            local left_margin = 24
            local right_margin = 128 - 24
            local top_margin = 24
            local bottom_margin = 128 - 24

            if on_left then
                target_x = px - left_margin
            elseif on_right then
                target_x = px - right_margin
            end

            if on_top then
                target_y = py - top_margin
            elseif on_bottom then
                target_y = py - bottom_margin
            end

            local max_nudge = 48
            target_x = clamp(target_x, -max_nudge, max_nudge)
            target_y = clamp(target_y, -max_nudge, max_nudge)
        else
            target_x = 0
            target_y = 0
        end
    else
        target_x = 0
        target_y = 0
    end

    local follow_speed = 0.08
    self.x = damp(target_x, self.x, follow_speed)
    self.y = damp(target_y, self.y, follow_speed)

    if abs(self.x - target_x) < 0.25 then self.x = target_x end
    if abs(self.y - target_y) < 0.25 then self.y = target_y end
end

-->8
-- UI MANAGER
-------------------------------------------------------------------------------
UIManager = {
    show_leaderboard = false,
    title_menu_index = 1,
    title_fade = 0,
    title_drop_y = -40,
    title_drop_vy = 0,
    title_bounce_done = false,
    title_anim_timer = 0,
    leaderboard_anim = 0,
    progress_flash = 0,
    record_anim_stage = 0,
    record_anim_timer = 0,
    record_anim_x = 0,
    record_anim_height = 2,
    record_anim_y_center = 64,
    record_anim_width = 128,
    record_anim_text = "",
    tile_respawn_anims = {},
    tile_respawn_active = false,
    tile_flashes = {},
    tile_flash_duration = 0.06
}

function UIManager:setup_tile_respawn_animations(old_map)
    self.tile_respawn_anims = {}
    self.tile_respawn_active = false

    -- find tiles that were destroyed (present in original level but missing in old_map)
    for i = 1, Map.width * Map.height do
        local original_tile = Game.levels[Game.current_level][i]
        local old_tile = old_map[i]

        -- if tile was destructible in original and is now missing/empty
        if (original_tile == 1 or original_tile == 2 or original_tile == 3 or (original_tile >= 7 and original_tile <= 14)) and old_tile == 0 then
            local idx0 = i - 1
            local tx = idx0 % Map.width
            local ty = flr(idx0 / Map.width)

            -- add to respawn animation list
            local delay = (tx + ty) * 0.06
            add(
                self.tile_respawn_anims, {
                    x = tx,
                    y = ty,
                    timer = -delay, -- start with negative timer so first tiles animate immediately
                    target_y = ty * Map.tile_size,
                    current_y = ty * Map.tile_size + 8, -- start 8 pixels below
                    delay = 0 -- no delay needed since we use negative timer
                }
            )
            self.tile_respawn_active = true
        end
    end
end

function UIManager:update_level_transition()
    Camera:reset()

    if Game.level_transition_phase == "slide" then
        Game.level_transition_offset = damp(Game.level_transition_offset, 128 * Game.level_transition_direction, 0.8)
        if abs(Game.level_transition_offset - 128 * Game.level_transition_direction) < 32 then
            Game.level_transition_phase = "fall"
        end
    elseif Game.level_transition_phase == "fall" then
        local all_new_finished = true
        for anim in all(Game.level_transition_new_anims) do
            anim.timer += 1 / 30
            if anim.timer >= 0 then
                anim.vy = anim.vy or 0
                local dy = anim.end_y - anim.current_y
                anim.vy += dy * 0.45
                anim.vy *= 0.65
                anim.current_y += anim.vy
                if abs(anim.current_y - anim.end_y) > 0.6 or abs(anim.vy) > 0.15 then
                    all_new_finished = false
                end
            else
                all_new_finished = false
            end
        end
        if all_new_finished then
            Game.level_transition = false
            Game.level_transition_started = false
            Game.current_level = Game.next_level

            if not Game.player then return end

            -- defer spawn until player is actually visible (after messages/transition)
            Game.player:set_position(Map.start_x, Map.start_y)
            Game.player.pending_spawn = true
            Game.player.spawning = false
            Game.player.spawn_timer = 0
            Game.player.spawn_flash = nil
            Game.player.input_buffered = false
            Game.player.buffered_dir = 0

            local gx, gy = Game.player.grid_x, Game.player.grid_y

            -- if out of map or not on edge -> keep camera centered
            if gx < 0 or gx >= Map.width or gy < 0 or gy >= Map.height then return end
            if gx ~= 0 and gx ~= Map.width - 1 and gy ~= 0 and gy ~= Map.height - 1 then return end

            local px, py = tile_to_px(gx, gy)
            local left_margin, right_margin = 24, 128 - 24
            local top_margin, bottom_margin = 24, 128 - 24

            if gx == 0 then
                Camera.x = px - left_margin
            elseif gx == Map.width - 1 then
                Camera.x = px - right_margin
            end

            if gy == 0 then
                Camera.y = py - top_margin
            elseif gy == Map.height - 1 then
                Camera.y = py - bottom_margin
            end

            local max_nudge = 48
            Camera.x = clamp(Camera.x, -max_nudge, max_nudge)
            Camera.y = clamp(Camera.y, -max_nudge, max_nudge)
        end
    end
end

function UIManager:update_common_effects()
    if Camera then Camera:update_shake() end
    if self.progress_flash > 0 then
        self.progress_flash -= 0.32
        if self.progress_flash < 0 then self.progress_flash = 0 end
    end
    if Game.level_transition then
        self:update_level_transition()
        return
    end
    ParticleSystem:update()
    self:update_flash_animation()
    self:update_tile_flashes()
    self:update_tile_respawn_animations()
end

function UIManager:update_title_state()
    if self.show_leaderboard and self.leaderboard_anim < 1 then
        self.leaderboard_anim = min(1, self.leaderboard_anim + 0.08)
    elseif not self.show_leaderboard and self.leaderboard_anim > 0 then
        self.leaderboard_anim = max(0, self.leaderboard_anim - 0.12)
    end

    if not self.title_menu_index then self.title_menu_index = 1 end

    if self.show_leaderboard then
        if btn(4) and btnp(5) then Game:reset_all_best_times() end
        if btnp(5) and not btn(4) then
            self.show_leaderboard = false
            return
        end
    end

    if not self.show_leaderboard and self.title_bounce_done then
        if btnp(2) then
            self.title_menu_index = max(1, self.title_menu_index - 1)
        elseif btnp(3) then
            self.title_menu_index = min(3, self.title_menu_index + 1)
        end

        if btnp(5) and not btn(4) then
            if self.title_menu_index == 1 then
                Game:start()
            elseif self.title_menu_index == 2 then
                Game:toggle_music()
            elseif self.title_menu_index == 3 then
                self.show_leaderboard = true
            end
        end
    end
end

function UIManager:update_tile_respawn_animations()
    if not self.tile_respawn_active then return end

    local all_finished = true

    for anim in all(self.tile_respawn_anims) do
        if anim.timer >= 0 then
            anim.current_y = damp(anim.target_y, anim.current_y, 0.5)
            if abs(anim.current_y - anim.target_y) > 0.5 then
                all_finished = false
            end
        else
            all_finished = false
        end

        anim.timer += 1 / 30
    end

    if all_finished then
        self.tile_respawn_active = false
        self.tile_respawn_anims = {}
    end
end

function UIManager:update_tile_flashes()
    if #self.tile_flashes == 0 then return end
    local to_finalize = {}
    for f in all(self.tile_flashes) do
        f.timer += 1 / 30
        if f.timer >= self.tile_flash_duration then
            add(to_finalize, f)
        end
    end
    for f in all(to_finalize) do
        Map:finalize_tile_removal(f)
        del(self.tile_flashes, f)
    end
end

function UIManager:reset()
    self.title_fade = 0
    self.title_bounce_done = false
    self.tile_respawn_anims = {}
    self.tile_respawn_active = false
    self.title_drop_y = -40
    self.title_drop_vy = 0
    self.title_bounce_done = false
    self.title_anim_timer = 0
end

function UIManager:update_flash_animation()
    if self.record_anim_stage == 0 then return end

    self.record_anim_timer += 0.08

    if self.record_anim_stage == 1 then
        self.record_anim_height = 1
        self.record_anim_width = 128
        self.record_anim_x = damp(0, 128, min(1, self.record_anim_timer)) -- slide from right to left

        if self.record_anim_timer >= 0.5 then
            self.record_anim_stage = 2
            self.record_anim_timer = 0
        end
    elseif self.record_anim_stage == 2 then
        self.record_anim_x = 0
        self.record_anim_width = 128
        self.record_anim_height = damp(16, 1, min(1, self.record_anim_timer))

        if self.record_anim_timer >= 0.3 then
            self.record_anim_stage = 3
            self.record_anim_timer = 0
        end
    elseif self.record_anim_stage == 3 then
        self.record_anim_x = 0
        self.record_anim_width = 128
        self.record_anim_height = 11

        if self.record_anim_timer >= 2 then
            self.record_anim_stage = 4
            self.record_anim_timer = 0
        end
    elseif self.record_anim_stage == 4 then
        self.record_anim_x = 0
        self.record_anim_width = 128
        self.record_anim_height = damp(1, 16, min(1, self.record_anim_timer))

        if self.record_anim_timer >= 0.5 then
            self.record_anim_stage = 5
            self.record_anim_timer = 0
        end
    elseif self.record_anim_stage == 5 then
        self.record_anim_x = 0
        self.record_anim_height = 1
        self.record_anim_width = damp(0, 128, min(1, self.record_anim_timer))

        if self.record_anim_timer >= 0.5 then
            self.record_anim_stage = 0
            self.record_anim_timer = 0
        end
    end
end

function UIManager:trigger_tile_flash(x, y, remove_after)
    for f in all(self.tile_flashes) do
        if f.x == x and f.y == y then
            return
        end
    end
    if remove_after == nil then remove_after = true end
    local entry = { x = x, y = y, timer = 0, remove_after = remove_after, tile = Map:get(x, y) }
    add(self.tile_flashes, entry)
end

function UIManager:get_flash_at(x, y)
    for f in all(self.tile_flashes) do
        if f.x == x and f.y == y then return f end
    end
    return nil
end

-->8
-- CORE GAME STATE ------------------------------------------------------------
Game = {
    t = 0,
    music_on = false,
    game_state = "title", -- "title", "playing", "won", "lost"
    immortal = false, -- debug mode to prevent falling off
    levels = {},
    level_transition_phase = nil,
    level_transition_offset = 0,
    level_transition_direction = 0,
    level_transition_new_anims = {},
    level_transition_started = false,
    level_transition = false,
    next_level = 1,
    current_level = 3,
    best_times = {} -- stores best time for each level
}

function Game:init()
    self.level_time = 0
    self.level_cleared = false
    self.level_cleared_timer = 0
    self.player = Player.new(Map.start_x, Map.start_y)

    menuitem(1, "music: " .. (Game.music_on and "on" or "off"), function() Game:toggle_music() end)
    menuitem(2, "back to title", function() Game:restart() end)

    Map:load_levels_from_native_map()
    ParticleSystem:clear()

    if self.player then
        self.player:set_position(Map.start_x, Map.start_y)
        self.player.pending_spawn = true
        self.player.spawning = false
        self.player.spawn_timer = 0
        self.player.spawn_flash = nil
        self.player.input_buffered = false
        self.player.buffered_dir = 0
    end
end

function Game:set_state(s)
    self.game_state = s
end

function Game:start()
    self.game_state = "playing"
    self:set_level(self.current_level, true, true)
end

function Game:restart()
    self.current_level = 1
    self.game_state = "title"
    UIManager:reset()
end

function Game:update()
    self.t += 0.01
    UIManager:update_common_effects()
    if self.game_state == "title" then
        UIManager:update_title_state()
    elseif self.game_state == "playing" then
        self:update_playing_state()
    elseif self.game_state == "won" then
        self:update_won_state()
    elseif self.game_state == "lost" then
        self:update_lost_state()
    end
end

function Game:draw()
    if self.game_state == "title" then
        UIManager:draw_title_screen()
        return
    end

    local shake_x, shake_y = Camera:get_shake()

    camera(0, 0)
    UIManager:draw_background()
    camera(shake_x + Camera.x, shake_y + Camera.y)
    Map:draw()
    ParticleSystem:draw(false)

    if is_player_visible(self.player) then
        self.player:draw()
    end

    camera(0, 0)
    UIManager:draw_gui()
    ParticleSystem:draw(true)

    if not self.level_transition then
        UIManager:draw_messages()
    end
end

function Game:update_playing_state()
    if not self.player then return end
    if self.level_transition then return end

    if self.level_cleared then
        self.level_cleared_timer += 1 / 30
        if self.level_cleared_timer >= 1 then
            self:handle_level_completion()
        end
        return
    end

    self.level_time += 1 / 30

    if self.player then self.player:update() end

    Camera:update()
end

function Game:update_lost_state()
    if not self.level_transition then
        Camera:center(-14)
    end

    if btnp(5) then self:reset_level(self.current_level) end

    if not self.level_transition_started then
        if btn(4) and btnp(1) then
            self:set_level(self.current_level + 1)
            self.game_state = "playing"
            if self.player then
                self.player:start_spawn_at(Map.start_x, Map.start_y)
            end
        elseif btn(4) and btnp(0) then
            self:set_level(self.current_level - 1)
            self.game_state = "playing"
            if self.player then
                self.player:start_spawn_at(Map.start_x, Map.start_y)
            end
        end
    end
end

function Game:update_won_state()
    Camera:center()
    if btnp(5) then
        self:restart()
    end
end

function Game:save_best_times()
    for i = 1, min(#self.levels, 63) do
        -- dget/dset supports indices 0-63, save 0 for metadata
        if self.best_times[i] then
            dset(i, self.best_times[i])
        else
            dset(i, -1) -- use -1 to indicate no time set
        end
    end
    -- save number of levels in slot 0 as metadata
    dset(0, #self.levels)
end

function Game:load_best_times()
    self.best_times = {}
    local saved_levels = dget(0)

    if saved_levels > 0 then
        for i = 1, min(saved_levels, 63) do
            local saved_time = dget(i)
            -- -1 means no time was saved
            if saved_time >= 0 then
                self.best_times[i] = saved_time
            end
        end
    end

    for i = 1, #self.levels do
        if not self.best_times[i] then
            self.best_times[i] = nil -- no best time initially
        end
    end
end

function Game:check_best_time()
    local current_time = self.level_time
    local level_idx = self.current_level

    if not self.best_times[level_idx] or current_time < self.best_times[level_idx] then
        self.best_times[level_idx] = current_time
        UIManager:trigger_flash_animation(90, "new record!")
        self:save_best_times()
        return true
    end

    return false
end

function Game:reset_all_best_times()
    for i = 1, #self.levels do
        self.best_times[i] = nil
    end
    self:save_best_times()
end

function Game:set_level(n, force, skip_slide)
    if not n then return end
    if n > #self.levels then
        n = 1
    elseif n < 1 then
        n = #self.levels
    end
    if type(n) ~= "number" then n = 1 end
    if n == self.current_level and not force then return end

    self.level_transition_new_anims = {}
    self.level_transition_started = true
    self.level_transition = true
    self.next_level = n

    UIManager:trigger_flash_animation(68, "get ready!")
    Camera:reset()
    Map:save_old_map()

    local ay = 5
    for tx = 0, Map.width - 1 do
        for ty = 0, Map.height - 1 do
            local idx = ty * Map.width + tx + 1
            if self.levels[self.next_level][idx] ~= 0 then
                local end_y = ay + ty * Map.tile_size
                local start_y = end_y - Map.tile_size
                add(
                    self.level_transition_new_anims, {
                        x = tx,
                        y = ty,
                        tile = self.levels[self.next_level][idx],
                        timer = -((ty * Map.width + tx) * 0.02),
                        start_y = start_y,
                        current_y = start_y,
                        end_y = end_y
                    }
                )
            end
        end
    end
    if skip_slide then
        self.level_transition_phase = "fall"
        self.level_transition_offset = 0
        self.level_transition_direction = 0
    else
        self.level_transition_phase = "slide"
        self.level_transition_offset = 0
        self.level_transition_direction = self.next_level > self.current_level and -1 or 1
    end

    if type(self.next_level) == "number" then
        self.current_level = self.next_level
    else
        self.current_level = 1
    end

    Map:reset(true)
end

function Game:reset_level(level)
    if type(level) == "number" then
        self.current_level = level
    else
        self.current_level = 1
    end
    self.lives = 1
    self.level_time = 0
    self.game_state = "playing"
    self.level_cleared = false
    self.level_cleared_timer = 0
    self.level_transition = false
    self.level_transition_started = false

    ParticleSystem:clear()
    Map:reset()
    Camera:center()

    if self.player then
        self.player:start_spawn_at(Map.start_x, Map.start_y)
    end
end

function Game:handle_level_completion()
    if UIManager.record_anim_stage > 0 then return end

    self.level_cleared = false
    self.level_cleared_timer = 0

    local nextn = self.current_level + 1
    if nextn > #self.levels then
        self.current_level = 1
        self.game_state = "won"
    else
        self:set_level(nextn)
    end
end

function Game:is_showing_messages()
    return (self.level_cleared and self.level_cleared_timer < 5)
            or self.game_state == "won"
            or self.game_state == "lost"
            or UIManager.record_anim_stage > 0
end

function Game:toggle_music()
    self.music_on = not self.music_on
    menuitem(1, "music: " .. (self.music_on and "on" or "off"), function() Game:toggle_music() end)
    if self.music_on then music(0) else music(-1) end
end

-->8
-- PARTICLE SYSTEM
-------------------------------------------------------------------------------
ParticleSystem = {}
ParticleSystem.__index = ParticleSystem
ParticleSystem.particles = {}
ParticleSystem.max_particles = 140 -- safety cap for particles to avoid FPS drops

function ParticleSystem:clear()
    self.particles = {}
end

function ParticleSystem:create_particle(x, y, col, vx, vy, life, is_trail, is_rect, is_ui)
    local p = {
        x = x,
        y = y,
        vx = vx or (rnd(2) - 1) * 2,
        vy = vy or -rnd(2) - 0.5,
        life = life or 1,
        col = col,
        is_trail = is_trail or false,
        is_rect = is_rect or false,
        is_ui = is_ui or false,
        rotation = 0,
        rot_speed = (rnd(2) - 1) * 0.2
    }
    if #self.particles >= self.max_particles then
        return
    end
    --@todo: when at capacity, consider dropping oldest particle instead of silently skipping
    add(self.particles, p)
end

function ParticleSystem:create_simple_particle(x, y, col)
    self:create_particle(x, y, col)
end

function ParticleSystem:create_debris_particles(px, py, col1, col2)
    col2 = col2 or col1
    self:create_particle(px, py, col1, -2, -2, 1.5, false, true, true)
    self:create_particle(px, py, col1, 2, -2, 1.5, false, true, true)
    self:create_particle(px, py, col2, -2, 2, 1.5, false, true, true)
    self:create_particle(px, py, col2, 2, 2, 1.5, false, true, true)
end

function ParticleSystem:create_trail(old_gx, old_gy, new_gx, new_gy)
    local old_px, old_py = tile_to_px(old_gx, old_gy)
    local new_px, new_py = tile_to_px(new_gx, new_gy)

    for i = 0, 15 do
        local t = i / 15
        local trail_x = old_px + (new_px - old_px) * t
        local trail_y = old_py + (new_py - old_py) * t

        self:create_particle(trail_x + rnd(4) - 2, trail_y + rnd(4) - 2, 8, 0, 0, 0.8, true)
    end
end

function ParticleSystem:update()
    local to_remove = {}
    for p in all(self.particles) do
        p.x += p.vx
        p.y += p.vy
        if not p.is_trail then p.vy += 0.1 end
        if p.is_rect then p.rotation += p.rot_speed end
        p.life -= 0.02
        if p.life <= 0 then add(to_remove, p) end
    end
    for p in all(to_remove) do
        del(self.particles, p)
    end
end

function ParticleSystem:draw(only_ui)
    if Game.game_state ~= "playing" or Game.level_transition then
        return
    end
    for p in all(self.particles) do
        if only_ui and not p.is_ui then goto continue end
        if not only_ui and p.is_ui then goto continue end

        local size = p.life * 2
        local col = p.col
        if p.is_trail then
            size = p.life * 3.5
            col = p.life > 0.6 and 7 or (p.life > 0.3 and 6 or 5)
            circfill(p.x, p.y, size, col)
        elseif p.is_rect then
            local w = 3
            local h = 3
            if flr(p.rotation * 2) % 2 == 0 then
                rectfill(p.x - w, p.y - h / 2, p.x + w, p.y + h / 2, col)
            else
                rectfill(p.x - h / 2, p.y - w, p.x + h / 2, p.y + w, col)
            end
        else
            circfill(p.x, p.y, size, col)
        end

        ::continue::
    end
end

-->8
-- MAP FUNCTIONS
-------------------------------------------------------------------------------
function Map:check_level_completion()
    local prev = self.tiles_left or self:count_tiles()
    self.tiles_left = self:count_tiles()
    if self.tiles_left < prev then
        UIManager.progress_flash = 1
    end
    if self.tiles_left <= 0 then
        Game:check_best_time()
        Game.level_cleared = true
        Game.level_cleared_timer = 0
        ParticleSystem:clear()
        Game.player.grid_x = 0
        Game.player.grid_y = 0
        Game.player.old_x = 0
        Game.player.old_y = 0
        Game.player.moving = false
    end
end

function Map:save_old_map()
    self.old_map = {}
    for i = 1, self.width * self.height do
        self.old_map[i] = Game.levels[Game.current_level][i]
    end
end

function Map:handle_teleport(x, y, debris)
    local px, py = tile_to_px(x, y)
    local world_px = px - Camera.x
    local world_py = py - Camera.y
    sfx(12)
    self:set(x, y, 0)
    Camera:trigger_shake()
    ParticleSystem:create_debris_particles(world_px, world_py, debris[1], debris[2])
    Map:check_level_completion()
end

function Map:hit_tile(x, y)
    local tile = self:get(x, y)
    local teleport = tile_meta[tile]

    if teleport then
        self:handle_teleport(x, y, teleport.debris)
        return
    end

    -- tiles 1,2,3 can be hit (5 is permanent platform)
    if tile == 1 or tile == 2 or tile == 3 then
        Camera:trigger_shake()
        local px, py = tile_to_px(x, y)

        for i = 1, 8 do
            local col = rnd(1) > 0.5 and 10 or 9
            ParticleSystem:create_simple_particle(px, py, col)
        end

        sfx(12)

        local new_tile = tile - 1
        local will_remove = new_tile <= 0

        UIManager:trigger_tile_flash(x, y, will_remove)

        if not will_remove then
            Map:set(x, y, new_tile)
            sfx(11)
        end
    end
end

function Map:draw()
    local ay = 4

    -- draw a map with offset
    local function draw_map(map_data, x_offset, y_offset)
        y_offset = y_offset or 0
        for tx = 0, self.width - 1 do
            local base_x = tx * self.tile_size + x_offset
            -- early skip if entire column is off screen
            if base_x > -self.tile_size and base_x < 128 then
                for ty = 0, self.height - 1 do
                    local idx = ty * self.width + tx + 1
                    local s = map_data[idx]
                    if s ~= 0 then
                        local yy = ay + ty * self.tile_size + y_offset
                        local animated_y = yy
                        local should_draw = true
                        if UIManager.tile_respawn_active then
                            for anim in all(UIManager.tile_respawn_anims) do
                                if anim.x == tx and anim.y == ty then
                                    animated_y = ay + anim.current_y
                                    -- only draw tile if its animation has started (timer >= 0)
                                    should_draw = anim.timer >= 0
                                    break
                                end
                            end
                        end

                        if should_draw then
                            UIManager:draw_tile_with_anim(s, base_x, animated_y)
                        end
                    end
                end
            end
        end
    end

    -- draw background circle in the middle
    circfill(64 - Camera.x, 64 - Camera.y, 42, 0)

    if Game.level_transition then
        if Game.level_transition_phase == "slide" then
            draw_map(self.old_map, Game.level_transition_offset)
        elseif Game.level_transition_phase == "fall" then
            for anim in all(Game.level_transition_new_anims) do
                if anim.timer >= 0 and anim.tile and anim.tile ~= 0 then
                    local base_x = anim.x * self.tile_size
                    UIManager:draw_tile_with_anim(anim.tile, base_x, anim.current_y)
                end
            end
        end
    else
        -- normal drawing (no transition)
        draw_map(self.current_map, 0)
    end
end

function Map:finalize_tile_removal(f)
    if not f or not f.remove_after then return end

    local x, y = f.x, f.y
    local px, py = tile_to_px(x, y)
    self:set(x, y, 0)
    local world_px = px - Camera.x
    local world_py = py - Camera.y

    local tileid = f.tile or 0
    local meta = tile_meta[tileid]
    local col1 = (meta and meta.debris and meta.debris[1]) or 8
    local col2 = (meta and meta.debris and meta.debris[2]) or col1

    ParticleSystem:create_debris_particles(world_px, world_py, col1, col2)
    Map:check_level_completion()
end

---------------------------------------------------------------
function UIManager:draw_tile_with_anim(tile, x, y)
    local draw_tile = tile == 4 and 42 or tile

    local function draw_tile_sprite(base_sprite, x, y)
        spr(base_sprite, x, y)
        spr(base_sprite + 1, x + 8, y)
        spr(base_sprite + 16, x, y + 8)
        spr(base_sprite + 17, x + 8, y + 8)
    end

    if draw_tile >= 7 and draw_tile <= 14 then
        local bg_tile = (draw_tile >= 11 and draw_tile <= 14) and teleport2_bg_sprite or teleport1_bg_sprite
        draw_tile_sprite(bg_tile, x, y)
        local icon_sprite = get_teleport_anim_sprite(draw_tile)
        spr(icon_sprite, x + 4, y + 3)
    else
        draw_tile_sprite(map_tile_to_sprite(draw_tile), x, y)
    end

    -- draw flash overlay if applicable
    local tx = flr(x / Map.tile_size)
    local ay = 4
    local ty = flr((y - ay) / Map.tile_size)
    local f = self:get_flash_at(tx, ty)
    if f then
        local base_sprite = map_tile_to_sprite(draw_tile)
        local src_x = (base_sprite % 16) * 8
        local src_y = flr(base_sprite / 16) * 8

        local ssrc_x = src_x
        local ssrc_y = src_y

        for c = 1, 15 do
            pal(c, 7)
        end

        sspr(ssrc_x, ssrc_y, Map.tile_size, Map.tile_size, x, y, Map.tile_size, Map.tile_size)

        -- if draw_tile >= 7 and draw_tile <= 14 then
        --     local icon_sprite = get_teleport_anim_sprite(draw_tile)
        --     sspr((icon_sprite % 16) * 8, flr(icon_sprite / 16) * 8, 8, 8, x + 4, y + 4, 8, 8)
        -- end

        pal()
    end
end

function UIManager:draw_gui()
    rectfill(0, 0, 128, 9, 0)
    spr(128, 96, 1)

    local display_level = (Game.level_transition and Game.next_level) or Game.current_level
    local level_text = "level " .. display_level
    print(level_text, 2, 3, 1)
    print(level_text, 2, 2, 6)

    local time_text = (Game.level_transition and "00:00") or format_time(Game.level_time)
    local time_width = #time_text * 4
    print(time_text, 128 - time_width - 2, 3, 1)
    print(time_text, 128 - time_width - 2, 2, 6)
end

function UIManager:draw_title_screen()
    local title_x, title_y = 33, 26
    local menu_x, menu_y = 64, title_y + 46
    local menu_spacing = 9
    local pulse = sin(Game.t * 2) * 0.5 + 0.5

    if self.title_bounce_done then
        rectfill(14, 14, 112, 112, 0)
        self:draw_background()
    else
        cls()
    end

    self.title_anim_timer = (self.title_anim_timer or 0) + 1 / 30

    if not self.show_leaderboard then
        rectfill(20, 20, 106, 106, 0)
        self.title_fade = mid(0, (self.title_fade or 0) + 0.05, 2)
        if self.title_bounce_done == nil then self.title_bounce_done = false end
        if not self.title_bounce_done then
            self.title_drop_vy = (self.title_drop_vy or 0) + 0.9 -- gravity
            self.title_drop_y = (self.title_drop_y or -40) + self.title_drop_vy
            if self.title_drop_y >= 0 then
                self.title_drop_y = 0
                self.title_drop_vy = -self.title_drop_vy * 0.45 -- bounce with damping
                if abs(self.title_drop_vy) < 0.6 then
                    self.title_drop_vy = 0
                    self.title_bounce_done = true
                end
            end
        end
        local cur_y = title_y + (self.title_drop_y or 0)
        if self.title_fade < 1 then
            if self.title_fade < 0.33 then
                for c = 1, 15 do
                    pal(c, 0)
                end
            elseif self.title_fade < 0.66 then
                for c = 1, 15 do
                    pal(c, (c == 8 or c == 2 or c == 1) and 0 or 1)
                end
            elseif self.title_fade < 0.77 then
                for c = 1, 15 do
                    pal(c, 12)
                end
            else
                for c = 1, 15 do
                    pal(c, c)
                end
            end
        end

        for i = 0, 7 do
            spr(136 + i, title_x + i * 8, cur_y)
            spr(152 + i, title_x + i * 8, cur_y + 8)
            spr(168 + i, title_x + i * 8, cur_y + 16)
            spr(184 + i, title_x + i * 8, cur_y + 24)
        end

        pal()

        if self.title_bounce_done then
            local delay, flash_dur = 0.6, 0.8
            if self.title_anim_timer >= delay then
                rect(20, 20, 106, 106, self.title_anim_timer >= 0.75 and 1 or 0)
                local ft = self.title_anim_timer - delay
                if ft < flash_dur then
                    local pulse = sin(Game.t * 20)
                    local col = pulse > 0 and 7 or 10
                    print_centered("BOUNCING", cur_y - 8, col, 4)
                    print_centered("BY PRAgHUS", cur_y + 33, col, 4)
                else
                    print_centered("BOUNCING", cur_y - 8, 10, 4)
                    print_centered("BY PRAgHUS", cur_y + 33, 10, 4)
                end
            end
            print("V1.1", 110, 120, 6)

            if not self.title_menu_index then self.title_menu_index = 1 end
            local items = {
                "start",
                (Game.music_on and "music: on" or "music: off"),
                "best times"
            }
            if self.title_anim_timer >= 0.6 then
                for i = 1, #items do
                    local yy = menu_y + (i - 1) * menu_spacing
                    if i == self.title_menu_index and self.title_anim_timer >= 1.1 then
                        rectfill(menu_x - 32, yy - 2, menu_x + 32, yy + 6, self.title_anim_timer >= 1.2 and 8 or 2)
                        print_centered(items[i], yy, 7)
                    else
                        print_centered(items[i], yy, self.title_anim_timer >= 0.7 and 6 or 1)
                    end
                end
            end
        end
    end

    if self.leaderboard_anim > 0 then
        self:draw_leaderboard()
    end
end

function UIManager:draw_leaderboard()
    local board_width = 100
    local board_height = 100
    local board_x = (128 - board_width) / 2
    local board_y = (128 - board_height) / 2 - (board_height * (1 - UIManager.leaderboard_anim))
    local k = flr(2 * cos(Game.t * 4))

    rectfill(board_x + k, board_y + k, board_x + board_width + 0.9999 - k, board_y + board_height + 0.9999 - k, 0)
    rect(board_x + k, board_y + k, board_x + board_width + 0.9999 - k, board_y + board_height + 0.9999 - k, 1)

    local col_width = board_width / 2
    local start_x1 = board_x + 8
    local start_x2 = board_x + col_width + 8
    local start_y = board_y + 20
    local row_height = 8
    local levels_per_column = 8

    local total_levels = #Game.levels
    local max_display = min(total_levels, levels_per_column * 2)
    local bt = Game.best_times

    for i = 1, max_display do
        local col = 1
        local row_index = i
        local x = start_x1

        if i > levels_per_column then
            col = 2
            row_index = i - levels_per_column
            x = start_x2
        end

        local y_pos = start_y + (row_index - 1) * row_height

        print(tostring(i), x, y_pos, 6)

        local value = bt[i]
        if value then
            print(format_time(value), x + 12, y_pos, 11)
        else
            print("--:--", x + 12, y_pos, 5)
        end
    end

    print_centered("\x8e+\x97 reset records", board_y + 8, 9, 1)
    print_centered("press \x97 to close", board_y + board_height - 12, 6, 1)
end

function UIManager:draw_background()
    --@todo: expensive per-frame work (loop 0..999). Consider caching star positions
    --@todo: reduce iteration count or precompute background to improve FPS on low-end targets
    rectfill(16 - Camera.x, 16 - Camera.y, 114 - Camera.x, 116 - Camera.y, 0)
    for i = 0, 999 do
        local x, y = rnd(128), rnd(128)
        local c = pget(x, y)
        local plt = Game.game_state == "title" and palette[0] or palette[Game.current_level % #palette + 1]
        local a = atan2(x - 64, y - 64)
        if plt[c] then
            if rnd(1.1) >= 1 then
                c = plt[c]
            end
        else
            c = 0
        end
        circfill(x + 2 * cos(a), y + 2 * sin(a), 1, c)
    end
end

function UIManager:draw_messages()
    local pulse = sin(Game.t * 4) * 0.5 + 0.5
    local color = 7 + flr(pulse * 3)

    if Game.level_cleared and Game.level_cleared_timer < 5 then
        local time_text = "time: " .. format_time(Game.level_time)
        local text1 = "level cleared!"
        local best_time = Game.best_times[Game.current_level]
        local best_text = ""
        if best_time then
            best_text = "best: " .. format_time(best_time)
            width3 = #best_text * 4
        end

        local box_height = best_time and 78 or 70
        rectfill(0, 50, 128, box_height, 0)

        print_centered(text1, 54, color)
        print_centered(time_text, 62, 7)

        if best_time then
            print_centered(best_text, 70, 6)
        end
    elseif Game.game_state == "won" then
        rectfill(0, 50, 128, 70, 0)
        print_centered("all levels complete!", 54, 11)
        print_centered("press \x97 to restart", 62, 7)
    elseif Game.game_state == "lost" then
        rectfill(0, 0, 128, 8, 1)
        print_centered("press \x8e+<> to level skip", 2, 6, 0)
        print_centered("press \x97 to restart", 20, color, 0)
    end
    self:draw_flash_animation()
end

function UIManager:trigger_flash_animation(y_offset, text)
    if self.record_anim_stage > 0 then return end
    self.record_anim_stage = 1
    self.record_anim_timer = 0
    self.record_anim_x = 128
    self.record_anim_height = 1
    self.record_anim_y_center = y_offset or 64
    self.record_anim_width = 128
    self.record_anim_text = text or ""
end

function UIManager:draw_flash_animation()
    if self.record_anim_stage == 0 then return end

    local y_center = self.record_anim_y_center or 64
    local y_pos = y_center - self.record_anim_height / 2
    local rect_color = 7

    if self.record_anim_stage == 3 then
        rect_color = 0
    end

    rectfill(self.record_anim_x, y_pos, self.record_anim_x + self.record_anim_width - 1, y_pos + self.record_anim_height - 1, rect_color)

    if self.record_anim_stage == 3 then
        local text = self.record_anim_text
        local text_width = #text * 4
        local text_y = y_center - 3 -- center text vertically

        if self.record_anim_height >= 8 and self.record_anim_width >= text_width then
            local pulse = sin(Game.t * 8) * 3 + 3 -- cycles through colors 0-6
            local color = flr(pulse) + 8 -- colors 8-14 (bright colors)
            if color > 14 then color = 8 + (color - 15) end
            print_centered(text, text_y, color)
        end
    end
end

-->8
-- HELPERS AND UTILS
-------------------------------------------------------------------------------
function damp(a, b, i) return i * a + (1 - i) * b end
function clamp(a, mi, ma) return min(max(a, mi), ma) end
function lerp(a, b, t) return a + (b - a) * t end
function map_tile_to_sprite(id) return tile_sprite_map[id] or id end
function tile_to_px(x, y) return 0 + x * Map.tile_size + 8, y * Map.tile_size + 8 end
function ball_render_size(p) return (p and (p.w or 0) or 0) / 1.8 end

function print_centered(text, y, col, shadow_col)
    local width = 0
    for i = 1, #text do
        local ch = sub(text, i, i)
        local code = ord(ch)
        if code >= 128 then
            width += 8
        else
            width += 4
        end
    end
    if shadow_col then
        print(text, 65 - width / 2, y + 1, shadow_col)
    end
    print(text, 65 - width / 2, y, col)
end

function get_teleport_anim_sprite(tile)
    local anim_frame = flr((Game.t * 24) % 6)
    local meta = tile_meta[tile]
    if meta and meta.anim_base then
        return meta.anim_base + anim_frame
    end
    return 0
end

function is_ball_drawn(p)
    if not p then return false end
    local s = (p.w or 0) / 1.8
    return s > 0.5
end

function is_player_visible(p)
    return p and not Game.level_cleared and not Game.level_transition and not Game:is_showing_messages() and is_ball_drawn(p)
end

function format_time(time_seconds)
    local minutes = flr(time_seconds / 60)
    local seconds = flr(time_seconds % 60)
    local time_text = ""
    if minutes < 10 then
        time_text = "0" .. minutes
    else
        time_text = "" .. minutes
    end
    time_text = time_text .. ":"
    if seconds < 10 then
        time_text = time_text .. "0" .. seconds
    else
        time_text = time_text .. seconds
    end
    return time_text
end

function init_background_palette()
    for j = 0, #palette do
        local plt = palette[j]
        local nplt = {}
        for i = 1, #plt do
            nplt[plt[i]] = plt[i % #plt + 1]
        end
        palette[j] = nplt
    end
end

init_background_palette()

__gfx__
000000008888888899999999aaaaaaaa777777767777777600000000bbbbbbb3bbbbbbb3bbbbbbb3bbbbbbb37777777c7777777c7777777c7777777c00000000
000000008888888899999999aaaaaaaa766666657666666500000000b3373331b3333331b3337331b33333317cccccc17cccccc17cccccc17cccccc100000000
000000008887788899977799aaa888aa7668866576d66d6500000000b3777331b3337331b3337331b33733317cc111c17c1cccc17cccc1c17c111cc100000000
000000008888788899999799aaaa88aa768e82657666666500000000b7777731b3337731b3337331b37733317ccc11c17cc1c1c17c1c1cc17c11ccc100000000
000000008888788899979999aaaaa8aa768882657666666500000000b3373331b7777771b3777771b77777717cc1c1c17ccc11c17c11ccc17c1c1cc100000000
000000008887778899977799aaa888aa7662266576d66d6500000000b3373331b3337731b3377731b37733317c1cccc17cc111c17c111cc17cccc1c100000000
000000008888888899999999aaaaaaaa766666657666666500000000b3373331b3337331b3337331b33733317cccccc17cccccc17cccccc17cccccc100000000
000000008888888899999999aaaaaaaa65555555655555550000000031111111311111113111111131111111c1111111c1111111c1111111c111111100000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000aaaaaaaaaaaa000000000000000000000000000000000006666666666666000ddddddddddddd0006666666666666d0
000000000000000000999999999999000aaaaaaaaaaaaaa000cccccccccccc0000bbbbbbbbbbbb006555555555555560ddddddddddddddd1666666666666666d
000888888888800009999999999999900aa444aaaaaaaaa00cccccccccccccc00bbbbbbbbbbbbbb06d66666666666d60ddddddddddddddd1666666666666666d
0088888888888800099aa999999999900aaa99aaaaaaaaa00cc1111111111cc00bb1111111111bb06d65666666656d60dddd5ddddd5dddd1666d66666666d66d
0088ff88888888000999a999999999900aaaa9aaaaaaaaa00cc1dddddddd1cc00bb1333333331bb06d67666666676d60ddd516ddd516ddd1666766666666766d
00888f8888888800099a9999999999900aa999aaaaaaaaa00cc1cccccccc1cc00bb1bbbbbbbb1bb06d66666666666d60dddd6ddddd6dddd1666666666666666d
00888f8888888800099aa999999999900aaaaaaaaaaaaaa00cc1cccccccc1cc00bb1bbbbbbbb1bb06d66666666666660ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc1cccccccc1cc00bb1bbbbbbbb1bb06d66666666666d60ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc5cccccccc5cc00bb3bbbbbbbb3bb06666666666666660ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cccccccccccccc00bbbbbbbbbbbbbb06d66666666666660dddd5ddddd5dddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc5cccccccc5cc00bb3bbbbbbbb3bb0666d6666666d6660ddd516ddd516ddd1666666666666666d
00e8888888888e00099999999999999007aaaaaaaaaaaa700cccccccccccccc00bbbbbbbbbbbbbb06667666666676660dddd6ddddd6dddd1666d66666666d66d
0027eeeeeeeee2000f999999999999f009777777777777900dccccccccccccd006bbbbbbbbbbbb606666666666666660ddddddddddddddd1666766666666766d
0002222222222000047fffffffffff400499999999999940056ddddddddddd50057666666666665066666666666666606ddddddddddddd61766666666666667d
00000000000000000044444444444400029999999999992000555555555555000055555555555500d7777777777777501666666666666610d7777777777777dd
00000000000000000000000000000000002222222222220000000000000000000000000000000000055555555555550001111111111111000dddddddddddddd0
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000000000000000000000000000
07000000007000000007000000007000000700000070000000770000000070000000000000000000000000000000700000000000000000000000000000000000
07700000007700000007700000007700000770000077000007770000000770000000070000000000000007000007700000000000000000000000000000000000
07770000007770000007770000007770000777000077700001110000007770000000770000000070000077000077700000000000000000000000000000000000
07710000007710000007710000007710000771000077100000000000001110000007770000000770000777000011100000000000000000000000000000000000
07100000007100000007100000007100000710000071000000000000000000000001110000007770000111000000000000000000000000000000000000000000
01000000001000000001000000001000000100000010000000000000000000000000000000001110000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000007770000000000000000000000000000000000000000000000000
00000070000007000000700000070000000070000000070000000000000000000007770000001770000777000000000000000000000000000000000000000000
00000770000077000007700000770000000770000000770000000000007770000001770000000170000177000077700000000000000000000000000000000000
00007770000777000077700007770000007770000007770007770000001770000000170000000010000017000017700000000000000000000000000000000000
00001770000177000017700001770000001770000001770001770000000170000000010000000000000001000001700000000000000000000000000000000000
00000170000017000001700000170000000170000000170000170000000010000000000000000000000000000000100000000000000000000000000000000000
00000010000001000000100000010000000010000000010000010000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000007000000000000000000000000000000000000000000007770000000000000000000000000000000000000000000000000000
00000000000000000000700000077700000070000000000000000000000000000077700007710000007770000000000000000000000000000000000000000000
00000000000070000007770000777770000777000000700000000000000777000077100007100000007710000007770000000000000000000000000000000000
00007000000777000077777000111110007777700007770000007770000771000071000001000000007100000007710000000000000000000000000000000000
00077700007777700011111000000000001111100077777000007710000710000010000000000000001000000007100000000000000000000000000000000000
00777770001111100000000000000000000000000011111000007100000100000000000000000000000000000001000000000000000000000000000000000000
00111110000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00777770000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000000000000000
00177710007777700000000000000000000000000077777000000770000070000000000000000000000000000000700000000000000000000000000000000000
00017100001777100077777000000000007777700017771000000777000077000007000000000000000700000000770000000000000000000000000000000000
00001000000171000017771000777770001777100001710000000111000077700007700000700000000770000000777000000000000000000000000000000000
00000000000010000001710000177710000171000000100000000000000011100007770000770000000777000000111000000000000000000000000000000000
00000000000000000000100000017100000010000000000000000000000000000001110000777000000111000000000000000000000000000000000000000000
00000000000000000000000000001000000000000000000000000000000000000000000000111000000000000000000000000000000000000000000000000000
00666000000000000000000000000000000000000000000000000000000000007ffffffffffff7007ffffffff0000000ffffffff000ffffffffffffff0000000
0611160000000000000000000000000000000000000000000000000000000000e8888888888888f2e8888888ff00000f88888888ffdf8888888888888f000000
6106016000000000000000000000000000000000000000000000000000000000e88888888888888fe88888888e1000f88888888888e288888888888888f00000
6006606000000000000000000000000000000000000000000000000000000000e888888888888888f88888888e100e8888888888888e288888888888888e0000
6001106000000000000000000000000000000000000000000000000000000000e888888222888888e28888888e11e88888888888888e128888222888888e0000
1600061000000000000000000000000000000000000000000000000000000000e8888821112888888e288888e0112888888888888888e128821112888888e000
01666100000000000000000000000000000000000000000000000000000000000e888821100288888e288888e0128888888222288888e128821100288888e100
00111000000000000000000000000000000000000000000000000000000000000e888821100288888e088888e01288888821111288888e12821100288888e100
00000000000000000000000000000000000000000000000000000000000000000e888821100288888e088888e01288888821000288888e11821100288888e100
00000000000000000000000000000000000000000000000000000000000000000e88882110028888e0188888e01288888821100288888e1182110028888e1100
00000000000000000000000000000000000000000000000000000000000000000e88882110028888e0188888e01288888821100288888e1182110028888e1100
00000000000000000000000000000000000000000000000000000000000000000e8888211128888e01888888e01288888821100288888e118211128888e11100
00000000000000000000000000000000000000000000000000000000000000000e888882118888e001888888e01288888821100288888e11182118888e111000
00000000000000000000000000000000000000000000000000000000000000000e8888888888ee0012888888e01288888821100288888e111888888ee1111000
00000000000000000000000000000000000000000000000000000000000000000e888888888888e001288888e01288888821100288888e11188888888e110000
00000000000000000000000000000000000000000000000000000000000000000e8888822288888e01288888e01288888821100288888e111822288888e10000
00000000000000000000000000000000000000000000000000000000000000000e28882111288888e0128888e01228888821100288882e1112111288888e0000
00000000000000000000000000000000000000000000000000000000000000000e228221100228822e112282e01222222221100288222e11121100228822e000
00000000000000000000000000000000000000000000000000000000000000000e2222211002222222e11222e01221111221100222222e111211002222222e00
00000000000000000000000000000000000000000000000000000000000000000e2222211002222222e11222201212222e21101222222e111211002222222e10
00000000000000000000000000000000000000000000000000000000000000000e2222211002222222e11222201112222e02111222222e111211002222222e10
00000000000000000000000000000000000000000000000000000000000000000e2222211112222222e11222200002222e02222222221d111211112222222e10
0000000000000000000000000000000000000000000000000000000000000000d22222211122222221d11222222222222d0222222221d1111211122222221d10
0000000000000000000000000000000000000000000000000000000000000000d1222222222222221d111222222222222d0222222211d111122222222221d110
0000000000000000000000000000000000000000000000000000000000000000c1122222222222111c110122222222221c012222211c1111022222222111c110
0000000000000000000000000000000000000000000000000000000000000000c111111111111111c1110111111111111c011111111c111101111111111c1110
0000000000000000000000000000000000000000000000000000000000000000c1111111111111cc11110111111111111c01111111c11111011111111cc11110
0000000000000000000000000000000000000000000000000000000000000000cccccccccccccc1111110dccccccccccc101cccccc1111110cccccccc1111110
00000000000000000000000000000000000000000000000000000000000000001111111111111111111011111111111111011111111111101111111111111100
00000000000000000000000000000000000000000000000000000000000000001111111111111111111011111111111111101111111111101111111111111100
00000000000000000000000000000000000000000000000000000000000000001111111111111111110011111111111111110111111111011111111111111000
00000000000000000000000000000000000000000000000000000000000000000111111111111111000001111111111111100001111100001111111111100000
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00088800000888000008880000000000000000000000000007000777070707770700000007700707000000000000000000000000007770777000007770777000
00878880008788800087888000000000000000000000000007000700070707000700000000700707000000000000000000000000007070707007007070007000
00888880008888800088888000000000000000000000000007000770070707700700000000700777000000000000000000000000007070707000007070077000
00888880008888800088888000000000000000000000000007000700077707000700000000700007000000000000000000000000007070707007007070007000
00088800000888000008880000000000000000000000000007770777007007770777000007770007000000000000000000000000007770777000007770777000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000100011110000013300000000100001100001110000000131010000010003110000000100000000001001000010000000010000000000000101111111330
00000000101110000111310000000000000000000110000000111100001001033311100001100000000110000000000000000100001000000011111111130100
00000000001111000011111000000000000000000011000101111000001110003111100001100000000110000000000000000000000000000311111011331110
00000001100111100001111000000000000000000000000000111000000000003100000001110100000100000010000000010000000000003111110001101103
00000000111001110000010111101000000000000000000000010000000000000000000001110100000000000000000000111000000000001111000001000103
00000001110000101000000000111100000000000000000000100000000000000000000000111000000000000000000000010011000000000100000000101000
13031101001001110000088888001000000000001000000000000000000000000000000000000000000000000000000001000000000000000000000000000000
113110111000000000777eeeee880000000000011110000000000000000000000000000000000000100000000000000011100000000000000000000100000000
1110000100000000077777eeeee88000000000001110000000000000000000000000000000000000110000000000000001000000000000000000000000000000
11000011100000007777777eeeee880000000000000000000000000000000000000000000000000010aaaaaaaaaaaa0000000000100000000000010100100000
11101001100000007777777eeeeee8800000000000001000000000000000000000000000000000000aaaaaaaaaaaaaa000999999999999000000011000000001
00013000100000007777777eeeeeee800008888888888100001000000000000000088888888880000aa444aaaaaaaaa009999999999999900000010000000001
0103300000000008877777eeeeeeee880088888888888800010000000000000000888888888888000aaa99aaaaaaaaa0099aa999999999900000000000000000
11103300000001088e777eeeeeeeee880088ff888888880000000000000000000088ff88888888000aaaa9aaaaaaaaa00999a999999999900000000000000000
31103331000000088eeeeeeeeeeeee2800888f8888888800000000000000000000888f88888888000aa999aaaaaaaaa0099a9999999999900000000000000001
11110310000000088eeeeeeeeeeeee2800888f8888888800000000000000000000888f88888888000aaaaaaaaaaaaaa0099aa999999999900000000000010011
311111110000000888eeeeeeeeeee2280088888888888800000000000000000000888888888888000aaaaaaaaaaaaaa009999999999999900000100000011011
1111111000000000882eeeeeeeee22200088888888888800000000000000000000888888888888000aaaaaaaaaaaaaa009999999999999900000000000111333
11111011000000008822eeeeeee222200088888888888800000000000000000000888888888888000aaaaaaaaaaaaaa009999999999999900000010001113333
111100010100000008822eeeee2222050088888888888800000000000000000000888888888888000aaaaaaaaaaaaaa009999999999999900000011113133333
1111000000000000008822222222200500e8888888888e00000000000000000000e8888888888e0007aaaaaaaaaaaa7009999999999999900000000011313113
110110000000000060088222222200650027eeeeeeeee20000000000000000000027eeeeeeeee20009777777777777900f999999999999f00000000000001111
100000000000010066600822222066650002222222222000000000000000000000022222222220000499999999999940147fffffffffff400000000000001111
11000000000000007777700000777775000000000000000000000000000000000000000000000000029999999999992001444444444444000011111000011330
01100030000010000555555555555550000000000000000000000000000000000000000000000000002222222222220000000000000000000001010100110300
011103330001110076666666666666600000000000000000766666666666666000aaaaaaaaaaaa00000000000000000000000000000000000000000010111000
11111131000010006555555555555565000000000000000065555555555555650aaaaaaaaaaaaaa0009999999999990000999999999999000000000110313000
01111111100000006d66666666666d6500088888888880006d66666666666d650aa444aaaaaaaaa0099999999999999009999999999999900000001000030030
31111111000001006d65666666656d6500888888888888006d65666666656d650aaa99aaaaaaaaa0099aa99999999990099aa999999999900000010030303333
33031001000011106d67666666676d650088ff88888888006d67666666676d650aaaa9aaaaaaaaa00999a999999999900999a999999999900000101030333330
30000000000001006d66666666666d6500888f88888888006d66666666666d650aa999aaaaaaaaa0099a999999999990099a9999999999900000000000001000
31000000000000006d6666666666666500888f88888888006d666666666666650aaaaaaaaaaaaaa0099aa99999999990099aa999999999900000001000011100
00000000000001006d66666666666d6500888888888888006d66666666666d650aaaaaaaaaaaaaa0099999999999999009999999999999900000010100101000
00001000000000006666666666666665008888888888880066666666666666650aaaaaaaaaaaaaa0099999999999999009999999999999900000000001110300
00010100000001006d6666666666666500888888888888006d666666666666650aaaaaaaaaaaaaa0099999999999999009999999999999900000000333100000
0100000000000000666d6666666d66650088888888888800666d6666666d66650aaaaaaaaaaaaaa0099999999999999009999999999999900000003033310000
0000000000000000666766666667666500e8888888888e00666766666667666507aaaaaaaaaaaa70099999999999999009999999999999900000000303111000
000001010000000066666666666666650027eeeeeeeee200666666666666666509777777777777900f999999999999f00f999999999999f00000003111111110
01011110000000006666666666666665000222222222200066666666666666650499999999999940047fffffffffff40047fffffffffff400000011111101001
11111010010000007777777777777775000000000000000077777777777777750299999999999920004444444444440000444444444444000000010111100000
01110000011000000555555555555550000000000000000005555555555555500022222222222200000000000000000000000000000000000010011111110000
00101000011110007666666666666660766666666666666076666666666666600000000000000000000000000000000000000000000000000000000111100000
10000000011111006555555555555565655555555555556565555555555555650000000000000000000000000000000000000000000000000000000110000000
31000000011111006d66666666666d656d66666666666d656d66666666666d650000000000000000000888888888800000088888888880000000011110000001
31000000010010006d65666666656d656d65666666656d656d65666666656d650000000000000000008888888888880000888888888888000000000100000011
11100000000000006d67666666676d656d67666666676d656d67666666676d6500000000000000000088ff88888888000088ff88888888000110000000000001
11110000000000006d66666666666d656d66666666666d656d66666666666d65000000000000000000888f888888880000888f88888888000010000000000000
31311110001000006d666666666666656d666666666666656d66666666666665000000000000000000888f888888880000888f88888888000000000000000000
03333111111111006d66666666666d656d66666666666d656d66666666666d650000000000000000008888888888880000888888888888000000000000001010
10300310311111006666666666666665666666666666666566666666666666650000000000000000008888888888880000888888888888000000000000010303
00003033000011006d666666666666656d666666666666656d666666666666650000000000000000008888888888880000888888888888000000100011000033
3003033330300000666d6666666d6665666d6666666d6665666d6666666d66650000000000000000008888888888880000888888888888000031000000000003
3000003000000000666766666667666566676666666766656667666666676665000000000000000000e8888888888e0000e8888888888e000333000000000010
110000000000000066666666666666656666666666666665666666666666666500000000000000000027eeeeeeeee2000027eeeeeeeee2000030001000100111
01000000000100106666666666666665666666666666666566666666666666650000000000000000000222222222200000022222222220000001111101000010
00000000001111117777777777777775777777777777777577777777777777750000000000000000000000000000000000000000000000000011111111100000
00000000000100110555555555555550055555555555555005555555555555500000000000000000000000000000000000000000000000000001001101000000
00000000010000000001000000000000766666666666666000000000000000000000000000000000000000000000000000000000000000000000000000103030
00000000111000010000000000000000655555555555556500000000000000000000000000000000000000000000000000000000000000000000000000000300
100001010100001000bbbbbbbbbbbb006d66666666666d6500bbbbbbbbbbbb000000000000000000000000000000000000000000000000000000000100100111
03033133100000010bbbbbbbbbbbbbb06d65666666656d650bbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000000000113331
33331333100000000bb1111111111bb06d67666666676d650bb1111111111bb00000000000000000000000000000000000000000000000000000000000103031
03001130110000000bb1333333331bb06d66666666666d650bb1333333331bb00000000000000000000000000000000000000000000000000001110000100001
00000101101000000bb1bbbbbbbb1bb06d666666666666650bb1bbbbbbbb1bb00000000000000000000000000000000000000000000000000000111331110001
10000001100011000bb1bbbbbbbb1bb06d66666666666d650bb1bbbbbbbb1bb00000000000000000000000000000000000000000000000000000013333100000
00000000000001000bb1bb77777b1bb066666666666666650bb1bb77777b1bb00000000000000000000000000000000000000000000000000000010331110031
33000000000000000bb3bb17771b3bb06d666666666666650bb3bb17771b3bb00000000000000000000000000000000000000000000000000010010131311111
00000000000100000bbbbbb171bbbbb0666d6666666d66650bbbbbb171bbbbb00000000000000000000000000000000000000000000000000100100333111131
00000010101110000bb3bbbb1bbb3bb066676666666766650bb3bbbb1bbb3bb00000000000000000000000000000000000000000000000000000010111313333
00000111111100010bbbbbbbbbbbbbb066666666666666650bbbbbbbbbbbbbb00000000000000000000000000000000000000000000000000000001111133333
000000130000000006bbbbbbbbbbbb60666666666666666506bbbbbbbbbbbb600000000000000000000000000000000000000000000000000000010111013331
00000000000000000576666666666650777777777777777505766666666666500000000000000000000000000000000000000000000000000000001111001333
10010000000000110055555555555500055555555555555000555555555555000000000000000000000000000000000000000000000000000000001110000133
01111000001101117666666666666660766666666666666076666666666666607666666666666660766666666666666000000000000000000000000100000033
11111000111110106555555555555565655555555555556565555555555555656555555555555565655555555555556500999999999999000000100003310003
11111001111100006d66666666666d656d66666666666d656d66666666666d656d66666666666d656d66666666666d6509999999999999900010111011111000
11100000100000006d65666666656d656d65666666656d656d65666666656d656d65666666656d656d65666666656d65099aa999999999900100011111111113
10000000000010006d67666666676d656d67666666676d656d67666666676d656d67666666676d656d67666666676d650999a999999999900110111001011100
00000000103111006d66666666666d656d66666666666d656d66666666666d656d66666666666d656d66666666666d65099a9999999999900001111110001000
00000031333310006d666666666666656d666666666666656d666666666666656d666666666666656d66666666666665099aa999999999900001111111013000
00001333133330006d66666666666d656d66666666666d656d66666666666d656d66666666666d656d66666666666d6509999999999999900001001011133301
00003331111300006666666666666665666666666666666566666666666666656666666666666665666666666666666509999999999999900000000101133311
00033301100000006d666666666666656d666666666666656d666666666666656d666666666666656d6666666666666509999999999999900000001011113111
0000331100000001666d6666666d6665666d6666666d6665666d6666666d6665666d6666666d6665666d6666666d666509999999999999900000010111111011
00003111000000006667666666676665666766666667666566676666666766656667666666676665666766666667666509999999999999900000100011010111
0101111110000000666666666666666566666666666666656666666666666665666666666666666566666666666666650f999999999999f00000010000000010
131111101000110066666666666666656666666666666665666666666666666566666666666666656666666666666665047fffffffffff400000000000000000
33313111000001007777777777777775777777777777777577777777777777757777777777777775777777777777777500444444444444000000000000000110
33303010000000000555555555555550055555555555555005555555555555500555555555555550055555555555555000000000000000000000110001000011
333300000100000000aaaaaaaaaaaa0000aaaaaaaaaaaa0000000000000000000000000000000000766666666666666000000000000000000001111010110113
33300000010000000aaaaaaaaaaaaaa00aaaaaaaaaaaaaa000000000000000000000000000000000655555555555556500000000000000000000111100010133
33300000100000000aa444aaaaaaaaa00aa444aaaaaaaaa0000888888888800000bbbbbbbbbbbb006d66666666666d6500088888888880000000001010001111
33300001000000000aaa99aaaaaaaaa00aaa99aaaaaaaaa000888888888888000bbbbbbbbbbbbbb06d65666666656d6500888888888888000000033033000111
03000011000000000aaaa9aaaaaaaaa00aaaa9aaaaaaaaa00088ff88888888000bb1111111111bb06d67666666676d650088ff88888888000000003333300011
00000111000000000aa999aaaaaaaaa00aa999aaaaaaaaa000888f88888888000bb1333333331bb06d66666666666d6500888f88888888000011033333300031
00000100000000000aaaaaaaaaaaaaa10aaaaaaaaaaaaaa000888f88888888000bb1bbbb7bbb1bb06d6666666666666500888f88888888000000013101300003
00000000100000000aaaaaaaaaaaaaa11aaaaaaaaaaaaaa000888888888888000bb1bbbb77bb1bb06d66666666666d6500888888888888000000003311130110
00000001000000000aaaaaaaaaaaaaa10aaaaaaaaaaaaaa000888888888888000bb1bbbb777b1bb0666666666666666500888888888888000000003111333000
00010000000000000aaaaaaaaaaaaaa00aaaaaaaaaaaaaa000888888888888000bb3bbbb771b3bb06d6666666666666500888888888888000000000111130010
00000000000000000aaaaaaaaaaaaaa00aaaaaaaaaaaaaa000888888888888000bbbbbbb71bbbbb0666d6666666d666500888888888888000000000111111111
000011000100000007aaaaaaaaaaaa7007aaaaaaaaaaaa7000e8888888888e000bb3bbbb1bbb3bb0666766666667666500e8888888888e000000000001111011
1001100011100000097777777777779009777777777777900027eeeeeeeee2000bbbbbbbbbbbbbb066666666666666650027eeeeeeeee2000000010100111100
011110000110000004999999999999400499999999999940000222222222200006bbbbbbbbbbbb60666666666666666500022222222220000000111110001001
00100100010000000299999999999920029999999999992000000000000000000576666666666650777777777777777500000000100000000011110100000000
01000010110003100022222222222200002222222222220000000000000000000055555555555500055555555555555000000000000000000001010100000000
11100000010033000000000000000000000001111000000100000001110000000000000000000000100000001000000000000100000000010000101110000000
31110000003330010000000000000000000001111000000100000000110000000000000000000011110000000000000000000000000000001000110100003330
11100000033300011001000000000000000011100000001110000001000000000000000000000110100000001000000000000100000000010000001001000303
31010000003000000011100000000000100101000000000110000111100000000000000000000100000000001000000300000100000000000000011101101000
31000000000000000001000000010000000000110000101111001101000000000000000000000110000000000000101000001111031001000000001000011103
31100000000001103000000011110111101101011000010110001110000000000000000000000000000000000000000100000111111110111011000010011133
01000000000000101000001111111111001111110000310000000110000000000000000000000100000000000000003300010001001100011111100111001133
10000000000011000000001011111111101111110003000010001100000000000000110000001110000001100000030110111000000010111111110011100033
00000300000111100000000000011111001111111330000000011100001000011100000000000100000003100000000010110000001103111111111111100011
00000001001111000000000000111100011111113310000000011000011100001000110000000000000031110000000001111000000000101111111131000111
03003311111110000000010000010010001131100111003000111000001000000000011310000000000003101000000010110000000001000111331330000011
30003031301000001011110000110103011111100010033000010000000001000000111130000000000000311100111001000000000000001111133331000000
00003330000000010111111001100000001131000011330000110001000010000000011300000000000000111100111100100010000011011311333333111000

__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00040501010101000004050102050300000402020202090000010201030303000001020202020200000402030001020000040100000203000004010201020100000405020505050000040c0005050500000800020103010000040002000909000004010109090100000401000103020000080109010101000004010201030200
000502020202050000050302010305000001000000000e0000080108030503000008000505050300000805080002010000020c000001020000010001000109000005010002000500000b000100000500000100050d0109000008000300010100000201020502050000050105030202000004030203010100000c00010b010300
000102030302050000010205030102000001000505000200000103010303030000010203000a010000030102000a0500000000010b000900000005000500050000080001000205000000000c000100000002000a040e05000001000a00030200000509050202020000050505000101000000000801090100000008010c000100
0005020303020100000201030502010000010005090002000007010a010a010000010102000a01000008050800020100000000020100000000090102010201000005020d01000a000002010001030100000101050b0502000008000100010100000201010101050000090509000000000001010100020200000502010e050000
0005020202020500000503010205030000010005030002000004030103010200000800050505020000020103000a050000030200000102000000000000000000000503020001050000010200000c000000000000000001000001000a0000010000050205020502000005050505050200000105010a030a000001030205020100
000101010105050000030502010305000008000101000100000801080107010000010204000001000008050800010200000201000a02010000010801020101000005050502050500000201000a02010000050705010a020000080001080005000001010101010100000303010805010000010101000201000005010207020300
__sfx__
0c0e0000232402122024240232202124024220232402122000000232201c24000000232401c2202124023220232402122024240232202124024220232402122000000232201c24000000232401c2202124023220
000e00001006400000100641006410064000001006410064100640000010064100641006400000100641006410064000001006410064100640000010064100641006400000100641006410064000001006410064
250e0000232402122024240232202624024220232402622000000232201c24000000232401c2202124023220232402122024240232202124024220232402122000000232201c24000000232401c2202124023220
000e00000c064000000c0640c0640c064000000c0640c0640c064000000c0640c0640c064000000c0640c0640e064000000e0640e0640e064000000e0640e0640e064000000e0640e0640e064000000e0640e064
210e000017754177500000000000177341773000000000001c7341c7300000000000237342373000000000001e7341e7301f7541f75000000000001f7341f7301f7541f7501e7541e7501f7541f7501e7341e730
210e0000000000000000000000001c7541c7500000000000237542375000000000001e7541e75000000000000000000000000000000000000000000000000000000000000000000000001f7341f7300000000000
210e00001f7341f7300000000000177341773000000000001c7341c7300000000000237342373000000000001e7341e7301a7541a75000000000001a7341a7301a7541a7501c7541c75017754177501c7341c730
210e0000177541775000000000001c7541c7500000000000237542375000000000001e7541e75000000000000000000000000000000000000000000000000000000000000000000000001a7341a7300000000000
080e2000177541775000000000001c7541c7500000000000237542375000000000001e7541e75000000000000000000000000000000000000000000000000000000000000000000000001a7341a7300140001400
010e000018073000003e2153e2110c675000003e2150000018073000003e2113e2110c675000003e2150000018073000003e2153e2110c675000003e2150000018073000003e2113e2110c675000003e21500000
000100001c0501c0501c0501c0501c0401c0401c0301c0301c0201c0201c0101c0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100001405014050140501405014040140401403014030140201402014010140100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200001805016050140501205010050090500705005050030500105000050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300001c5501a5501855015550125500f5500c55009550065500355001550005500055000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
01 09010041
00 09030243
00 09010041
00 09030243
00 09040501
00 09060703
00 09040501
02 09060803

