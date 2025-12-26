pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- bouncing bloob
-- by praghus
------------------------------------------------------------------------------
cartdata("blob_best_times") -- initialize cartdata storage for best times
pal(0, 129, 1)
-- CORE GAME STATE ----------------------------------------------------------
t = 0
lives = 3
game_state = "title" -- "title", "playing", "won", "lost"
firstinit = true
immortal = false -- debug mode to prevent falling off
show_numbers = false

-- LEVEL STATE ---------------------------------------------------------------
current_level = 1
next_level = 1
levels = {}
level_time = 0 -- time counter for current level in seconds
level_cleared = false
level_cleared_timer = 0
level_transition = false
level_transition_timer = 0
level_transition_direction = 0 -- -1 for left, 1 for right
level_skip = true -- enable level skipping with Z+arrows

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
star_count = 50
tile_sprite_map = { [1] = 32, [2] = 34, [3] = 36, [5] = 42 }
teleport1_bg_sprite = 40
teleport2_bg_sprite = 38
palette = {
    [0] = { 0, 1, 2, 1, 2, 8 },
    [1] = { 0, 1, 5, 1, 5 },
    [2] = { 0, 1, 4, 1, 4 },
    [3] = { 0, 1, 3, 1, 3 },
    [4] = { 0, 1, 2, 1, 2 }
}

-- CAMERA & EFFECTS ----------------------------------------------------------
cam_x = 0
cam_y = 0
shake_timer = 0
shake_intensity = 0
particles = {}
max_particles = 140 -- safety cap for particles to avoid FPS drops
progress_flash = 0
prev_progress = 0

-- AUDIO ----------------------------------------------------------------------
music_on = false

-- UI STATE -------------------------------------------------------------------
show_leaderboard = false -- flag for leaderboard visibility
leaderboard_anim = 0 -- animation progress for leaderboard slide-in (0-1)
reset_feedback = false -- flag for reset confirmation message
reset_feedback_timer = 0 -- timer for reset feedback
title_menu_index = 1 -- selected menu item on title screen (1=start,2=music,3=best times)

-- ANIMATIONS -----------------------------------------------------------------
record_anim_stage = 0 -- 0=hidden, 1=expanding, 2=flash, 3=showing, 4=shrinking
record_anim_timer = 0
record_anim_x = 0
record_anim_height = 2
-- tile respawn animation
tile_respawn_anims = {} -- array of {x, y, timer, target_y} for animating tiles
tile_respawn_active = false -- flag indicating if respawn animation is playing

-- BEST TIMES -----------------------------------------------------------------
best_times = {} -- stores best time for each level

-------------------------------------------------------------------------------
global = _ENV

function _init()
    stars = {}
    star_types = {
        star,
        near_star,
        far_star
    }

    for i = 1, star_count do
        local star_type = rnd(star_types)
        add(
            stars, star_type:new({
                x = rnd(127),
                y = rnd(127)
            })
        )
    end

    -- game initialization - only on first run
    if firstinit then
        cls()
        current_level = 1
        lives = 3
        game_state = "title"
        if music_on then
            music(0)
        end
    end
    firstinit = false

    if game_state == "title" then
        return
    end

    cls(0)

    game_state = "playing"

    -- create working copy of level
    reset_map()

    -- create player at start position (tile id 4 converted to platform id 5 in reset_map)
    player = create_player(start_x, start_y)

    -- variable to control input at jump peak
    init_player_flags(player)

    -- reset level time
    level_time = 0

    -- tile counter to clear
    tiles_left = count_tiles()
    total_tiles = tiles_left
    if total_tiles > 0 then
        prev_progress = tiles_left / total_tiles
    else
        prev_progress = 0
    end

    -- clear particles
    particles = {}

    -- reset tile animations
    tile_respawn_anims = {}
    tile_respawn_active = false

    -- reset level cleared state
    level_cleared = false
    level_cleared_timer = 0
end

function _update()
    t += 0.01

    -- update common timers and effects
    update_common_effects()

    -- state-specific updates
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
    -- apply camera shake
    local shake_x, shake_y = 0, 0
    if shake_timer > 0 then
        shake_x = rnd(shake_intensity) - shake_intensity / 2
        shake_y = rnd(shake_intensity) - shake_intensity / 2
    end

    -- reset camera for background
    camera(0, 0)
    draw_background()

    if game_state == "title" then
        draw_title_screen()
        return
    end

    camera(shake_x + cam_x, shake_y + cam_y)
    draw_board()
    draw_particles(false)

    local showing_messages = (level_cleared and level_cleared_timer < 5)
            or game_state == "won"
            or game_state == "lost"
            or record_anim_stage > 0

    if player and not level_cleared and not level_transition and not showing_messages then
        draw_player(player, shake_x + cam_x, shake_y + cam_y)
    end

    -- reset camera for UI
    camera(0, 0)
    draw_gui()
    -- UI particles
    draw_particles(true)
    draw_messages()
end

