package game

import rl "vendor:raylib"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:os"
import "core:log"

// color palettes
MY_YELLOW_BROWN :: rl.Color{221, 169, 99, 255}
MY_BROWN :: rl.Color{201, 129, 75, 255}
MY_BLACK :: rl.Color{37, 39, 42, 255}
MY_LIGHT_BROWN :: rl.Color{219, 193, 175, 255}
MY_ORANGE :: rl.Color{207, 106, 79, 255}
MY_YELLOW :: rl.Color{224, 185, 74, 255}
MY_GREEN :: rl.Color{178, 175, 92, 255}
MY_GREY :: rl.Color{167, 167, 158, 255}
MY_PURPLE :: rl.Color{155, 105, 112, 255}

GRID_SIZE :: 64
SCREEN_SIZE :: 960
GRID_COUNT :: 10
MAX_ENTITIES_COUNT :: 300

HALF_ALPHA_VALUE :: u8(150)

offset := rl.Vector2{0, 0}
mouse_position : rl.Vector2
targets : [dynamic]Entity

font : rl.Font

is_ok: bool
current_level_index: int

Entity_Type :: enum u8 {
    Player = '@',
    Cargo = 'C',
    Wall = '#',
    Target = '*',
    Flag = '>',
}

TextureID :: enum {
    TEXTURE_none,
    TEXTURE_player,
    TEXTURE_cargo,
    TEXTURE_wall,
    TEXTURE_target,
    TEXTURE_flag_ok,
    TEXTURE_flag_no,
    TEXTURE_visible,
    TEXTURE_invisible,
}

textures: [TextureID]rl.Texture2D

get_texture :: proc(id: TextureID) -> rl.Texture2D {
    if id >= .TEXTURE_none {
        return textures[id]
    }
    return textures[.TEXTURE_none]
}

get_texture_id_from_type :: proc(type: Entity_Type) -> TextureID {
    switch type {
        case .Player:
            return .TEXTURE_player
        case .Cargo:
            return .TEXTURE_cargo
        case .Wall:
            return .TEXTURE_wall
        case .Target:
            return .TEXTURE_target
        case .Flag:
            if is_ok {
                return .TEXTURE_flag_ok
            }
            else {
                return .TEXTURE_flag_no
            }
        case:
            return .TEXTURE_none
    }
}

Layer :: struct {
    entities: [dynamic]Entity,
    is_visible: bool,
    order: int,
}

get_layer_by_num :: proc(num: int) -> Layer {
    if num == 1 {
        return level.layer_1
    }
    else {
        return level.layer_2
    }
}

Level :: struct {
    layer_1: Layer,
    layer_2: Layer,
}

level := Level {
    layer_1 = Layer {
        is_visible = true,
        order = 1,
    },
    layer_2 = Layer {
        is_visible = true,
        order = 2,
    },
}

Input :: enum {
    None,
    Up,
    Down,
    Left,
    Right,
}

input: Input

Entity :: struct {
    type: Entity_Type,
    texture_id: TextureID,
    position: [2]int,
    layer: int, // 1 or 2
    priority: int, // from 0
    can_overlap: bool,
}

Player :: struct {
    using entity: Entity,
    is_flipped: bool,
}

player := Player{}
setup_player :: proc(en: ^Entity) {
    en.texture_id = .TEXTURE_player
    en.type = .Player
    en.position = {5, 6}
    en.priority = 3
}

setup_cargo :: proc(en: ^Entity) {
    en.texture_id = .TEXTURE_cargo
    en.type = .Cargo
    en.priority = 3
}

setup_wall :: proc(en: ^Entity) {
    en.texture_id = .TEXTURE_wall
    en.type = .Wall
    en.priority = 3
}

setup_flag :: proc(en: ^Entity) {
    en.texture_id = .TEXTURE_flag_no
    en.type = .Flag
    en.priority = 2
    en.can_overlap = true
}

