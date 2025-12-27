pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- bouncing bloob
-- by praghus
------------------------------------------------------------------------------
cartdata("blob_best_times")
-- poke(0x5f2e, 1)
-- pal(0, 129, 1)

-- CORE GAME STATE ----------------------------------------------------------
t = 0
music_on = false
game_state = "title" -- "title", "playing", "won", "lost"
firstinit = true
immortal = false -- debug mode to prevent falling off

-- LEVEL STATE ---------------------------------------------------------------
current_level = 1
next_level = 1
levels = {}
level_time = 0 -- time counter for current level in seconds
level_cleared = false
level_cleared_timer = 0
level_transition = false
level_transition_direction = 0 -- -1 for left, 1 for right
level_transition_new_anims = {}
level_transition_phase = "slide"
level_transition_offset = 0
level_transition_started = false

-- MAP STATE -----------------------------------------------------------------
map_width = 8
map_height = 8
map_tiles = map_width * map_height
tile_size = 16
current_map = {}
old_map = {}
start_x = 0
start_y = 0
tiles_left = 0
total_tiles = 0

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

-- CAMERA & EFFECTS ----------------------------------------------------------
cam_x = 0
cam_y = 0
shake_timer = 0
shake_intensity = 0

-- PARTICLES -------------------------------------------------------------------
particles = {}
max_particles = 140 -- safety cap for particles to avoid FPS drops

-- UI STATE -------------------------------------------------------------------
show_leaderboard = false
title_menu_index = 1
title_fade = 0
title_drop_y = -40
title_drop_vy = 0
title_bounce_done = false
title_anim_timer = 0
leaderboard_anim = 0
progress_flash = 0
record_anim_stage = 0
record_anim_timer = 0
record_anim_x = 0
record_anim_height = 2
tile_respawn_anims = {}
tile_respawn_active = false

-- BEST TIMES -----------------------------------------------------------------
best_times = {} -- stores best time for each level
-------------------------------------------------------------------------------

function _init()
    menuitem(1, "music: " .. (music_on and "on" or "off"), toggle_music)
    menuitem(2, "back to title", return_to_title)

    set_default_palette()
    cls(0)

    if firstinit then
        current_level = 1
        game_state = "title"
        if music_on then
            music(0)
        end
    end
    firstinit = false

    if game_state == "title" then
        return
    end

    reset_map()

    player = create_player(start_x, start_y)
    level_time = 0
    game_state = "playing"
    tiles_left = count_tiles()
    total_tiles = tiles_left
    particles = {}
    tile_respawn_anims = {}
    tile_respawn_active = false
    level_cleared = false
    level_cleared_timer = 0

    init_player_flags(player)
end

function _update()
    t += 0.01
    update_common_effects()
    if game_state == "title" then
        update_title_state()
    elseif game_state == "playing" then
        update_playing_state()
    elseif game_state == "won" then
        update_won_state()
    elseif game_state == "lost" then
        update_lost_state()
    end
end

function _draw()
    if game_state == "title" then
        draw_title_screen()
        return
    end

    local shake_x, shake_y = 0, 0
    if shake_timer > 0 then
        shake_x = rnd(shake_intensity) - shake_intensity / 2
        shake_y = rnd(shake_intensity) - shake_intensity / 2
    end

    camera(0, 0)
    draw_background()
    camera(shake_x + cam_x, shake_y + cam_y)
    draw_board()
    draw_particles(false)

    if is_player_visible(player) then
        draw_player(player, shake_x + cam_x, shake_y + cam_y)
    end

    camera(0, 0)
    draw_gui()
    draw_particles(true)

    if not level_transition then
        draw_messages()
    end
end

-->8
-- STATE MANAGEMENT
-------------------------------------------------------------------------------
function start_game()
    game_state = "playing"
    _init()
    set_level(current_level, true, true)
end

function reset_all_best_times()
    for i = 1, #levels do
        best_times[i] = nil
    end
    save_best_times()
end

function toggle_music()
    music_on = not music_on
    menuitem(1, "music: " .. (music_on and "on" or "off"), toggle_music)
    if music_on then music(0) else music(-1) end
end

function return_to_title()
    restart_game()
end

function restart_game()
    current_level = 1
    game_state = "title"
    title_fade = 0
    title_drop_y = -40
    title_drop_vy = 0
    title_bounce_done = false
    tile_respawn_anims = {}
    tile_respawn_active = false
    title_drop_y = -40
    title_drop_vy = 0
    title_bounce_done = false
    title_anim_timer = 0
end

function handle_level_completion()
    if record_anim_stage > 0 then return end

    level_cleared = false
    level_cleared_timer = 0

    local nextn = current_level + 1
    if nextn > #levels then
        current_level = 1
        game_state = "won"
    else
        set_level(nextn)
    end
end

function handle_player_input()
    if btn(0) then
        player.buffered_dir = 0
        player.input_buffered = true
    elseif btn(1) then
        player.buffered_dir = 1
        player.input_buffered = true
    elseif btn(2) then
        player.buffered_dir = 2
        player.input_buffered = true
    elseif btn(3) then
        player.buffered_dir = 3
        player.input_buffered = true
    else
        player.input_buffered = false
    end
end

-->8
-- UPDATE FUNCTIONS
-------------------------------------------------------------------------------