-- update common visual effects and timers
function update_common_effects()
    for star in all(stars) do
        star:update()
    end
    -- progress flash effect
    if progress_flash > 0 then
        progress_flash -= 0.32
        if progress_flash < 0 then progress_flash = 0 end
    end

    -- camera shake
    if shake_timer > 0 then
        shake_timer -= 1
    end

    -- animations
    update_record_animation()
    update_tile_respawn_animations()

    -- reset feedback timer
    if reset_feedback and reset_feedback_timer < 1.5 then
        reset_feedback_timer += 1 / 30 -- 30fps
        if reset_feedback_timer >= 1.5 then
            reset_feedback = false
        end
    end
end

-- handle title screen state
function update_title_state()
    -- leaderboard animation
    if show_leaderboard and leaderboard_anim < 1 then
        leaderboard_anim = min(1, leaderboard_anim + 0.08)
    elseif not show_leaderboard and leaderboard_anim > 0 then
        leaderboard_anim = max(0, leaderboard_anim - 0.12)
    end
    -- reset records (Z+X)
    if show_leaderboard and btn(4) and btnp(5) then
        reset_all_best_times()
    end

    -- ensure menu index exists
    if not title_menu_index then title_menu_index = 1 end

    -- when leaderboard visible, allow closing it with O (btnp(3)) or X (btnp(5))
    if show_leaderboard then
        -- close leaderboard with O (btnp(3))
        if btnp(3) then
            show_leaderboard = false
            return
        end
        -- close leaderboard with X (btnp(5)) if not holding modifier (btn(4))
        if btnp(5) and not btn(4) then
            show_leaderboard = false
            return
        end
    end

    -- title navigation when leaderboard hidden
    if not show_leaderboard then
        -- navigate title menu with up/down
        if btnp(2) then
            title_menu_index = max(1, title_menu_index - 1)
        elseif btnp(3) then
            title_menu_index = min(3, title_menu_index + 1)
        end

        -- confirm/activate selection with X (btnp(5))
        if btnp(5) and not btn(4) then
            if title_menu_index == 1 then
                -- start
                start_game()
            elseif title_menu_index == 2 then
                -- toggle music
                toggle_music()
            elseif title_menu_index == 3 then
                -- show leaderboard
                show_leaderboard = true
            end
        end
    end
end

-- HELPER FUNCTIONS FOR STATE MANAGEMENT ------------------------------------

function reset_all_best_times()
    for i = 1, #levels do
        best_times[i] = nil
    end
    save_best_times()
    reset_feedback = true
    reset_feedback_timer = 0
end

function toggle_music()
    music_on = not music_on
    if music_on then
        music(0)
    else
        music(-1)
    end
end

function start_game()
    game_state = "playing"
    _init()
end

function restart_game()
    current_level = 1
    lives = 3
    game_state = "title"

    -- reset tile animations
    tile_respawn_anims = {}
    tile_respawn_active = false
end

function handle_level_completion()
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

function handle_level_skip_input()
    if btn(4) and btnp(1) then
        set_level(current_level + 1)
    elseif btn(4) and btnp(0) then
        set_level(current_level - 1)
    end
end

function update_level_transition()
    level_transition_timer += 0.08
    if level_transition_timer < 1 then return end

    level_transition = false
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

function update_player_state()
    if player.falling then
        update_player_falling()
    elseif player.moving then
        update_player_moving()
    else
        handle_player_input()
    end

    update_bounce(player)
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

-- PLAYER UPDATE FUNCTIONS ---------------------------------------------------

function update_playing_state()
    if not player then return end

    -- level cleared handling
    if level_cleared then
        level_cleared_timer += 1 / 30
        if level_cleared_timer >= 1 then
            handle_level_completion()
        end
        return -- skip other logic during level cleared
    end

    -- update level time
    level_time += 1 / 30

    -- level switching with Z+arrows
    if level_skip and not level_transition then
        handle_level_skip_input()
    end

    -- level transition animation
    if level_transition then
        update_level_transition()
        return
    end

    -- update particles and player
    update_particles()
    update_player_state()
    update_camera()
end

function update_player_falling()
    player.fall_timer += 0.08
    if player.fall_timer >= 1 then
        sfx(13)
        lives -= 1
        if lives <= 0 then
            game_state = "lost"
        else
            reset_map()
            cam_x = 0
            cam_y = 0
            level_time = 0
            player = create_player(start_x, start_y)
            init_player_flags(player)
            particles = {}
        end
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

function center_camera()
    -- smoothly return camera to center
    cam_x = lerp(0, cam_x, 0.2)
    cam_y = lerp(0, cam_y, 0.2)
    if abs(cam_x) < 0.25 then cam_x = 0 end
    if abs(cam_y) < 0.25 then cam_y = 0 end
end

function update_won_state()
    center_camera()
    if btnp(5) then
        restart_game()
    end
end

function update_lost_state()
    center_camera()
    if btnp(4) then
        lives = 3
        game_state = "playing"
        set_level(current_level + 1)
    end
    if btnp(5) then
        restart_game()
    end
end

-- helper function to save current map
function save_old_map()
    old_map = {}
    for i = 1, map_tiles do
        old_map[i] = current_map[i]
    end