setup_target :: proc(en: ^Entity) {
    en.texture_id = .TEXTURE_target
    en.type = .Target
    en.priority = 2
    en.can_overlap = true
    append(&targets, en^)
}

main :: proc() {
    // Init logger
    logger := log.create_console_logger()
    context.logger = logger
    defer log.destroy_console_logger(logger)
    
    // any memory leaks?
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorret frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    rl.SetConfigFlags({.WINDOW_RESIZABLE})
    rl.InitWindow(SCREEN_SIZE+200, SCREEN_SIZE, "UWU")
    defer rl.CloseWindow()
    rl.SetTargetFPS(100)
    game_init()

    camera: rl.Camera2D
    camera.zoom = 1.5

    for !rl.WindowShouldClose() {
        rl.BeginMode2D(camera)
        defer rl.EndDrawing()
        game_update()
        is_ok = check_win_condition()
        draw()
    }
}

draw :: proc() {
    rl.ClearBackground(rl.WHITE)

    // draw grid lines
    for i := 0; i < GRID_COUNT+1; i += 1 {
        rl.DrawLineEx(rl.Vector2{f32(GRID_SIZE*i) + offset.x/2, offset.y/2}, rl.Vector2{f32(GRID_SIZE*i) + offset.x/2, GRID_COUNT*GRID_SIZE - offset.y/2}, 2, rl.Color{MY_GREY.r, MY_GREY.g, MY_GREY.b, 80})
    }

    for i := 0; i < GRID_COUNT+1; i += 1 {
        rl.DrawLineEx(rl.Vector2{offset.x/2, f32(GRID_SIZE*i)}, rl.Vector2{GRID_COUNT*GRID_SIZE+offset.x/2, f32(GRID_SIZE*i)}, 2, rl.Color{MY_GREY.r, MY_GREY.g, MY_GREY.b, 80})
    }

    // draw level
    if level.layer_1.is_visible {
        for &entity in level.layer_1.entities {
            if entity.type == .Flag {
                if is_ok {
                    entity.texture_id = .TEXTURE_flag_ok
                }
                else {
                    entity.texture_id = .TEXTURE_flag_no
                }
            }
            rl.DrawTextureV(textures[entity.texture_id], rl.Vector2{f32(entity.position.x*GRID_SIZE), f32(entity.position.y*GRID_SIZE)}, rl.Color{255, 255, 255, HALF_ALPHA_VALUE})
        }
    }
    if level.layer_2.is_visible {
        for &entity in level.layer_2.entities {
            if entity.type == .Flag {
                if is_ok {
                    entity.texture_id = .TEXTURE_flag_ok
                }
                else {
                    entity.texture_id = .TEXTURE_flag_no
                }
            }
            rl.DrawTextureV(textures[entity.texture_id], rl.Vector2{f32(entity.position.x*GRID_SIZE), f32(entity.position.y*GRID_SIZE)}, rl.Color{255, 255, 255, HALF_ALPHA_VALUE})
        }
    }

    // draw player
    if !player.is_flipped {
        rl.DrawTexturePro(textures[player.texture_id], rl.Rectangle{0, 0, f32(textures[player.texture_id].width), f32(textures[player.texture_id].height)}, rl.Rectangle{f32(player.position.x*GRID_SIZE), f32(player.position.y*GRID_SIZE), f32(textures[player.texture_id].width), f32(textures[player.texture_id].height)}, rl.Vector2(0), 0, rl.WHITE)
    }
    else {
        rl.DrawTexturePro(textures[player.texture_id], rl.Rectangle{0, 0, -f32(textures[player.texture_id].width), f32(textures[player.texture_id].height)}, rl.Rectangle{f32(player.position.x*GRID_SIZE), f32(player.position.y*GRID_SIZE), f32(textures[player.texture_id].width), f32(textures[player.texture_id].height)}, rl.Vector2(0), 0, rl.WHITE)
    }

    // draw text and ui
    rl.DrawTextEx(font, "Layer 1", rl.Vector2{690, 10}, 20, 1.2, MY_BLACK)
    rl.DrawTextEx(font, "Layer 2", rl.Vector2{690, 40}, 20, 1.2, MY_BLACK)
    if level.layer_1.is_visible {
        rl.DrawTexture(textures[.TEXTURE_visible], 630, -13, rl.WHITE)
    }
    else {
        rl.DrawTexture(textures[.TEXTURE_invisible], 630, -13, rl.WHITE)
    }
    if level.layer_2.is_visible {
        rl.DrawTexture(textures[.TEXTURE_visible], 630, -13+30, rl.WHITE)
    }
    else {
        rl.DrawTexture(textures[.TEXTURE_invisible], 630, -13+30, rl.WHITE)
    }
}