function update_level_transition()
    -- reset camera during transition
    cam_x, cam_y = 0, 0

    if level_transition_phase == "slide" then
        level_transition_offset = lerp(level_transition_offset, 128 * level_transition_direction, 0.8)
        if abs(level_transition_offset - 128 * level_transition_direction) < 32 then
            level_transition_phase = "fall"
        end
    elseif level_transition_phase == "fall" then
        local all_new_finished = true
        for anim in all(level_transition_new_anims) do
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
            level_transition = false
            level_transition_started = false
            current_level = next_level
            _init()

            -- reset camera after transition
            cam_x, cam_y = 0, 0

            if not player then return end

            local gx, gy = player.grid_x, player.grid_y

            -- if out of map or not on edge -> keep camera centered
            if gx < 0 or gx >= map_width or gy < 0 or gy >= map_height then return end
            if gx ~= 0 and gx ~= map_width - 1 and gy ~= 0 and gy ~= map_height - 1 then return end

            local px, py = tile_to_px(gx, gy)
            local left_margin, right_margin = 24, 128 - 24
            local top_margin, bottom_margin = 24, 128 - 24

            if gx == 0 then
                cam_x = px - left_margin
            elseif gx == map_width - 1 then
                cam_x = px - right_margin
            end

            if gy == 0 then
                cam_y = py - top_margin
            elseif gy == map_height - 1 then
                cam_y = py - bottom_margin
            end

            local max_nudge = 48
            cam_x = clamp(cam_x, -max_nudge, max_nudge)
            cam_y = clamp(cam_y, -max_nudge, max_nudge)
        end
    end
end

function update_common_effects()
    if shake_timer > 0 then shake_timer -= 1 end
    if progress_flash > 0 then
        progress_flash -= 0.32
        if progress_flash < 0 then progress_flash = 0 end
    end
    if level_transition then
        update_level_transition()
        return
    end
    update_particles()
    update_flash_animation()
    update_tile_respawn_animations()
end

function update_particles()
    local to_remove = {}
    for p in all(particles) do
        p.x += p.vx
        p.y += p.vy
        if not p.is_trail then p.vy += 0.1 end
        if p.is_rect then p.rotation += p.rot_speed end
        p.life -= 0.02
        if p.life <= 0 then add(to_remove, p) end
    end
    for p in all(to_remove) do
        del(particles, p)
    end
end

function update_title_state()
    if show_leaderboard and leaderboard_anim < 1 then
        leaderboard_anim = min(1, leaderboard_anim + 0.08)
    elseif not show_leaderboard and leaderboard_anim > 0 then
        leaderboard_anim = max(0, leaderboard_anim - 0.12)
    end

    if not title_menu_index then title_menu_index = 1 end

    if show_leaderboard then
        if btn(4) and btnp(5) then reset_all_best_times() end
        if btnp(5) and not btn(4) then
            show_leaderboard = false
            return
        end
    end

    if not show_leaderboard and title_bounce_done then
        if btnp(2) then
            title_menu_index = max(1, title_menu_index - 1)
        elseif btnp(3) then
            title_menu_index = min(3, title_menu_index + 1)
        end

        if btnp(5) and not btn(4) then
            if title_menu_index == 1 then
                start_game()
            elseif title_menu_index == 2 then
                toggle_music()
            elseif title_menu_index == 3 then
                show_leaderboard = true
            end
        end
    end
end

function update_player_state()
    if player.falling then
        update_player_falling()
    elseif player.moving then
        update_player_moving()
    else
        handle_player_input()
    end
    if is_player_visible(player) then
        update_bounce(player)
    end
end

function update_camera()
    local target_cam_x = cam_x
    local target_cam_y = cam_y

    if not level_transition and player then
        local on_left = (player.grid_x == 0)
        local on_right = (player.grid_x == map_width - 1)
        local on_top = (player.grid_y == 0)
        local on_bottom = (player.grid_y == map_height - 1)

        if on_left or on_right or on_top or on_bottom then
            local px, py = tile_to_px(player.grid_x, player.grid_y)
            local left_margin = 24
            local right_margin = 128 - 24
            local top_margin = 24
            local bottom_margin = 128 - 24

            if on_left then
                target_cam_x = px - left_margin
            elseif on_right then
                target_cam_x = px - right_margin
            end

            if on_top then
                target_cam_y = py - top_margin
            elseif on_bottom then
                target_cam_y = py - bottom_margin
            end

            local max_nudge = 48
            target_cam_x = clamp(target_cam_x, -max_nudge, max_nudge)
            target_cam_y = clamp(target_cam_y, -max_nudge, max_nudge)
        else
            target_cam_x = 0
            target_cam_y = 0
        end
    else
        target_cam_x = 0
        target_cam_y = 0
    end

    local follow_speed = 0.08
    cam_x = lerp(target_cam_x, cam_x, follow_speed)
    cam_y = lerp(target_cam_y, cam_y, follow_speed)

    if abs(cam_x - target_cam_x) < 0.25 then cam_x = target_cam_x end
    if abs(cam_y - target_cam_y) < 0.25 then cam_y = target_cam_y end
end

function update_playing_state()
    if not player then return end
    if level_transition then return end

    if level_cleared then
        level_cleared_timer += 1 / 30
        if level_cleared_timer >= 1 then
            handle_level_completion()
        end
        return
    end

    level_time += 1 / 30

    update_player_state()
    update_camera()
end

function update_player_falling()
    player.fall_timer += 0.08
    if player.fall_timer >= 1 then
        sfx(13)
        game_state = "lost"
    end