end

-- helper function to save current map
function set_level(n)
    if not n then return end

    if n > #levels then
        n = 1
    elseif n < 1 then
        n = #levels
    end

    if n == current_level then return end

    next_level = n
    -- determine animation direction: slide right if new > current
    if next_level > current_level then
        level_transition_direction = 1
    else
        level_transition_direction = -1
    end
    level_transition = true
    level_transition_timer = 0
    save_old_map()

    -- reset tile animations when changing levels
    tile_respawn_anims = {}
    tile_respawn_active = false
end

-- helper function to initialize player flags
function init_player_flags(p)
    p.can_move = false
    p.input_buffered = false
    p.buffered_dir = 0
    p.can_hit = true
    p.prev_size = 4
    p.reached_peak = false
end

-- helper function to create 4 debris particles in cardinal directions
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
    -- enforce particle cap to avoid huge slowdowns
    if #particles >= max_particles then
        return
    end
    add(particles, p)
end

-- helper for simple particles with default values
function create_simple_particle(x, y, col)
    create_particle(x, y, col, nil, nil, nil, false, false, false)
end

-- helper function to check if level is completed
function check_level_completion()
    -- recalc tile counter and flash if progress increased
    local prev = tiles_left or count_tiles()
    tiles_left = count_tiles()
    if tiles_left < prev then
        progress_flash = 1
    end
    if tiles_left <= 0 then
        -- level cleared - check for new best time
        check_best_time()
        -- show message and prepare for transition
        level_cleared = true
        level_cleared_timer = 0
        -- clear all particles for clean transition
        particles = {}
        -- reset player position to start immediately
        player.grid_x = 0
        player.grid_y = 0
        player.old_x = 0
        player.old_y = 0
        player.moving = false
    end
end

function create_trail(old_gx, old_gy, new_gx, new_gy)
    -- create trail particles from old grid position to new grid position
    local old_px, old_py = tile_to_px(old_gx, old_gy)
    local new_px, new_py = tile_to_px(new_gx, new_gy)
    -- generate particles along the path
    for i = 0, 15 do
        local t = i / 15
        local trail_x = old_px + (new_px - old_px) * t
        local trail_y = old_py + (new_py - old_py) * t
        -- white trail particles, no velocity, just fade
        create_particle(trail_x + rnd(4) - 2, trail_y + rnd(4) - 2, 8, 0, 0, 0.8, true)
    end
end

function update_particles()
    local to_remove = {}
    for p in all(particles) do
        p.x += p.vx
        p.y += p.vy
        -- gravity only for non-trail particles
        if not p.is_trail then
            p.vy += 0.1 -- gravity
        end
        -- rotation for rectangular particles
        if p.is_rect then
            p.rotation += p.rot_speed
        end
        p.life -= 0.02
        if p.life <= 0 then
            add(to_remove, p)
        end
    end
    -- remove dead particles in separate loop to avoid iteration issues
    for p in all(to_remove) do
        del(particles, p)
    end
end

function draw_particles(only_ui)
    for p in all(particles) do
        -- filter by UI/world scope - early skip
        if only_ui and not p.is_ui then goto continue end
        if not only_ui and p.is_ui then goto continue end

        local size = p.life * 2
        local col = p.col
        if p.is_trail then
            -- trail particles are larger
            size = p.life * 3.5
            -- fade from white (7) through light gray (6) to dark gray (5) as particle fades
            -- life goes from 0.8 to 0
            col = p.life > 0.6 and 7 or (p.life > 0.3 and 6 or 5)
            circfill(p.x, p.y, size, col)
        elseif p.is_rect then
            -- rectangular particles (simplified rotation with rectfill)
            local w = 3
            local h = 3
            -- simple rotation effect - alternate between orientations
            if flr(p.rotation * 2) % 2 == 0 then
                rectfill(p.x - w, p.y - h / 2, p.x + w, p.y + h / 2, col)
            else
                rectfill(p.x - h / 2, p.y - w, p.x + h / 2, p.y + w, col)
            end
        else
            -- regular circular particles
            circfill(p.x, p.y, size, col)
        end

        ::continue::
    end
end

-- count tiles to clear
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

-- get tile from working map
function get_tile(x, y)
    if x < 0 or x >= map_width or y < 0 or y >= map_height then
        return 0
    end
    local idx = y * map_width + x + 1
    return current_map[idx]
end

-- set tile in working map
function set_tile(x, y, v)
    if x >= 0 and x < map_width and y >= 0 and y < map_height then
        local idx = y * map_width + x + 1
        current_map[idx] = v
    end
end

-- reset map to initial state
function reset_map()
    -- save current map state before reset to know which tiles were destroyed
    local old_current_map = {}
    if current_map then
        for i = 1, map_tiles do
            old_current_map[i] = current_map[i]
        end
    end

    current_map = {}
    -- reset start position defaults
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

-- setup tile respawn animations
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

