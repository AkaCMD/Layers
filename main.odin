package main

import rl "vendor:raylib"

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

GRID_SIZE :: 32

Player :: struct {
    position: rl.Vector2,
}

player := Player{ {320, 320}, }

main :: proc() {
    rl.InitWindow(672, 672, "LAYERS:)")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        defer rl.EndDrawing()
        draw()
    }
}

draw :: proc() {
    rl.ClearBackground(rl.WHITE)

    // draw player
    rl.DrawRectangleV(player.position, {64, 64}, MY_ORANGE)
}