end

function update_player_moving()
    player.move_timer += 0.08
    if player.move_timer >= 1 then
        player.moving = false
        player.move_timer = 0
        player.old_x = player.grid_x
        player.old_y = player.grid_y

        if player.grid_x < 0 or player.grid_x >= map_width
                or player.grid_y < 0 or player.grid_y >= map_height then
            if immortal then
                player.grid_x = player.old_x
                player.grid_y = player.old_y
            else
                player.falling = true
                player.fall_timer = 0
            end
        else
            local tile = get_tile(player.grid_x, player.grid_y)
            if tile == 0 then
                if immortal then
                    player.grid_x = player.old_x
                    player.grid_y = player.old_y
                else
                    player.falling = true
                    player.fall_timer = 0
                end
            else
                player.can_hit = true
                player.reached_peak = false
            end
        end
    end
end

function update_flash_animation()
    if record_anim_stage == 0 then return end

    record_anim_timer += 0.08

    if record_anim_stage == 1 then
        record_anim_height = 1
        record_anim_width = 128
        record_anim_x = lerp(0, 128, min(1, record_anim_timer)) -- slide from right to left

        if record_anim_timer >= 0.5 then
            record_anim_stage = 2
            record_anim_timer = 0
        end
    elseif record_anim_stage == 2 then
        record_anim_x = 0
        record_anim_width = 128
        record_anim_height = lerp(16, 1, min(1, record_anim_timer))

        if record_anim_timer >= 0.3 then
            record_anim_stage = 3
            record_anim_timer = 0
        end
    elseif record_anim_stage == 3 then
        record_anim_x = 0
        record_anim_width = 128
        record_anim_height = 11

        if record_anim_timer >= 2 then
            record_anim_stage = 4
            record_anim_timer = 0
        end
    elseif record_anim_stage == 4 then
        record_anim_x = 0
        record_anim_width = 128
        record_anim_height = lerp(1, 16, min(1, record_anim_timer))

        if record_anim_timer >= 0.5 then
            record_anim_stage = 5
            record_anim_timer = 0
        end
    elseif record_anim_stage == 5 then
        record_anim_x = 0
        record_anim_height = 1
        record_anim_width = lerp(0, 128, min(1, record_anim_timer))

        if record_anim_timer >= 0.5 then
            record_anim_stage = 0
            record_anim_timer = 0
        end
    end
end

function update_lost_state()
    if not level_transition then
        center_camera(-14)
    end

    if btnp(5) then reset_level(current_level) end

    if not level_transition_started then
        if btn(4) and btnp(1) then
            set_level(current_level + 1)
        elseif btn(4) and btnp(0) then
            set_level(current_level - 1)
        end
    end
end

function update_won_state()
    center_camera()
    if btnp(5) then
        restart_game()
    end
end

function center_camera(offset_y)
    cam_x = lerp(0, cam_x, 0.2)
    cam_y = lerp(offset_y or 0, cam_y, 0.2)
    if abs(cam_x) < 0.25 then cam_x = 0 end
    if abs(cam_y) < 0.25 then cam_y = 0 end
end

function reset_level(level)
    current_level = level or 1
    lives = 1
    level_time = 0
    particles = {}
    tile_respawn_anims = {}
    tile_respawn_active = false
    game_state = "playing"
    player = create_player(start_x, start_y)
    init_player_flags(player)
    reset_map()
    center_camera()
end

function save_old_map()
    old_map = {}
    for i = 1, map_tiles do
        old_map[i] = levels[current_level][i]
    end
end

function set_level(n, force, skip_slide)
    if not n then return end

    if n > #levels then
        n = 1
    elseif n < 1 then
        n = #levels
    end

    if n == current_level and not force then return end

    level_transition_started = true
    next_level = n
    cam_x, cam_y = 0, 0
    level_transition = true
    tile_respawn_anims = {}
    tile_respawn_active = false
    level_transition_new_anims = {}

    save_old_map()
    trigger_flash_animation(68, "get ready!")

    local ay = 5

    for tx = 0, map_width - 1 do
        for ty = 0, map_height - 1 do
            local idx = ty * map_width + tx + 1
            if levels[next_level][idx] ~= 0 then
                local end_y = ay + ty * tile_size
                local start_y = end_y - tile_size
                add(
                    level_transition_new_anims, {
                        x = tx,
                        y = ty,
                        tile = levels[next_level][idx],
                        timer = -((ty * map_width + tx) * 0.02),
                        start_y = start_y,
                        current_y = start_y,
                        end_y = end_y
                    }
                )
            end
        end
    end
    if skip_slide then
        level_transition_phase = "fall"
        level_transition_offset = 0
        level_transition_direction = 0
    else
        level_transition_phase = "slide"
        level_transition_offset = 0
        level_transition_direction = next_level > current_level and -1 or 1
    end
end

-->8
-- PARTICLE SYSTEM
-------------------------------------------------------------------------------

function create_debris_particles(px, py, col1, col2)
    col2 = col2 or col1
    create_particle(px, py, col1, -2, -2, 1.5, false, true, true)
    create_particle(px, py, col1, 2, -2, 1.5, false, true, true)
    create_particle(px, py, col2, -2, 2, 1.5, false, true, true)
    create_particle(px, py, col2, 2, 2, 1.5, false, true, true)
end

function create_particle(x, y, col, vx, vy, life, is_trail, is_rect, is_ui)
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
    if #particles >= max_particles then
        return
    end
    add(particles, p)