-- bounce animation
function update_bounce(p)
    -- save previous bounce value for bounce detection
    local prev_bounce = p.prev_bounce or 0

    -- if ball is falling, animate fall (zoom only)
    if p.falling then
        local t = p.fall_timer
        -- ball shrinks to 1x1 (top view - zoom out) if falling
        local size = 8 * (1 - t) -- from 8 to 0
        p.w = max(1, size)
        p.h = max(1, size)
        -- move ball down as it falls to show it's dropping into the void
        p.offset_y = t * 8 -- gradually move down by up to 8 pixels
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
        -- slower animation (was 0.05)
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

                -- start movement
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

    -- ball size: small (4) to large (16) and back - smoother zoom
    local min_size = 4
    local max_size = 16
    local zoom_factor = bounce * bounce
    p.w = min_size + (max_size - min_size) * zoom_factor
    p.h = min_size + (max_size - min_size) * zoom_factor

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
                        -- immortal mode - bounce sound
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

-- helper function for teleport tiles
function handle_teleport(x, y, particle_col1, particle_col2)
    -- trigger camera shake
    trigger_shake()
    -- create particle effect
    local px, py = tile_to_px(x, y)
    -- adjust for camera position (debris particles are rendered in world space)
    local world_px = px - cam_x
    local world_py = py - cam_y
    -- teleport sound
    sfx(12)
    -- remove teleport tile immediately (set to empty 0)
    set_tile(x, y, 0)
    -- create debris particles (gray colors)
    create_debris_particles(world_px, world_py, particle_col1, particle_col2)
    check_level_completion()
end

-- hit tile (decrease value or remove)
function hit_tile(x, y)
    local tile = get_tile(x, y)

    -- handle directional teleport ids (now 7..14)
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
        -- trigger camera shake
        trigger_shake()
        -- create particle effect on each hit (scaled 2x)
        local px, py = tile_to_px(x, y)
        -- yellow and orange particles for tile hits
        for i = 1, 8 do
            local col = rnd(1) > 0.5 and 10 or 9 -- randomly yellow (10) or orange (9)
            create_simple_particle(px, py, col)
        end
        -- crumbling tile sound
        sfx(12)

        local new_tile = tile - 1
        if new_tile <= 0 then
            -- tile disappeared: set to empty (0) and spawn debris
            set_tile(x, y, 0)
            -- adjust for camera position (debris particles are rendered in world space)
            local world_px = px - cam_x
            local world_py = py - cam_y
            -- create 4 rectangular debris particles flying in different directions
            create_debris_particles(world_px, world_py, 8)
            check_level_completion()
        else
            -- tile downgraded but still present
            set_tile(x, y, new_tile)
            sfx(11)
        end
    end
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

-- get animation sprite for teleport tile
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

function create_player(x, y)
    local p = {
        grid_x = x, -- tile position (target position)
        grid_y = y,
        old_x = x, -- previous position (for interpolation)
        old_y = y,
        moving = false, -- is ball moving
        move_timer = 0, -- timer for movement animation (0 to 1)
        w = 4, -- ball size (will animate 4-16)
        h = 4,
        offset_y = 0, -- Y offset for animation (0 down, -4 up)
        bounce_timer = 0 -- timer for bounce animation
    }
    return p
end

-- DRAWS ---------------------------------------------------------------------
function draw_player_shadow(cx, cy, r, col)
    local x0 = flr(cx - r)
    local x1 = flr(cx + r)
    for x = x0, x1 do
        local dx = x - cx
        local h2 = r * r - dx * dx
        if h2 >= 0 then
            local dy = flr(sqrt(h2))
            local y0 = flr(cy - dy)
            local y1 = flr(cy + dy)
            line(x, y0, x, y1, col)
        end
    end
end

function draw_player(p, camx, camy)
    -- interpolate position if ball is moving
    local render_x, render_y
    local center_x, center_y = 7, 9
    if p.falling then
        -- during fall ball stays in center of tile (no interpolation)
        render_x = p.grid_x
        render_y = p.grid_y
    elseif p.moving then
        -- smooth interpolation from old to new position
        local t = p.move_timer
        -- easing out for smoother movement (slowdown at end)
        local ease_t = 1 - (1 - t) * (1 - t)
        render_x = p.old_x + (p.grid_x - p.old_x) * ease_t
        render_y = p.old_y + (p.grid_y - p.old_y) * ease_t
    else
        render_x = p.grid_x
        render_y = p.grid_y
    end

    -- allow optional camera offsets (world->screen): default 0
    camx = camx or 0
    camy = camy or 0

    -- ball at position in world coords (center of 16x16 tile)
    local world_px = render_x * tile_size + center_x
    local world_py = render_y * tile_size + center_y
    -- camera() already applied offset, so use world coords directly
    local px = world_px
    local py = world_py

    -- shadow only when ball is near the ground (not in airborne flight) and not falling
    -- hide shadow during jump/flight by checking ball size (p.w): when large => airborne
    if not p.falling then
        local tile = get_tile(p.grid_x, p.grid_y)
        if tile ~= 0 and p.w <= 7 then
            local shadow_x = p.grid_x * tile_size + center_x
            local shadow_y = p.grid_y * tile_size + center_y
            draw_player_shadow(shadow_x, shadow_y, 4, 5)
        end
    end

    -- ball with Y offset
    local s = p.w / 1.8
    local ball_y = py + p.offset_y - s / 2

    -- draw ball only if size larger than 1px
    if s > 0.5 then
        local highlight_size = max(1.5, s * 0.45)
        local highlight_offset = s * 0.35
        -- shadow (black outline)
        circfill(px, ball_y, s + 1, 0)
        -- main ball (red base)
        circfill(px, ball_y, s, 8)
        -- darker gradient at bottom (transparency effect)
        circfill(px + 1, ball_y + s * 0.25, s * 0.7, 2)
        -- center gradient for depth
        circfill(px + 1 - s * 0.1, ball_y - s * 0.1, s * 0.7, 14)
        -- main highlight
        circfill(px - highlight_offset, ball_y - highlight_offset, highlight_size, 7)
        -- bright core highlights (glass effect)
        if s > 2 then
            circfill(px - highlight_offset * 1.1, ball_y - highlight_offset * 1.1, highlight_size * 0.6, 7)
        end
        -- small intense sparkle (like light reflex on glass)
        if s > 2.5 then
            local sparkle_size = max(0.5, s * 0.15)
            circfill(px - s * 0.5, ball_y - s * 0.5, sparkle_size, 7)
            pset(px - s * 0.5, ball_y - s * 0.5, 7)
        end
    end
