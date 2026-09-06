package game

import "core:c"
import "core:log"
import "core:mem"
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

GAME_SCREEN_WIDTH :: 960 + 200
GAME_SCREEN_HEIGHT :: 960
OVERVIEW_SCREEN_WIDTH :: 1920
OVERVIEW_SCREEN_HEIGHT :: 1080
ZOOM :: 1.5
LEVEL_SIZE :: 960
GRID_COUNT :: 10
GRID_SIZE :: LEVEL_SIZE / (GRID_COUNT * ZOOM)
MAX_ENTITIES_COUNT :: 300
RATIO :: 0.8

HALF_ALPHA_VALUE :: u8(150)

// render
target: rl.RenderTexture2D
overview_target: rl.RenderTexture2D
scale: f32
overview_scale: f32

// atlas
Rect :: rl.Rectangle
atlas: rl.Texture

// audio
bgm: rl.Music
sfx_footstep: rl.Sound
sfx_pushbox: rl.Sound
sfx_switch: rl.Sound
sfx_activate: rl.Sound
sfx_undo: rl.Sound
sfx_complete: rl.Sound

offset := rl.Vector2{0, 0}
mouse_position: rl.Vector2

font: rl.Font

is_completed: bool
should_show_tip: bool = true
current_level_index: int

// UI
eyeball_bounds: [dynamic]rl.Rectangle

// overview (special view that shows every layer + player)
is_overview: bool
overview_eye_bounds: [dynamic]rl.Rectangle
overview_panel_x: [dynamic]f32
overview_cell: f32
overview_panel_y: f32

run: bool
camera: rl.Camera2D
logger: log.Logger

// Undo stack memory allocator
arena_allocator: mem.Allocator
arena: mem.Arena

icon: rl.Image

world := World{}
undo_stack: [dynamic]Record

Input :: enum {
	None,
	Up,
	Down,
	Left,
	Right,
}

input: Input