end

function create_simple_particle(x, y, col)
    create_particle(x, y, col, nil, nil, nil, false, false, false)
end

function create_trail(old_gx, old_gy, new_gx, new_gy)
    local old_px, old_py = tile_to_px(old_gx, old_gy)
    local new_px, new_py = tile_to_px(new_gx, new_gy)

    for i = 0, 15 do
        local t = i / 15
        local trail_x = old_px + (new_px - old_px) * t
        local trail_y = old_py + (new_py - old_py) * t

        create_particle(trail_x + rnd(4) - 2, trail_y + rnd(4) - 2, 8, 0, 0, 0.8, true)
    end
end

function draw_particles(only_ui)
    if not game_state == "playing" or level_transition then
        return
    end
    for p in all(particles) do
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
function check_level_completion()
    local prev = tiles_left or count_tiles()
    tiles_left = count_tiles()
    if tiles_left < prev then
        progress_flash = 1
    end
    if tiles_left <= 0 then
        -- level cleared - check for new best time
        check_best_time()
        -- trigger level cleared state
        level_cleared = true
        level_cleared_timer = 0
        particles = {}
        player.grid_x = 0
        player.grid_y = 0
        player.old_x = 0
        player.old_y = 0
        player.moving = false
    end
end

function count_tiles()
    local count = 0
    for i = 1, map_tiles do
        local v = current_map[i]
        -- count only destructible tiles (1,2,3) and teleport tiles
        if v == 1 or v == 2 or v == 3
                or (v >= 7 and v <= 14) then
            count += 1
        end
    end
    return count
end

function get_tile(x, y)
    if x < 0 or x >= map_width or y < 0 or y >= map_height then
        return 0
    end
    local idx = y * map_width + x + 1
    return current_map[idx]
end

function set_tile(x, y, v)
    if x >= 0 and x < map_width and y >= 0 and y < map_height then
        local idx = y * map_width + x + 1
        current_map[idx] = v
    end
end

function reset_map()
    local old_current_map = {}
    if current_map then
        for i = 1, map_tiles do
            old_current_map[i] = current_map[i]
        end
    end

    current_map = {}
    start_x = 0
    start_y = 0
    for i = 1, map_tiles do
        local v = levels[current_level][i]
        -- if tile 4 marks player start, record its position and treat it as platform (id 5)
        if v == 4 then
            local idx0 = i - 1
            start_x = idx0 % map_width
            start_y = flr(idx0 / map_width)
            v = 5
        end
        current_map[i] = v
    end

    -- setup tile respawn animations for tiles that were destroyed
    if old_current_map and #old_current_map > 0 then
        setup_tile_respawn_animations(old_current_map)
    end

    tiles_left = count_tiles()
end

function setup_tile_respawn_animations(old_map)
    tile_respawn_anims = {}
    tile_respawn_active = false

    -- find tiles that were destroyed (present in original level but missing in old_map)
    for i = 1, map_tiles do
        local original_tile = levels[current_level][i]
        local old_tile = old_map[i]

        -- if tile was destructible in original and is now missing/empty
        if (original_tile == 1 or original_tile == 2 or original_tile == 3 or (original_tile >= 7 and original_tile <= 14)) and old_tile == 0 then
            local idx0 = i - 1
            local tx = idx0 % map_width
            local ty = flr(idx0 / map_width)

            -- add to respawn animation list
            local delay = (tx + ty) * 0.06 -- faster sequential animation
            add(
                tile_respawn_anims, {
                    x = tx,
                    y = ty,
                    timer = -delay, -- start with negative timer so first tiles animate immediately
                    target_y = ty * tile_size,
                    current_y = ty * tile_size + 8, -- start 8 pixels below
                    delay = 0 -- no delay needed since we use negative timer
                }
            )
            tile_respawn_active = true
        end
    end
end

-- update tile respawn animations
function update_tile_respawn_animations()
    if not tile_respawn_active then return end

    local all_finished = true

    for anim in all(tile_respawn_anims) do
        -- start animation when timer becomes positive (staggered start)
        if anim.timer >= 0 then
            anim.current_y = lerp(anim.target_y, anim.current_y, 0.5)

            -- check if animation is close to finished
            if abs(anim.current_y - anim.target_y) > 0.5 then
                all_finished = false
            end
        else
            all_finished = false
        end

        anim.timer += 1 / 30 -- increment based on frame rate
    end

    -- if all animations finished, clear the system
    if all_finished then
        tile_respawn_active = false
        tile_respawn_anims = {}
    end
end