end

-- draw tile with teleport animation
function draw_tile_with_anim(tile, x, y)
    -- check if it's a teleport tile
    if tile >= 7 and tile <= 14 then
        -- choose background tile: cardinal teleports use teleport1_bg_sprite, diagonals use teleport2_bg_sprite
        local bg_tile = (tile >= 11 and tile <= 14) and teleport2_bg_sprite or teleport1_bg_sprite
        -- draw background using the teleport bg constants directly (do not remap)
        draw_tile_sprite(bg_tile, x, y)
        -- draw animated icon in center (8x8 centered on 16x16 tile)
        local icon_sprite = get_teleport_anim_sprite(tile)
        spr(icon_sprite, x + 4, y + 4)
    else
        -- normal tile drawing
        draw_tile_sprite(map_tile_to_sprite(tile), x, y)
        -- optionally draw remaining-hit numbers for destructible tiles 1..3
        if show_numbers and tile >= 1 and tile <= 3 then
            local txt = tostring(tile)
            local c = tile == 1 and 7 or (tile == 2 and 10 or 9)
            local w = #txt * 4
            print(txt, x + 9 - w / 2, y + 7 - tile, c)
        end
    end
end

function draw_board()
    local ay = 2

    -- if not level_transition then
    --     rectfill(32 - cam_x, ay + 32 - cam_y, 96 - cam_x, ay + 96 - cam_y, 0)
    -- end

    -- helper function to draw a map with offset
    local function draw_map(map_data, x_offset)
        for tx = 0, map_width - 1 do
            local base_x = tx * tile_size + x_offset
            -- early skip if entire column is off screen
            if base_x > -tile_size and base_x < 128 then
                for ty = 0, map_height - 1 do
                    local idx = ty * map_width + tx + 1
                    local s = map_data[idx]
                    if s ~= 0 then
                        local yy = ay + ty * tile_size

                        -- check if this tile has a respawn animation
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

    if level_transition then
        -- calculate offset for level transition animation
        local offset_x = level_transition_timer * 128 * level_transition_direction
        -- draw old map (sliding out)
        draw_map(old_map, -offset_x)
        -- draw new map (sliding in from opposite side)
        draw_map(levels[next_level], -offset_x + (128 * -level_transition_direction))
    else
        -- normal drawing (no transition)
        draw_map(current_map, 0)
    end
end

function draw_background()
    cls(0)

    local col = 1
    local base_spacing = 24
    local amp = 3
    local speed = 2.8
    local cx, cy = 64, 64

    -- local spacing = 14
    local spacing = flr(base_spacing + amp * cos(t * speed))
    -- if spacing < 4 then spacing = 4 end

    local left = flr(cx / spacing)
    local right = flr((127 - cx) / spacing)
    local xs = {}
    for i = -left, right do
        add(xs, cx + i * spacing)
    end

    local top = flr(cy / spacing)
    local bottom = flr((127 - cy) / spacing)
    local ys = {}
    for i = -top, bottom do
        add(ys, cy + i * spacing)
    end

    for x in all(xs) do
        line(x, 0, x, 127, col)
    end
    for y in all(ys) do
        line(0, y, 127, y, col)
    end
    for x in all(xs) do
        for y in all(ys) do
            rectfill(x - 1, y - 1, x + 1, y + 1, col)
        end
    end
end

