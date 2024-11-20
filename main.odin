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
SCREEN_SIZE :: 672
GRID_COUNT :: 10

offset := rl.Vector2{ 0, 0 }

Input :: enum {
    None,
    Up,
    Down,
    Left,
    Right,
}

input: Input

Player :: struct {
    position: rl.Vector2,
}

player := Player{ {5, 5}, }

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

    rl.InitWindow(SCREEN_SIZE, SCREEN_SIZE, "UWU")
    defer rl.CloseWindow()
    rl.SetTargetFPS(100)

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        defer rl.EndDrawing()
        game_update()
        draw()
    }
}

draw :: proc() {
    rl.ClearBackground(rl.WHITE)

    // draw grid lines
    for i := 0; i < GRID_COUNT+1; i += 1 {
        rl.DrawLineV(rl.Vector2{f32(GRID_SIZE*i) + offset.x/2, offset.y/2}, rl.Vector2{f32(GRID_SIZE*i) + offset.x/2, GRID_COUNT*GRID_SIZE - offset.y/2}, MY_GREY)
    }

    for i := 0; i < GRID_COUNT+1; i += 1 {
        rl.DrawLineV(rl.Vector2{offset.x/2, f32(GRID_SIZE*i)}, rl.Vector2{GRID_COUNT*GRID_SIZE+offset.x/2, f32(GRID_SIZE*i)}, MY_GREY)
    }

    // draw player
    rl.DrawRectangleV(player.position * GRID_SIZE, {GRID_SIZE, GRID_SIZE}, MY_ORANGE)
}

get_input :: proc() {
    input = .None
    if rl.IsKeyPressed(.UP) {
        input = .Up
    } 
    else if rl.IsKeyPressed(.DOWN) {
        input = .Down
    }
    else if rl.IsKeyPressed(.LEFT) {
        input = .Left
    }
    else if rl.IsKeyPressed(.RIGHT) {
        input = .Right
    }
}

game_init :: proc() {
    // do some init stuff
}

game_update :: proc() {
    get_input()
    #partial switch input {
        case .Up:
            if player.position.y > 0 {
                player.position += {0, -1}
            }
        case .Down:
            if player.position.y < GRID_COUNT-1 {
                player.position += {0, 1}
            }
        case .Left:
            if player.position.x > 0 {
                player.position += {-1, 0}
            }
        case .Right:
            if player.position.x < GRID_COUNT-1 {
                player.position += {1, 0}
            }
    }
}