package game

import rl "vendor:raylib"
import "core:fmt"
import "core:mem"

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

HALF_ALPHA_VALUE :: u8(128)

offset := rl.Vector2{0, 0}

font : rl.Font

Entity_Type :: enum {
    Player,
    Cargo,
    Wall,
}

TextureID :: enum {
    TEXTURE_none,
    TEXTURE_player,
    TEXTURE_cargo,
    TEXTURE_wall,
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
        case:
            return .TEXTURE_none
    }
}

Layer :: struct {
    entities: [dynamic]Entity,
    is_visible: bool,
    order: int,
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
    en.position = {5, 5}
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

main :: proc() {
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
        for entity in level.layer_1.entities {
            rl.DrawTextureV(textures[entity.texture_id], rl.Vector2{f32(entity.position.x*GRID_SIZE), f32(entity.position.y*GRID_SIZE)}, rl.Color{255, 255, 255, HALF_ALPHA_VALUE})
        }
    }
    if level.layer_2.is_visible {
        for entity in level.layer_2.entities {
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
}

game_init :: proc() {
    // load assets
    font = rl.LoadFont("assets/fonts/m6x11.ttf")
    textures[.TEXTURE_player] = rl.LoadTexture("assets/textures/duck.png")
    textures[.TEXTURE_cargo] = rl.LoadTexture("assets/textures/cargo.png")
    textures[.TEXTURE_wall] = rl.LoadTexture("assets/textures/wall.png")

    setup_player(&player)
    cargo := Entity{}
    cargo.position = {4, 4}
    setup_cargo(&cargo)
    append(&level.layer_1.entities, cargo)

    cargo_1 := Entity{}
    cargo_1.position = {4, 4}
    setup_cargo(&cargo_1)
    append(&level.layer_2.entities, cargo_1)

    wall := Entity{}
    wall.position = {3, 3}
    setup_wall(&wall)
    append(&level.layer_1.entities, wall)
}

game_update :: proc() {
    get_input()
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

    // test
    if rl.IsKeyPressed(.O) {
        level.layer_1.is_visible = !level.layer_1.is_visible
    }
    if rl.IsKeyPressed(.P) {
        level.layer_2.is_visible = !level.layer_2.is_visible
    }
}

move :: proc(en: ^Entity, dir: [2]int) -> bool {
    target_pos := en.position + dir
    entity_in_l1, entity_in_l2 := find_entities_in_position(target_pos)

    if target_pos.x < 0 || target_pos.x >= GRID_COUNT || target_pos.y < 0 || target_pos.y >= GRID_COUNT {
        return false // Out of bounds, do nothing
    }

    if entity_in_l1 == nil && entity_in_l2 == nil {
        en.position = target_pos
        return true
    } 
    else if entity_in_l1 != nil && entity_in_l2 == nil {
        if entity_in_l1.type == .Cargo {
            if move(entity_in_l1, dir) {
                en.position = target_pos
                return true
            }
        } else {
            return false
        }
    }
    else if entity_in_l1 == nil && entity_in_l2 != nil {
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
        if entity_in_l2.type == .Cargo && entity_in_l1.type == .Cargo {
            first_cargo_target_pos := target_pos + dir
            first_next_entity_in_l1, first_next_entity_in_l2 := find_entities_in_position(first_cargo_target_pos)

            second_cargo_target_pos := target_pos + dir
            second_next_entity_in_l1, second_next_entity_in_l2 := find_entities_in_position(second_cargo_target_pos)

            if first_next_entity_in_l1 == nil && first_next_entity_in_l2 == nil && 
               second_next_entity_in_l1 == nil && second_next_entity_in_l2 == nil {
                entity_in_l1.position = first_cargo_target_pos
                entity_in_l2.position = second_cargo_target_pos
                en.position = target_pos
                return true
            }
        }
        return false
    }
    return false
}

find_entities_in_position :: proc(pos: [2]int) -> (^Entity, ^Entity){
    entity_in_l1: ^Entity = nil
    entity_in_l2: ^Entity = nil

    if level.layer_1.is_visible == true {
        for &en in level.layer_1.entities {
            if en.position == pos {
                entity_in_l1 = &en
                break
            }
        }
    }

    if level.layer_2.is_visible == true {
        for &en in level.layer_2.entities {
            if en.position == pos {
                entity_in_l2 = &en
                break
            }
        }
    }

    return entity_in_l1, entity_in_l2
}