function draw_messages()
    -- game state messages
    if level_cleared and level_cleared_timer < 5 then
        local pulse = 0.5 + 0.5 * sin(t * 4)
        local text_col = 7 + flr(pulse * 3) -- pulse between white and light colors
        local time_text = "time: " .. format_time(level_time)
        local text1 = "level cleared!"

        -- get best time info
        local best_time = best_times[current_level]
        local best_text = ""
        if best_time then
            best_text = "best: " .. format_time(best_time)
            width3 = #best_text * 4
        end

        -- adjust box size for additional text
        local box_height = best_time and 78 or 70
        rectfill(20, 50, 108, box_height, 0)

        print_centered(text1, 54, text_col)
        print_centered(time_text, 62, 7)

        if best_time then
            print_centered(best_text, 70, 6)
        end
    elseif game_state == "won" then
        rectfill(20, 50, 108, 70, 0)
        print_centered("all levels complete!", 54, 11)
        print_centered("press \x97 to restart", 62, 7)
    elseif game_state == "lost" then
        rectfill(16, 50, 112, 80, 0)
        print_centered("game over", 54, 8)
        print_centered("press \x97 to restart", 62, 7)
        print_centered("press \x8e for next level", 70, 7)
    end

    -- draw new dynamic record animation (replaces old record message)
    draw_record_animation()
end

function draw_gui()
    -- rectfill(0, 0, 128, 9, 0)
    -- draw balls representing lives (at bottom)
    for i = 1, lives do
        local x = 4 + (i - 1) * 8
        local y = 4
        -- miniature red ball
        circfill(x, y, 3, 0) -- shadow
        circfill(x, y, 2, 8) -- red ball
        circfill(x - 1, y - 1, 0.5, 7) -- sparkle
    end

    -- draw level info in center
    local level_text = "level " .. current_level
    print_centered(level_text, 2, 7, 1)

    -- draw time counter in mm:ss format (right side)
    local time_text = format_time(level_time)
    local time_width = #time_text * 4
    print(time_text, 128 - time_width - 2, 2, 7)
end

function draw_title_screen()
    local title_x = 33
    local title_y = 28
    local menu_x = 64
    local menu_y = 72
    local menu_spacing = 11
    local pulse = sin(t * 2) * 0.5 + 0.5
    local color = flr(pulse * 6) + 8
    local k = flr(2 * cos(t * 4))

    if not show_leaderboard then
        -- rectfill(15, 15, 113, 113, 0)
        -- rect(14 + k, 14 + k, 114 + 0.9999 - k, 114 + 0.9999 - k, 1)

        -- title sprites
        for i = 0, 7 do
            spr(136 + i, title_x + i * 8, title_y)
            spr(152 + i, title_x + i * 8, title_y + 8)
            spr(168 + i, title_x + i * 8, title_y + 16)
            spr(184 + i, title_x + i * 8, title_y + 24)
            -- spr(128 + i, title_x + i * 8, title_y - 2)
            spr(144 + i, title_x + i * 8, title_y + 28)
        end

        print_centered("BOUNCING", title_y - 2, 10, 4)
        print("V1.0", 110, 120, 6)

        if not title_menu_index then title_menu_index = 1 end

        local items = {
            "start",
            (music_on and "music: on" or "music: off"),
            "best times"
        }

        for i = 1, #items do
            local yy = menu_y + (i - 1) * menu_spacing
            if i == title_menu_index then
                rectfill(menu_x - 32 + k, yy - 2, menu_x + 32 + 0.9999 - k, yy + 6, 8)
                print_centered(items[i], yy, 7)
            else
                print_centered(items[i], yy, 6, 1)
            end
        end
    end

    -- draw sliding leaderboard
    if leaderboard_anim > 0 then
        draw_leaderboard()
    end
end

-- draw the leaderboard table sliding from bottom
function draw_leaderboard()
    -- center the board on screen
    local board_width = 100
    local board_height = 100
    local board_x = (128 - board_width) / 2
    local board_y = (128 - board_height) / 2 - (board_height * (1 - leaderboard_anim))
    local k = flr(2 * cos(t * 4))

    rectfill(board_x, board_y, board_x + board_width, board_y + board_height, 0)
    rect(board_x + k, board_y + k, board_x + board_width + 0.9999 - k, board_y + board_height + 0.9999 - k, 1)

    -- layout
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

    print_centered("\x8e+\x97 reset records", board_y + 8, 9, 4)
    print_centered("press \x83 to close", board_y + board_height - 12, 6, 5)
end

-- helper to draw 2x2 sprite tile
function draw_tile_sprite(base_sprite, x, y)
    spr(base_sprite, x, y)
    spr(base_sprite + 1, x + 8, y)
    spr(base_sprite + 16, x, y + 8)
    spr(base_sprite + 17, x + 8, y + 8)
end

-- HELPERS AND UTILS ---------------------------------------------------------
function lerp(a, b, i) return i * a + (1 - i) * b end
function clamp(a, mi, ma) return min(max(a, mi), ma) end
function map_tile_to_sprite(id) return tile_sprite_map[id] or id end
function tile_to_px(x, y) return 0 + x * tile_size + 8, y * tile_size + 8 end

-- helper for centered text printing
function print_centered(text, y, col, shadow_col)
    -- compute pixel width of the string: normal chars = 4px, special/icon bytes (>=128) = 8px
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
        print(text, 64 - width / 2, y + 1, shadow_col)
    end
    print(text, 64 - width / 2, y, col)