init :: proc() {
	run = true
	// Change working directory
	// For macos, the default directory is not application directory
	rl.ChangeDirectory(rl.GetApplicationDirectory())
	// Init logger
	logger = log.create_console_logger()
	context.logger = logger

	// any memory leaks?
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				log.errorf("=== %v allocations not freed: ===", len(track.allocation_map))
				for _, entry in track.allocation_map {
					log.errorf("- %v bytes @ %v", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				log.errorf("=== %v incorret frees: ===", len(track.bad_free_array))
				for entry in track.bad_free_array {
					log.errorf("- %p @ %v", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	arena = mem.Arena{}
	mem.arena_init(&arena, make([]byte, 6_000_000))
	arena_allocator = mem.arena_allocator(&arena)

	when ODIN_OS != .JS {
		rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .WINDOW_MAXIMIZED})
	} else {
		rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	}
	rl.InitWindow(GAME_SCREEN_WIDTH * RATIO, GAME_SCREEN_HEIGHT * RATIO, "Layers")
	rl.InitAudioDevice()

	// Render texture initialization, used to hold the rendering result so we can easily resize it
	target = rl.LoadRenderTexture(GAME_SCREEN_WIDTH, GAME_SCREEN_HEIGHT)
	rl.SetTextureFilter(target.texture, rl.TextureFilter.POINT)
	overview_target = rl.LoadRenderTexture(OVERVIEW_SCREEN_WIDTH, OVERVIEW_SCREEN_HEIGHT)
	rl.SetTextureFilter(overview_target.texture, rl.TextureFilter.POINT)

	rl.SetTargetFPS(60)
	init_layers()
	game_init()
	rl.PlayMusicStream(bgm)

	camera.zoom = ZOOM
}

update :: proc() {
	rl.ClearBackground(MY_GREY)
	rl.UpdateMusicStream(bgm)
	scale = min(
		f32(rl.GetScreenWidth()) / f32(GAME_SCREEN_WIDTH),
		f32(rl.GetScreenHeight()) / f32(GAME_SCREEN_HEIGHT),
	)
	overview_scale = min(
		f32(rl.GetScreenWidth()) / f32(OVERVIEW_SCREEN_WIDTH),
		f32(rl.GetScreenHeight()) / f32(OVERVIEW_SCREEN_HEIGHT),
	)

	init_ui_bounds()

	if rl.IsKeyPressed(.TAB) {
		is_overview = !is_overview
		rl.PlaySound(sfx_switch)
	}

	if is_overview {
		rl.BeginTextureMode(overview_target)
		{
			overview_update()
			draw_overview()
		}
		rl.EndTextureMode()
	} else {
		rl.BeginTextureMode(target)
		{
			rl.BeginMode2D(camera)
			{
				game_update()
				draw()
			}
			rl.EndMode2D()
		}
		rl.EndTextureMode()
	}

	// Draw scaled content to screen
	rl.BeginDrawing()
	{
		if is_overview {
			dest := rl.Rectangle {
				(f32(rl.GetScreenWidth()) - f32(OVERVIEW_SCREEN_WIDTH) * overview_scale) * 0.5,
				(f32(rl.GetScreenHeight()) - f32(OVERVIEW_SCREEN_HEIGHT) * overview_scale) * 0.5,
				f32(OVERVIEW_SCREEN_WIDTH) * overview_scale,
				f32(OVERVIEW_SCREEN_HEIGHT) * overview_scale,
			}
			source := rl.Rectangle{0, 0, f32(overview_target.texture.width), f32(-overview_target.texture.height)}
			rl.DrawTexturePro(overview_target.texture, source, dest, rl.Vector2{0, 0}, 0.0, rl.WHITE)
		} else {
			dest := rl.Rectangle {
				(f32(rl.GetScreenWidth()) - f32(GAME_SCREEN_WIDTH) * scale) * 0.5,
				(f32(rl.GetScreenHeight()) - f32(GAME_SCREEN_HEIGHT) * scale) * 0.5,
				f32(GAME_SCREEN_WIDTH) * scale,
				f32(GAME_SCREEN_HEIGHT) * scale,
			}
			source := rl.Rectangle{0, 0, f32(target.texture.width), f32(-target.texture.height)}
			rl.DrawTexturePro(target.texture, source, dest, rl.Vector2{0, 0}, 0.0, rl.WHITE)
		}
	}
	rl.EndDrawing()
	free_all(context.temp_allocator)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(c.int(w), c.int(h))
}

shutdown :: proc() {
	log.destroy_console_logger(logger)
	rl.CloseAudioDevice()
	rl.UnloadAudioStream(bgm)
	rl.CloseWindow()
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			run = false
		}
	}

	return run
}

read_move_input :: proc() {
	input = .None
	if rl.IsKeyPressed(.UP) || rl.IsKeyPressed(.W) {
		input = .Up
	} else if rl.IsKeyPressed(.DOWN) || rl.IsKeyPressed(.S) {
		input = .Down
	} else if rl.IsKeyPressed(.LEFT) || rl.IsKeyPressed(.A) {
		input = .Left
	} else if rl.IsKeyPressed(.RIGHT) || rl.IsKeyPressed(.D) {
		input = .Right
	}
}

push_undo_record :: proc() {
	if input == .None {
		return
	}
	record := new(Record, context.temp_allocator)
	record.world = clone_world(&world)
	append(&undo_stack, record^)
	rl.PlaySound(sfx_footstep)
}

apply_movement :: proc() {
	player := find_player()
	#partial switch input {
	case .Up:
		move(player, {0, -1})
	case .Down:
		move(player, {0, 1})
	case .Left:
		move(player, {-1, 0})
		player.is_flipped = true
	case .Right:
		move(player, {1, 0})
		player.is_flipped = false
	}
}

get_move_input :: proc() {
	read_move_input()
	mouse_position = get_mouse_position()
	push_undo_record()
}

