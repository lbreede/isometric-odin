/*
	*******************************************************************************************************************
	*
	*  Cartesian to isometric conversions
	*      - When commiting to true isometric tiles with a 2:1 aspect ratio, we can use one of two conversion methods:
	*        1. Matrix transformation: `{1, 0.5, -1, 0.5}`
	*        2. Element-wise transformation: `x'=x-y, y'=(x+y)/2`
	*      - Alternatively, we can leave the aspect ratio to the texture dimensions after the conversion:
	*        1. Matrix: `position *= {1, 1, -1, 1}`
	*        2. Element-wise: `position.x = x - y; position.y = x + y`
	*        This is followed by `position *= {TILE_WIDTH, TILE_HEIGHT}` which is where the aspect ration comes from
	*
	*******************************************************************************************************************
*/

package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

SCREEN_WIDTH :: 1920
SCREEN_HEIGHT :: 1080

MAP_WIDTH :: 16

// Most of these constants assume an isometric projection with a 2:1 aspect ratio

TILE_WIDTH :: 256
TILE_HEIGHT :: 128
TILE_FULL_HEIGHT :: 512

X_STEP :: 2
Y_STEP :: 1
CHARACTER_SPEED :: 256


M_TO_ISO :: matrix[2, 2]f32{
	+1.0, -1.0, 
	+0.5, +0.5, 
}

M_TO_CART :: matrix[2, 2]f32{
	+0.5, +1.0, 
	-0.5, +1.0, 
}

load_directory_of_textures :: proc(pattern: string) -> map[string]rl.Texture2D {
	textures := make(map[string]rl.Texture2D)

	matches, _ := filepath.glob(pattern)
	for match in matches {
		path := strings.clone(match)
		textures[path] = rl.LoadTexture(fmt.ctprintf("%s", match))
	}
	for match in matches {
		delete(match)
	}
	delete(matches)

	return textures
}

unload_directory_of_textures :: proc(textures: map[string]rl.Texture2D) {
	for path, tex in textures {
		delete(path)
		rl.UnloadTexture(tex)
	}
	delete(textures)
}

to_isometric :: proc(cartesian: rl.Vector2) -> rl.Vector2 {
	return {cartesian.x - cartesian.y, (cartesian.x + cartesian.y) / 2}
}

to_cartesian :: proc(isometric: rl.Vector2) -> rl.Vector2 {
	return {isometric.x / 2 + isometric.y, isometric.y - isometric.x / 2}
}


draw_background_grid :: proc(color: rl.Color) {
	a, b := 16, 9
	grid_tile_size := i32(SCREEN_WIDTH / a)
	for i in 0 ..< a * b {
		x, y := i32(i % a), i32(i / a)
		x *= grid_tile_size
		y *= grid_tile_size
		rl.DrawRectangleLines(x, y, grid_tile_size, grid_tile_size, color)
	}
}

handle_character_movement_input :: proc() -> rl.Vector2 {
	delta: rl.Vector2
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {delta.x += X_STEP}
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {delta.x -= X_STEP}
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {delta.y += Y_STEP}
	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {delta.y -= Y_STEP}
	return delta
}

get_character_direction :: proc(delta: rl.Vector2, current: Direction) -> Direction {
	switch delta {
	case {X_STEP, -Y_STEP}:
		return .North
	case {X_STEP, 0}:
		return .NorthEast
	case {X_STEP, Y_STEP}:
		return .East
	case {0, Y_STEP}:
		return .SouthEast
	case {-X_STEP, Y_STEP}:
		return .South
	case {-X_STEP, 0}:
		return .SouthWest
	case {-X_STEP, -Y_STEP}:
		return .West
	case {0, -Y_STEP}:
		return .NorthWest
	case:
		return current
	}
}


draw_character :: proc(character: Character, textures: ^map[string]rl.Texture2D) {
	tex: rl.Texture2D
	if character.is_moving {
		anim_index := int(math.mod(character.animation * 15, 10))
		tex =
			textures[fmt.tprintf("res/image/character/Male_%d_Run%d.png", character.direction, anim_index)]
	} else {
		tex = textures[fmt.tprintf("res/image/character/Male_%d_Idle0.png", character.direction)]
	}
	rl.DrawTextureV(tex, character.position, rl.WHITE)
}


Direction :: enum {
	North,
	NorthEast,
	East,
	SouthEast,
	South,
	SouthWest,
	West,
	NorthWest,
}

Character :: struct {
	position:  rl.Vector2,
	direction: Direction,
	is_moving: bool,
	animation: f32,
}

main :: proc() {
	rl.SetTraceLogLevel(.ERROR)
	rl.SetConfigFlags({.MSAA_4X_HINT, .WINDOW_HIGHDPI, .VSYNC_HINT})
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Isometrisch")
	defer rl.CloseWindow()

	scene_textures := load_directory_of_textures("res/image/scene/*.png")
	defer unload_directory_of_textures(scene_textures)

	character_textures := load_directory_of_textures("res/image/character/*.png")
	defer unload_directory_of_textures(character_textures)

	camera := rl.Camera2D {
		offset = {SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2},
		target = {TILE_WIDTH / 2, TILE_FULL_HEIGHT - TILE_HEIGHT},
		zoom   = 1,
	}

	floor_tilemap := load_tilemap_layer("main.tmx", "floor")
	defer unload_tilemap(floor_tilemap)
	walls_tilemap := load_tilemap_layer("main.tmx", "walls")
	defer unload_tilemap(walls_tilemap)
	objects_tilemap := load_tilemap_layer("main.tmx", "objects")
	defer unload_tilemap(objects_tilemap)

	character: Character

	rl.SetTargetFPS(60)
	for !rl.WindowShouldClose() {
		free_all(context.temp_allocator)

		dt := rl.GetFrameTime()

		character_dp := handle_character_movement_input()
		character.direction = get_character_direction(character_dp, character.direction)
		if linalg.length2(character_dp) > 0 {
			character.is_moving = true
			character.animation += dt
			// NOTE: normalization is disabled since it already describes different
			// speeds for different elements (the x component is double the y component)
			//
			// character_dp = linalg.normalize0(character_dp)
			camera.target += character_dp * CHARACTER_SPEED * dt
			character.position += character_dp * CHARACTER_SPEED * dt
		} else {
			character.is_moving = false
			character.animation = 0
		}

		rl.BeginDrawing();defer rl.EndDrawing()

		rl.ClearBackground(rl.SKYBLUE)

		draw_background_grid(rl.BLUE)

		rl.BeginMode2D(camera)
		zoom_speed: f32 = 1.0
		if rl.IsKeyDown(.J) {camera.zoom += zoom_speed * dt}
		if rl.IsKeyDown(.K) {camera.zoom -= zoom_speed * dt}

		draw_tilemap(floor_tilemap, &scene_textures)
		draw_tilemap(walls_tilemap, &scene_textures)
		draw_tilemap(objects_tilemap, &scene_textures)
		draw_character(character, &character_textures)

		rl.EndMode2D()

		rl.DrawFPS(10, 10)
	}
}