end

-- trigger camera shake effect
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

-- initialize best times table
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

-- save best times to cartridge persistent data
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

-- load best times from cartridge persistent data
function load_best_times()
    best_times = {}
    local saved_levels = dget(0)

    -- if we have saved data, load it
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

-- check and update best time for current level
function check_best_time()
    local current_time = level_time
    local level_idx = current_level

    if not best_times[level_idx] or current_time < best_times[level_idx] then
        -- new record!
        best_times[level_idx] = current_time

        -- trigger new dynamic animation
        trigger_record_animation(90)

        -- save to persistent storage immediately
        save_best_times()

        return true
    end

    return false
end

-- trigger new dynamic record animation
function trigger_record_animation(y_offset, text)
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

-- update dynamic record animation
function update_record_animation()
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

-- draw dynamic record animation
function draw_record_animation()
    if record_anim_stage == 0 then return end

    -- calculate y position so bar expands from center vertically
    local y_center = record_anim_y_center or 64
    local y_pos = y_center - record_anim_height / 2

    -- choose rectangle color based on stage
    local rect_color = 7
    -- white by default
    if record_anim_stage == 3 then
        rect_color = 0 -- black in shrinking phases
    end

    -- draw rectangle
    rectfill(record_anim_x, y_pos, record_anim_x + record_anim_width - 1, y_pos + record_anim_height - 1, rect_color)

    if record_anim_stage == 3 then
        -- showing stage - display text with rainbow colors
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

-- helper function to format time as mm:ss
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
-------------------------------------------------------------------------------
class = setmetatable(
    {
        new = function(_ENV, tbl)
            tbl = tbl or {}

            setmetatable(
                tbl, {
                    __index = _ENV
                }
            )

            return tbl
        end,

        init = function() end
    }, { __index = _ENV }
)

entity = class:new({
    x = 0,
    y = 0
})
-->8
-- stars

star = entity:new({
    spd = .8,
    rad = 0,
    clr = 13,

    update = function(_ENV)
        x -= spd

        if x + rad < -9 then
            x = 137 + rad
        end
    end,

    draw = function(_ENV)
        circfill(x, y, rad, clr)
    end
})

far_star = star:new({
    clr = 1,
    spd = .25,
    rad = 0
})

near_star = star:new({
    clr = 7,
    spd = .75,
    rad = 1,

    new = function(self, tbl)
        tbl = star.new(self, tbl)

        tbl.spd = tbl.spd + rnd(.5)

        return tbl
    end
})