// :init
game_init :: proc() {
	// load assets
	atlas = rl.LoadTexture("assets/atlas.png")
	rl.SetTextureFilter(atlas, rl.TextureFilter.POINT)
	icon = rl.LoadImage("assets/icon.png")
	rl.SetWindowIcon(icon)
	font = rl.LoadFont("assets/fonts/PixelifySans-Regular.ttf")

	bgm = rl.LoadMusicStream("assets/audio/bgm.wav")
	sfx_footstep = rl.LoadSound("assets/audio/footstep.ogg")
	sfx_pushbox = rl.LoadSound("assets/audio/pushbox.ogg")
	sfx_switch = rl.LoadSound("assets/audio/switch.ogg")
	sfx_activate = rl.LoadSound("assets/audio/activate.ogg")
	sfx_undo = rl.LoadSound("assets/audio/undo.ogg")
	sfx_complete = rl.LoadSound("assets/audio/complete.ogg")
	rl.SetSoundVolume(sfx_undo, 0.5)

	if ok := level_load_from_txt(1); ok {
		current_level_index = 1
	}
}

// :ui bounds positions
init_ui_bounds :: proc() {
	visible := atlas_textures[.Visible].rect

	clear(&eyeball_bounds)
	for i in 0 ..< len(world.layers) {
		append(
			&eyeball_bounds,
			rl.Rectangle{630, f32(1 + i * 32), visible.width, visible.height / 2},
		)
	}
}

// :update
game_update :: proc() {
	get_move_input()
	apply_movement()

	// toggle layer's visibility
	for i in 0 ..< len(world.layers) {
		if rl.CheckCollisionPointRec(mouse_position, eyeball_bounds[i]) {
			rl.DrawRectangleLinesEx(
				rl.Rectangle{eyeball_bounds[i].x + 10, eyeball_bounds[i].y + 5, 130, 30},
				2,
				MY_PURPLE,
			)
			if rl.IsMouseButtonPressed(.LEFT) {
				should_show_tip = false
				toggle_layer_visibility(i)
				rl.PlaySound(sfx_switch)
			}
		}
	}

	is_completed = check_completion()

	// R to reset
	if rl.IsKeyPressed(.R) {
		level_reload()
		rl.PlaySound(sfx_undo)
	}

	// Z to undo
	if rl.IsKeyPressed(.Z) {
		undo()
	}

	//  [] to switch level for test
	if rl.IsKeyPressed(.LEFT_BRACKET) {
		level_load_by_index(current_level_index - 1)
	}
	if rl.IsKeyPressed(.RIGHT_BRACKET) {
		level_load_by_index(current_level_index + 1)
	}
}

overview_update :: proc() {
	compute_overview_layout()
	read_move_input()
	push_undo_record()
	apply_movement()

	mouse_position = get_overview_mouse_position()

	for i in 0 ..< len(world.layers) {
		if rl.CheckCollisionPointRec(mouse_position, overview_eye_bounds[i]) {
			if rl.IsMouseButtonPressed(.LEFT) {
				toggle_layer_visibility(i)
				rl.PlaySound(sfx_switch)
			}
		}
	}

	is_completed = check_completion()

	if rl.IsKeyPressed(.ESCAPE) {
		is_overview = false
		rl.PlaySound(sfx_switch)
	}
}

get_overview_mouse_position :: proc() -> [2]f32 {
	rl.SetMouseOffset(
		-i32((f32(rl.GetScreenWidth()) - OVERVIEW_SCREEN_WIDTH * overview_scale) * 0.5),
		-i32((f32(rl.GetScreenHeight()) - OVERVIEW_SCREEN_HEIGHT * overview_scale) * 0.5),
	)
	rl.SetMouseScale(1 / overview_scale, 1 / overview_scale)
	mouse_position = rl.GetMousePosition()
	return mouse_position
}

get_mouse_position :: proc() -> [2]f32 {
	mouse_position = rl.GetMousePosition()
	rl.SetMouseOffset(
		-i32((f32(rl.GetScreenWidth()) - GAME_SCREEN_WIDTH * scale) * 0.5),
		-i32((f32(rl.GetScreenHeight()) - GAME_SCREEN_HEIGHT * scale) * 0.5),
	)
	rl.SetMouseScale(1 / scale, 1 / scale)
	return mouse_position / ZOOM
}

undo :: proc() {
	if len(undo_stack) == 0 {
		return
	}
	rl.PlaySound(sfx_undo)
	record := pop(&undo_stack)
	world = record.world
	log.info("undo")
}