get_input :: proc() {
    input = .None
    if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
        input = .Up
    } 
    else if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
        input = .Down
    }
    else if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.A){
        input = .Left
    }
    else if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) {
        input = .Right
    }
    mouse_position = rl.GetMousePosition()
}

game_init :: proc() {
    // load assets
    font = rl.LoadFont("assets/fonts/m6x11.ttf")
    textures[.TEXTURE_player] = rl.LoadTexture("assets/textures/duck.png")
    textures[.TEXTURE_cargo] = rl.LoadTexture("assets/textures/cargo.png")
    textures[.TEXTURE_wall] = rl.LoadTexture("assets/textures/wall.png")
    textures[.TEXTURE_flag_ok] = rl.LoadTexture("assets/textures/flag_ok.png")
    textures[.TEXTURE_flag_no] = rl.LoadTexture("assets/textures/flag_no.png")
    textures[.TEXTURE_target] = rl.LoadTexture("assets/textures/target.png")

    textures[.TEXTURE_visible] = rl.LoadTexture("assets/textures/visible.png")
    textures[.TEXTURE_invisible] = rl.LoadTexture("assets/textures/invisible.png")

    setup_player(&player)
    if ok := load_level_from_txt(1); ok {
        current_level_index = 1
    }
}

game_update :: proc() {
    get_input()
    // fmt.println("mouse pos: ", mouse_position)
    #partial switch input {
        case .Up:
            move(&player, {0, -1})
        case .Down:
            move(&player, {0, 1})
        case .Left:
            move(&player, {-1, 0})
            player.is_flipped = true
        case .Right:
            move(&player, {1, 0})
            player.is_flipped = false
    }

    // toggle layer's visibility
    if rl.IsMouseButtonPressed(.LEFT) {
        if mouse_position.x > 960 && mouse_position.x < 960+64 && mouse_position.y > 0 && mouse_position.y < 40 {
            level.layer_1.is_visible = !level.layer_1.is_visible
            if !level.layer_1.is_visible && !level.layer_2.is_visible {
                level.layer_2.is_visible = true
            } 
        }
        if mouse_position.x > 960 && mouse_position.x < 960+64 && mouse_position.y > 40 && mouse_position.y < 40+40 {
            level.layer_2.is_visible = !level.layer_2.is_visible
            if !level.layer_1.is_visible && !level.layer_2.is_visible {
                level.layer_1.is_visible = true
            }
        }
    }
}

move :: proc(en: ^Entity, dir: [2]int) -> bool {
    target_pos := en.position + dir
    entity_in_l1, entity_in_l2 := find_entities_in_position(target_pos)

    if target_pos.x < 0 || target_pos.x >= GRID_COUNT || target_pos.y < 0 || target_pos.y >= GRID_COUNT {
        return false // Out of bounds, do nothing
    }

    if ((entity_in_l1 == nil || entity_in_l1.can_overlap) && (entity_in_l2 == nil || entity_in_l2.can_overlap)) {
        en.position = target_pos
        return true
    } 
    else if entity_in_l1 != nil && (entity_in_l2 == nil || entity_in_l2.can_overlap) {
        if entity_in_l1.type == .Cargo {
            if move(entity_in_l1, dir) {
                en.position = target_pos
                return true
            }
        } else {
            return false
        }
    }
    else if (entity_in_l1 == nil || entity_in_l1.can_overlap) && entity_in_l2 != nil {
        if entity_in_l2.type == .Cargo {
            if move(entity_in_l2, dir) {
                en.position = target_pos
                return true
            }
        } else {
            return false
        }
    }
    else {
        // TODO: should overlapped cargos be pushed together?
        if entity_in_l2.type == .Cargo && entity_in_l1.type == .Cargo {
            if move(entity_in_l2, dir) && move(entity_in_l1, dir) {
                en.position = target_pos
                return true
            }
        } else{
            return false
        }
    }
    return false
}