-------------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------------
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
0000000000000000000000000000000000aaaaaaaaaaaa000000000000000000000000000000000076666666666666600ddddddddddddd0006666666666666d0
000000000000000000999999999999000aaaaaaaaaaaaaa0000000000000000000000000000000006555555555555565ddddddddddddddd1666666666666666d
000888888888800009999999999999900aaaaaaaaaaaaaa000cccccccccccc0000bbbbbbbbbbbb006d66666666666d65ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cccccccccccccc00bbbbbbbbbbbbbb06d65666666656d65dddd5ddddd5dddd1666d66666666d66d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc1111111111cc00bb1111111111bb06d67666666676d65ddd516ddd516ddd1666766666666766d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc1dddddddd1cc00bb1333333331bb06d66666666666d65dddd6ddddd6dddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc1cccccccc1cc00bb1bbbbbbbb1bb06d66666666666665ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc1cccccccc1cc00bb1bbbbbbbb1bb06d66666666666d65ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc1cccccccc1cc00bb1bbbbbbbb1bb06666666666666665ddddddddddddddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cc5cccccccc5cc00bb3bbbbbbbb3bb06d66666666666665dddd5ddddd5dddd1666666666666666d
008888888888880009999999999999900aaaaaaaaaaaaaa00cccccccccccccc00bbbbbbbbbbbbbb0666d6666666d6665ddd516ddd516ddd1666666666666666d
00e8888888888e00099999999999999007aaaaaaaaaaaa700cc5cccccccc5cc00bb3bbbbbbbb3bb06667666666676665dddd6ddddd6dddd1666d66666666d66d
0027eeeeeeeee2000f999999999999f009777777777777900cccccccccccccc00bbbbbbbbbbbbbb06666666666666665ddddddddddddddd1666766666666766d
0002222222222000047fffffffffff4004999999999999400dccccccccccccd006bbbbbbbbbbbb6066666666666666656ddddddddddddd61766666666666667d
000000000000000000444444444444000244444444444420056ddddddddddd50057666666666665077777777777777751666666666666610d7777777777777dd
00000000000000000000000000000000002222222222220000555555555555000055555555555500055555555555555001111111111111000dddddddddddddd0
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
00000000000000000770000000000000000000000000770000000000000000007ffffffffffff7007ffffffff0000000ffffffff000ffffffffffffff0000000
0000000000000000070707770707077000770707700707000000000000000000e8888888888888f2e8888888ff00000f88888888ffdf8888888888888f000000
0000000000000000077007070707070707000007070700000000000000000000e88888888888888fe88888888e1000f88888888888e288888888888888f00000
0000000000000000070707070707070707000707070707000000000000000000e888888888888888f88888888e100e8888888888888e288888888888888e0000
0000000000000000077707770777070700770707070077000000000000000000e888888222888888e28888888e11e88888888888888e128888222888888e0000
0000000000000000000000000000000000000000000000000000000000000000e8888821112888888e288888e0112888888888888888e128821112888888e000
00000000000000000000000000000000000000000000000000000000000000000e888821100288888e288888e0128888888222288888e128821100288888e100
00000000000000000000000000000000000000000000000000000000000000000e888821100288888e088888e01288888821111288888e12821100288888e100
00000000000000000000000000000000000000000000000000000000000000000e888821100288888e088888e01288888821000288888e11821100288888e100
00000000000000000000000000000000000000000000000000000000000000000e88882110028888e0188888e01288888821100288888e1182110028888e1100
000000000000007000000000aa000000000000070000000777000000000000000e88882110028888e0188888e01288888821100288888e1182110028888e1100
00000000000000aa00a0a000a0a00a00a00aaa0aa00a0a0aa0000000000000000e8888211128888e01888888e01288888821100288888e118211128888e11100
00000000000000909090900099009009090909090909090009000000000000000e888882118888e001888888e01288888821100288888e11182118888e111000
00000000000000999099900090009009990999090909990999000000000000000e8888888888ee0012888888e01288888821100288888e111888888ee1111000
00000000000000000000900000000000000009000000000000000000000000000e888888888888e001288888e01288888821100288888e11188888888e110000
00000000000000000000000000000000000000000000000000000000000000000e8888822288888e01288888e01288888821100288888e111822288888e10000
00000000000000000000000000000000000000000000000000000000000000000e28882111288888e0128888e01228888821100288882e1112111288888e0000
00000000000000000000000000000000000000000000000000000000000000000e228221100228822e112282e01222222221100288222e11121100228822e000
00000000000000000000000000000000000000000000000000000000000000000e2222211002222222e11222e01221111221100222222e111211002222222e00
00000000000000000000000000000000000000000000000000000000000000000e2222211002222222e11222201212222e21101222222e111211002222222e10
00000000000000000000000000000000000000000000000000000000000000000e2222211002222222e11222201112222e02111222222e111211002222222e10
00000000000000000000000000000000000000000000000000000000000000000e2222211112222222e11222200002222e02222222221d111211112222222e10
0000000000000000000000000000000000000000000000000000000000000000c22222211122222221d11222222222222d0222222221c1111211122222221d10
0000000000000000000000000000000000000000000000000000000000000000c1222222222222221c111222222222222c0222222211c111122222222221c110
0000000000000000000000000000000000000000000000000000000000000000c1122222222222111c110122222222221c012222211c1111022222222111c110
0000000000000000000000000000000000000000000000000000000000000000c111111111111111c1110111111111111c011111111c111101111111111c1110
0000000000000000000000000000000000000000000000000000000000000000c1111111111111cc11110111111111111c01111111c11111011111111cc11110
0000000000000000000000000000000000000000000000000000000000000000cccccccccccccc1111110dccccccccccc101cccccc1111110cccccccc1111110
00000000000000000000000000000000000000000000000000000000000000001111111111111111111011111111111111011111111111101111111111111100
00000000000000000000000000000000000000000000000000000000000000001111111111111111111011111111111111101111111111101111111111111100
00000000000000000000000000000000000000000000000000000000000000001111111111111111110011111111111111110111111111011111111111111000
00000000000000000000000000000000000000000000000000000000000000000111111111111111000001111111111111100001111100001111111111100000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00040501010101000004050102050300000402020202090000010201030303000001020202020200000402030001020000040100000203000004010201020100000405020505050000040c0005050500000800020103010000040002000909000004010109090100000401000103020000080109010101000004010201030200
000502020202050000050302010305000001000000000e0000080108030503000008000505050300000805080002010000020c000001020000010001000109000005010002000500000b000100000500000100050d0109000008000300010100000201020502050000050105030202000004030203010100000c00010b010300
000102030302050000010205030102000001000505000200000103010303030000010203000a010000030102000a0500000000010b000900000005000500050000080001000205000000000c000100000002000a040e05000001000a00030200000509050202020000050505000101000000000801090100000008010c000100
0005020303020100000201030502010000010005090002000007010a010a010000010102000a01000008050800020100000000020100000000090102010201000005020d01000a000002010001030100000101050b0502000008000100010100000201010101050000090509000000000001010100010200000502010e050000
0005020202020500000503010205030000010005030002000004030103010200000800050505020000020103000a050000010100000101000000000000000000000503020001050000010200000c000000000000000001000001000a0000010000050205020502000005050505050200000105010a080a000001030205020100
000101010105050000030502010305000008000101000100000801080107010000010204000001000008050800010200000101000a02010000010801020101000005050502050500000201000a02010000050705010a020000080001080005000001010101010100000303010805010000010101000102000005010207020300
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