function update_bounce(p)
    -- save previous bounce value for bounce detection
    local prev_bounce = p.prev_bounce or 0

    -- if ball is falling, animate fall (zoom only)
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
                -- create_trail(p.old_x, p.old_y, nx, ny)
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
                local tile = get_tile(p.grid_x, p.grid_y)
                if tile == 0 then
                    if not immortal then
                        -- empty tile - start falling (no bounce sound!)
                        p.falling = true
                        p.fall_timer = 0
                    else
                        sfx(11)
                    end
                else
                    -- tile exists - check if it's a teleport tile (new ids 7..14)
                    if tile >= 7 and tile <= 14 then
                        -- teleport tile - hit it and start teleport animation
                        sfx(11)
                        hit_tile(p.grid_x, p.grid_y)
                        -- calculate teleport destination
                        local nx2, ny2 = p.grid_x, p.grid_y
                        -- new directional teleport ids (7..14), clockwise from up=7
                        if tile == 10 then
                            nx2 = p.grid_x - 2 -- left (2 tiles)
                        elseif tile == 8 then
                            nx2 = p.grid_x + 2 -- right (2 tiles)
                        elseif tile == 9 then
                            ny2 = p.grid_y + 2 -- down (2 tiles)
                        elseif tile == 7 then
                            ny2 = p.grid_y - 2 -- up (2 tiles)
                        elseif tile == 14 then
                            nx2 = p.grid_x - 1 -- up-left (diag)
                            ny2 = p.grid_y - 1
                        elseif tile == 11 then
                            nx2 = p.grid_x + 1 -- up-right (diag)
                            ny2 = p.grid_y - 1
                        elseif tile == 13 then
                            nx2 = p.grid_x - 1 -- down-left (diag)
                            ny2 = p.grid_y + 1
                        elseif tile == 12 then
                            nx2 = p.grid_x + 1 -- down-right (diag)
                            ny2 = p.grid_y + 1
                        end
                        -- start animated teleport movement
                        p.old_x = p.grid_x
                        p.old_y = p.grid_y
                        p.grid_x = nx2
                        p.grid_y = ny2
                        p.moving = true
                        p.move_timer = 0
                        -- create trail for teleport
                        create_trail(p.old_x, p.old_y, nx2, ny2)
                        -- block until next cycle and reset peak
                        p.can_hit = false
                        p.reached_peak = false
                    else
                        -- normal tile - hit it with bounce sound
                        sfx(11)
                        hit_tile(p.grid_x, p.grid_y)
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

function handle_teleport(x, y, particle_col1, particle_col2)
    local px, py = tile_to_px(x, y)
    local world_px = px - cam_x
    local world_py = py - cam_y
    trigger_shake()
    sfx(12)
    set_tile(x, y, 0)
    create_debris_particles(world_px, world_py, particle_col1, particle_col2)
    check_level_completion()
end

function hit_tile(x, y)
    local tile = get_tile(x, y)
    if tile == 7 then
        handle_teleport(x, y, 11, 3) -- up
        return
    elseif tile == 11 then
        handle_teleport(x, y, 12, 1) -- up-right
        return
    elseif tile == 8 then
        handle_teleport(x, y, 11, 3) -- right
        return
    elseif tile == 12 then
        handle_teleport(x, y, 12, 1) -- down-right
        return
    elseif tile == 9 then
        handle_teleport(x, y, 11, 3) -- down
        return
    elseif tile == 13 then
        handle_teleport(x, y, 12, 1) -- down-left
        return
    elseif tile == 10 then
        handle_teleport(x, y, 11, 3) -- left
        return
    elseif tile == 14 then
        handle_teleport(x, y, 12, 1) -- up-left
        return
    end

    -- tiles 1,2,3 can be hit (5 is permanent platform)
    -- destructible tiles have values 1,2,3 (representing 1..3 hits)
    if tile == 1 or tile == 2 or tile == 3 then
        trigger_shake()
        local px, py = tile_to_px(x, y)
        for i = 1, 8 do
            local col = rnd(1) > 0.5 and 10 or 9
            create_simple_particle(px, py, col)
        end

        sfx(12)

        local new_tile = tile - 1
        if new_tile <= 0 then
            set_tile(x, y, 0)
            local world_px = px - cam_x
            local world_py = py - cam_y
            create_debris_particles(world_px, world_py, 8)
            check_level_completion()
        else
            set_tile(x, y, new_tile)
            sfx(11)
        end
    end
end

function get_teleport_anim_sprite(tile)
    local anim_frame = flr((t * 24) % 6)
    if tile == 10 then
        return 80 + anim_frame -- left
    elseif tile == 8 then
        return 64 + anim_frame -- right
    elseif tile == 9 then
        return 112 + anim_frame -- down
    elseif tile == 7 then
        return 96 + anim_frame -- up
    elseif tile == 14 then
        return 102 + anim_frame -- up-left
    elseif tile == 11 then
        return 86 + anim_frame -- up-right
    elseif tile == 13 then
        return 118 + anim_frame -- down-left
    elseif tile == 12 then
        return 70 + anim_frame -- down-right
    end
    return 0
end

-->8
-- DRAWS
-------------------------------------------------------------------------------
function draw_player(p, camx, camy)
    camx = camx or 0
    camy = camy or 0

    local px, py = compute_ball_screen_pos(p)
    local s = ball_render_size(p)
    local ball_y = py + (p.offset_y or 0) - s / 2

    draw_player_shadow(p, 7, 11)

    if s > 0.5 then
        draw_ball(px, ball_y, s)
    end
end

function draw_player_shadow(p, center_x, center_y)
    if p.falling then return end
    local tile = get_tile(p.grid_x, p.grid_y)
    if tile ~= 0 and (p.w or 0) <= 7 then
        circfill(p.grid_x * tile_size + center_x, p.grid_y * tile_size + center_y, 4, 5)
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

function draw_tile_with_anim(tile, x, y)
    local draw_tile = tile == 4 and 42 or tile
    if draw_tile >= 7 and draw_tile <= 14 then
        local bg_tile = (draw_tile >= 11 and draw_tile <= 14) and teleport2_bg_sprite or teleport1_bg_sprite
        draw_tile_sprite(bg_tile, x, y)
        local icon_sprite = get_teleport_anim_sprite(draw_tile)
        spr(icon_sprite, x + 4, y + 4)
    else
        draw_tile_sprite(map_tile_to_sprite(draw_tile), x, y)
    end