find_entities_in_position :: proc(pos: [2]int) -> (^Entity, ^Entity){
    entity_in_l1: ^Entity = nil
    entity_in_l2: ^Entity = nil

    if level.layer_1.is_visible == true {
        for &en in level.layer_1.entities {
            if en.position == pos && !en.can_overlap {
                entity_in_l1 = &en
                break
            }
        }
    }

    if level.layer_2.is_visible == true {
        for &en in level.layer_2.entities {
            if en.position == pos && !en.can_overlap {
                entity_in_l2 = &en
                break
            }
        }
    }

    return entity_in_l1, entity_in_l2
}

check_win_condition :: proc() -> bool {
    for target in targets {
        if get_layer_by_num(target.layer).is_visible == false {
            return false
        }
        en_1, en_2 := find_entities_in_position(target.position)
        if en_1 == nil && en_2 == nil {
            return false
        }
    }
    log.info("Can enter next level now")
    // TODO: when player enter flag, load next level
    return true
}


load_level_from_txt :: proc(index: int) -> bool {
    builder := strings.builder_make()

    path1 := fmt.sbprintf(&builder, "assets/levels/%d-l1.txt", index)
    if l1_data, ok := os.read_entire_file_from_filename(path1, context.temp_allocator); ok {
        from_txt_to_level(1, string(l1_data))
        log.infof("Loaded level%d layer1!", index)
    } else {
        log.infof("Could't load level%d layer1!", index)
        return false
    }

    strings.builder_reset(&builder)

    path2 := fmt.sbprintf(&builder, "assets/levels/%d-l2.txt", index)
    if l2_data, ok := os.read_entire_file_from_filename(path2, context.temp_allocator); ok {
        from_txt_to_level(2, string(l2_data))
        log.infof("Loaded level%d layer2!", index)
    } else {
        log.infof("Could't load level%d layer2!", index)
        return false
    }
    return true
}

from_txt_to_level :: proc(layer_index: int, content: string) {
    x := 0
    y := 0
    // print level
    fmt.printf("\nlayer %d:\n", layer_index)
    for char, i in content {
        if char != '\n' {
            fmt.printf("%c", char)
        } else {
            fmt.printf("\n")
        }

        en := new(Entity)
        en.position = {x, y}
        en.layer = layer_index
        x += 1
        switch char {
            case '@':
                setup_player(en)
            case 'C':
                setup_cargo(en)
            case '#':
                setup_wall(en)
            case '*':
                setup_target(en)
            case '>':
                setup_flag(en)
            case ' ': // empty
                continue
            case '\n':
                y += 1
                x = 0
        }
        if layer_index == 1 {
            append(&level.layer_1.entities, en^)
        } else if layer_index == 2 {
            append(&level.layer_2.entities, en^)
        } else {
            log.error("Invalid layer index!")
        }
    }
}

unload_level :: proc() {
    clear(&level.layer_1.entities)
    clear(&level.layer_2.entities)
}

load_next_level :: proc() {
    unload_level()
    if ok := load_level_from_txt(current_level_index + 1); ok {
        current_level_index += 1
    } else {
        load_level_from_txt(current_level_index)
        log.warn("Load next level failed, maybe it's the last level?")
    }
}