end

function draw_board()
    local ay = 4

    -- draw a map with offset
    local function draw_map(map_data, x_offset, y_offset)
        y_offset = y_offset or 0
        for tx = 0, map_width - 1 do
            local base_x = tx * tile_size + x_offset
            -- early skip if entire column is off screen
            if base_x > -tile_size and base_x < 128 then
                for ty = 0, map_height - 1 do
                    local idx = ty * map_width + tx + 1
                    local s = map_data[idx]
                    if s ~= 0 then
                        local yy = ay + ty * tile_size + y_offset
                        local animated_y = yy
                        local should_draw = true
                        if tile_respawn_active then
                            for anim in all(tile_respawn_anims) do
                                if anim.x == tx and anim.y == ty then
                                    animated_y = ay + anim.current_y
                                    -- only draw tile if its animation has started (timer >= 0)
                                    should_draw = anim.timer >= 0
                                    break
                                end
                            end
                        end

                        if should_draw then
                            draw_tile_with_anim(s, base_x, animated_y)
                        end
                    end
                end
            end
        end
    end

    -- draw background circle in the middle
    circfill(64 - cam_x, 64 - cam_y, 42, 0)

    if level_transition then
        if level_transition_phase == "slide" then
            draw_map(old_map, level_transition_offset)
        elseif level_transition_phase == "fall" then
            for anim in all(level_transition_new_anims) do
                if anim.timer >= 0 and anim.tile and anim.tile ~= 0 then
                    local base_x = anim.x * tile_size
                    draw_tile_with_anim(anim.tile, base_x, anim.current_y)
                end
            end
        end
    else
        -- normal drawing (no transition)
        draw_map(current_map, 0)
    end
end

function draw_gui()
    rectfill(0, 0, 128, 9, 0)
    -- -- rectfill(0, 119, 128, 128, 0)
    -- -- line(0, 8, 128, 8, 1)
    -- rect(0, 9, 127, 127, 1)
    -- rect(1, 10, 126, 126, 0)

    local display_level = (level_transition and next_level) or current_level
    local level_text = "level " .. display_level
    print(level_text, 2, 3, 1)
    print(level_text, 2, 2, 6)

    local time_text = (level_transition and "00:00") or format_time(level_time)
    local time_width = #time_text * 4
    print(time_text, 128 - time_width - 2, 3, 1)
    print(time_text, 128 - time_width - 2, 2, 6)

    spr(128, 96, 1)
end

function draw_title_screen()
    local title_x, title_y = 33, 26
    local menu_x, menu_y = 64, title_y + 46
    local menu_spacing = 9
    local pulse = sin(t * 2) * 0.5 + 0.5

    if title_bounce_done then
        rectfill(14, 14, 112, 112, 0)
        draw_background()
    else
        cls()
    end

    title_anim_timer = (title_anim_timer or 0) + 1 / 30

    if not show_leaderboard then
        rectfill(20, 20, 106, 106, 0)
        title_fade = mid(0, (title_fade or 0) + 0.05, 2)

        if title_bounce_done == nil then title_bounce_done = false end
        if not title_bounce_done then
            title_drop_vy = (title_drop_vy or 0) + 0.9 -- gravity
            title_drop_y = (title_drop_y or -40) + title_drop_vy
            if title_drop_y >= 0 then
                title_drop_y = 0
                title_drop_vy = -title_drop_vy * 0.45 -- bounce with damping
                if abs(title_drop_vy) < 0.6 then
                    title_drop_vy = 0
                    title_bounce_done = true
                end
            end
        end
        local cur_y = title_y + (title_drop_y or 0)

        if title_fade < 1 then
            if title_fade < 0.33 then
                for c = 1, 15 do
                    pal(c, 0)
                end
            elseif title_fade < 0.66 then
                for c = 1, 15 do
                    pal(c, (c == 8 or c == 2 or c == 1) and 0 or 1)
                end
            elseif title_fade < 0.77 then
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

        set_default_palette()

        if title_bounce_done then
            local delay, flash_dur = 0.6, 0.8
            if title_anim_timer >= delay then
                rect(20, 20, 106, 106, title_anim_timer >= 0.75 and 1 or 0)
                local ft = title_anim_timer - delay
                if ft < flash_dur then
                    local pulse = sin(t * 20)
                    local col = pulse > 0 and 7 or 10
                    print_centered("BOUNCING", cur_y - 8, col, 4)
                    print_centered("BY PRAgHUS", cur_y + 33, col, 4)
                else
                    print_centered("BOUNCING", cur_y - 8, 10, 4)
                    print_centered("BY PRAgHUS", cur_y + 33, 10, 4)
                end
            end
            print("V1.1", 110, 120, 6)

            if not title_menu_index then title_menu_index = 1 end
            local items = {
                "start",
                (music_on and "music: on" or "music: off"),
                "best times"
            }
            if title_anim_timer >= 0.6 then
                for i = 1, #items do
                    local yy = menu_y + (i - 1) * menu_spacing
                    if i == title_menu_index and title_anim_timer >= 1.1 then
                        rectfill(menu_x - 32, yy - 2, menu_x + 32, yy + 6, title_anim_timer >= 1.2 and 8 or 2)
                        print_centered(items[i], yy, 7)
                    else
                        print_centered(items[i], yy, title_anim_timer >= 0.7 and 6 or 1)
                    end
                end
            end
        end
    end

    if leaderboard_anim > 0 then
        draw_leaderboard()
    end
end

function draw_leaderboard()
    local board_width = 100
    local board_height = 100
    local board_x = (128 - board_width) / 2
    local board_y = (128 - board_height) / 2 - (board_height * (1 - leaderboard_anim))
    local k = flr(2 * cos(t * 4))

    rectfill(board_x + k, board_y + k, board_x + board_width + 0.9999 - k, board_y + board_height + 0.9999 - k, 0)
    rect(board_x + k, board_y + k, board_x + board_width + 0.9999 - k, board_y + board_height + 0.9999 - k, 1)

    local col_width = board_width / 2
    local start_x1 = board_x + 8
    local start_x2 = board_x + col_width + 8
    local start_y = board_y + 20
    local row_height = 8
    local levels_per_column = 8

    local total_levels = #levels
    local max_display = min(total_levels, levels_per_column * 2)
    local bt = best_times

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
    print_centered("press \x83 to close", board_y + board_height - 12, 6, 1)
end

function draw_background()
    rectfill(16 - cam_x, 16 - cam_y, 114 - cam_x, 116 - cam_y, 0)
    for i = 0, 999 do
        local x, y = rnd(128), rnd(128)
        local c = pget(x, y)
        local plt = game_state == "title" and palette[0] or palette[current_level % #palette + 1]
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

function draw_messages()
    local pulse = 0.5 + 0.5 * sin(t * 4)
    local color = 7 + flr(pulse * 3)

    -- local pulse = sin(t * 2) * 0.5 + 0.5
    -- local color = flr(pulse * 6) + 8

    if level_cleared and level_cleared_timer < 5 then
        local time_text = "time: " .. format_time(level_time)
        local text1 = "level cleared!"
        local best_time = best_times[current_level]
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
    elseif game_state == "won" then
        rectfill(0, 50, 128, 70, 0)
        print_centered("all levels complete!", 54, 11)
        print_centered("press \x97 to restart", 62, 7)
    elseif game_state == "lost" then
        rectfill(0, 0, 128, 8, 1)
        print_centered("press \x8e+<> to level skip", 2, 6, 0)
        print_centered("press \x97 to restart", 20, color, 0)
    end
    draw_flash_animation()
end

function draw_flash_animation()
    if record_anim_stage == 0 then return end

    local y_center = record_anim_y_center or 64
    local y_pos = y_center - record_anim_height / 2

    local rect_color = 7
    if record_anim_stage == 3 then
        rect_color = 0
    end

    rectfill(record_anim_x, y_pos, record_anim_x + record_anim_width - 1, y_pos + record_anim_height - 1, rect_color)

    if record_anim_stage == 3 then
        local text = record_anim_text
        local text_width = #text * 4
        -- local text_x = record_anim_x + (record_anim_width - text_width) / 2
        local text_y = y_center - 3 -- center text vertically

        if record_anim_height >= 8 and record_anim_width >= text_width then
            -- rainbow color cycling effect
            local color_cycle = sin(t * 8) * 3 + 3 -- cycles through colors 0-6
            local text_color = flr(color_cycle) + 8 -- colors 8-14 (bright colors)
            if text_color > 14 then text_color = 8 + (text_color - 15) end
            print_centered(text, text_y, text_color)
        end
    end
end

function draw_tile_sprite(base_sprite, x, y)
    spr(base_sprite, x, y)
    spr(base_sprite + 1, x + 8, y)
    spr(base_sprite + 16, x, y + 8)
    spr(base_sprite + 17, x + 8, y + 8)
end

-->8
-- HELPERS AND UTILS
-------------------------------------------------------------------------------
function lerp(a, b, i) return i * a + (1 - i) * b end
function clamp(a, mi, ma) return min(max(a, mi), ma) end
function map_tile_to_sprite(id) return tile_sprite_map[id] or id end
function tile_to_px(x, y) return 0 + x * tile_size + 8, y * tile_size + 8 end
function ball_render_size(p) return (p and (p.w or 0) or 0) / 1.8 end
function set_default_palette() pal() end

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

function trigger_shake()
    shake_timer = 6
    shake_intensity = 2
end

-- build levels from native map using mget
function load_levels_from_native_map()
    -- number of blocks that fit horizontally and vertically
    local blocks_x = 128 / map_width
    local blocks_y = flr(32 / map_height)

    for by = 0, blocks_y - 1 do
        for bx = 0, blocks_x - 1 do
            local ox = bx * map_width
            local oy = by * map_height
            local lvl = {}
            local is_empty = true
            for y = 0, map_height - 1 do
                for x = 0, map_width - 1 do
                    local v = mget(ox + x, oy + y)
                    add(lvl, v)
                    if v ~= 0 then is_empty = false end
                end
            end
            -- only add non-empty maps so empty slots in __map__ are ignored
            if not is_empty then
                add(levels, lvl)
            end
        end
    end
end

function save_best_times()
    for i = 1, min(#levels, 63) do
        -- dget/dset supports indices 0-63, save 0 for metadata
        if best_times[i] then
            dset(i, best_times[i])
        else
            dset(i, -1) -- use -1 to indicate no time set
        end
    end
    -- save number of levels in slot 0 as metadata
    dset(0, #levels)
end

function load_best_times()
    best_times = {}
    local saved_levels = dget(0)

    if saved_levels > 0 then
        for i = 1, min(saved_levels, 63) do
            local saved_time = dget(i)
            if saved_time >= 0 then
                -- -1 means no time was saved
                best_times[i] = saved_time
            end
        end
    end
end

function check_best_time()
    local current_time = level_time
    local level_idx = current_level

    if not best_times[level_idx] or current_time < best_times[level_idx] then
        best_times[level_idx] = current_time
        trigger_flash_animation(90)
        save_best_times()
        return true
    end

    return false
end

function trigger_flash_animation(y_offset, text)
    -- don't restart if animation is already playing
    if record_anim_stage > 0 then return end
    record_anim_stage = 1
    record_anim_timer = 0
    record_anim_x = 128
    record_anim_height = 1
    record_anim_y_center = y_offset or 64
    record_anim_width = 128
    record_anim_text = text or "new record!"
end

function is_showing_messages()
    return (level_cleared and level_cleared_timer < 5)
            or game_state == "won"
            or game_state == "lost"
            or record_anim_stage > 0
end

function is_ball_drawn(p)
    if not p then return false end
    local s = (p.w or 0) / 1.8
    return s > 0.5
end

function is_player_visible(p)
    return p and not level_cleared and not level_transition and not is_showing_messages() and is_ball_drawn(p)
end

function compute_ball_screen_pos(p)
    local center_x, center_y = 7, 11
    local render_x, render_y
    if p.falling then
        render_x = p.grid_x
        render_y = p.grid_y
    elseif p.moving then
        local t = p.move_timer
        local ease_t = 1 - (1 - t) * (1 - t)
        render_x = p.old_x + (p.grid_x - p.old_x) * ease_t
        render_y = p.old_y + (p.grid_y - p.old_y) * ease_t
    else
        render_x = p.grid_x
        render_y = p.grid_y
    end

    local px = render_x * tile_size + center_x
    local py = render_y * tile_size + center_y
    return px, py, render_x, render_y, center_x, center_y
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

-->8
-- INITIALIZATION
-------------------------------------------------------------------------------
function create_player(x, y)
    local p = {
        grid_x = x, -- tile position (target position)
        grid_y = y,
        old_x = x, -- previous position (for interpolation)
        old_y = y,
        moving = false, -- is ball moving
        move_timer = 0, -- timer for movement animation (0 to 1)
        w = 4, -- ball size (will animate 4-16)
        offset_y = 0, -- Y offset for animation (0 down, -4 up)
        bounce_timer = 0 -- timer for bounce animation
    }
    return p
end

function init_player_flags(p)
    p.can_move = false
    p.input_buffered = false
    p.buffered_dir = 0
    p.can_hit = true
    p.prev_size = 4
    p.reached_peak = false
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

function init_best_times()
    -- load saved times from cartridge data first
    load_best_times()
    -- if no saved data, initialize with nil
    for i = 1, #levels do
        if not best_times[i] then
            best_times[i] = nil -- no best time initially
        end
    end
end

load_levels_from_native_map()
init_background_palette()
init_best_times()

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
000000000000000000999999999999000aaaaaaaaaaaaaa0000000000000000000000000000000006555555555555560ddddddddddddddd1666666666666666d
000888888888800009999999999999900aa444aaaaaaaaa000cccccccccccc0000bbbbbbbbbbbb006d66666666666d60ddddddddddddddd1666666666666666d
0088888888888800099aa999999999900aaa99aaaaaaaaa00cccccccccccccc00bbbbbbbbbbbbbb06d65666666656d60dddd5ddddd5dddd1666d66666666d66d
0088ff88888888000999a999999999900aaaa9aaaaaaaaa00cc1111111111cc00bb1111111111bb06d67666666676d60ddd516ddd516ddd1666766666666766d
00888f8888888800099a9999999999900aa999aaaaaaaaa00cc1dddddddd1cc00bb1333333331bb06d66666666666d60dddd6ddddd6dddd1666666666666666d
00888f8888888800099aa999999999900aaaaaaaaaaaaaa00cc1cccccccc1cc00bb1bbbbbbbb1bb06d66666666666660ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc1cccccccc1cc00bb1bbbbbbbb1bb06d66666666666d60ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc1cccccccc1cc00bb1bbbbbbbb1bb06666666666666660ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc5cccccccc5cc00bb3bbbbbbbb3bb06d66666666666660dddd5ddddd5dddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cccccccccccccc00bbbbbbbbbbbbbb0666d6666666d6660ddd516ddd516ddd1666666666666666d
00e8888888888e00099999999999999007aaaaaaaaaaaa700cc5cccccccc5cc00bb3bbbbbbbb3bb06667666666676660dddd6ddddd6dddd1666d66666666d66d
0027eeeeeeeee2000f999999999999f009777777777777900cccccccccccccc00bbbbbbbbbbbbbb06666666666666660ddddddddddddddd1666766666666766d
0002222222222000047fffffffffff4004999999999999400dccccccccccccd006bbbbbbbbbbbb6066666666666666606ddddddddddddd61766666666666667d
000000000000000000444444444444000299999999999920056ddddddddddd500576666666666650d7777777777777501666666666666610d7777777777777dd
00000000000000000000000000000000002222222222220000555555555555000055555555555500055555555555550001111111111111000dddddddddddddd0
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

