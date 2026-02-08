package heightmaps

import "glue"
import gl "vendor:OpenGL"

import "core:bytes"
import "core:log"
import "core:slice"
import "core:math"
import "core:math/linalg"
import "core:image"
import "core:image/png"
import "core:os"

Vec2 :: [2]f32
Vec3 :: [3]f32
Mat4 :: matrix[4, 4]f32

VERTEX_SOURCE :: #load("terrain.vert", string)
FRAGMENT_SOURCE :: #load("terrain.frag", string)

WINDOW_TITLE  :: "Heightmaps"
WINDOW_WIDTH  :: 1920
WINDOW_HEIGHT :: 1080
WINDOW_ASPECT_RATIO :: 1920.0 / 1080.0

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
	defer log.destroy_console_logger(context.logger)

	if !glue.create_window(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE) do log.panic("Failed to create a window.")
	defer glue.destroy_window()

	glue.set_cursor_enabled(false)
	glue.set_raw_mouse_motion_enabled(true)

	shader, shader_ok := glue.create_simple_shader(VERTEX_SOURCE, FRAGMENT_SOURCE)
	if !shader_ok do log.panic("Failed to compile the shader.")
	defer glue.destroy_shader(shader)

	terrain_mesh, terrain_mesh_ok := create_terrain_mesh("iceland.png")
	if !terrain_mesh_ok do log.panic("Failed to create the terrain mesh.")
	defer destroy_terrain_mesh(&terrain_mesh)

	camera := glue.Camera {
		position = { 0, 100, 0 },
		yaw = math.to_radians(f32(-90.0)),
	}

	model_uniform := glue.get_uniform(shader, "model", Mat4)
	view_uniform := glue.get_uniform(shader, "view", Mat4)
	projection_uniform := glue.get_uniform(shader, "projection", Mat4)

	glue.use_shader(shader)

	gl.ClearColor(0, 0, 0, 1)
	gl.Enable(gl.DEPTH_TEST)

	prev_time := glue.time()

	for !glue.window_should_close() {
		glue.poll_events()

		for event in glue.pop_event() {
			#partial switch event in event {
			case glue.Key_Pressed_Event:
				if event.key == .Escape do glue.close_window()
			}
		}

		time := glue.time()
		dt := f32(time - prev_time)
		prev_time = time

		LOOK_SPEED :: 1
		cursor_position_delta := linalg.array_cast(glue.cursor_position_delta(), f32)
		camera.yaw += cursor_position_delta.x * LOOK_SPEED * 0.001
		camera.pitch += -cursor_position_delta.y * LOOK_SPEED * 0.001
		camera.pitch = clamp(camera.pitch, math.to_radians(f32(-89)), math.to_radians(f32(89)))

		camera_vectors := glue.camera_vectors(camera)

		MOVEMENT_SPEED :: 100
		if glue.key_pressed(.W) do camera.position += camera_vectors.forward * MOVEMENT_SPEED * dt
		if glue.key_pressed(.S) do camera.position -= camera_vectors.forward * MOVEMENT_SPEED * dt
		if glue.key_pressed(.A) do camera.position -= camera_vectors.right   * MOVEMENT_SPEED * dt
		if glue.key_pressed(.D) do camera.position += camera_vectors.right   * MOVEMENT_SPEED * dt

		model: Mat4 = 1
		view := linalg.matrix4_look_at(eye = camera.position,
					       centre = camera.position + camera_vectors.forward,
					       up = camera_vectors.up)
		projection := linalg.matrix4_perspective(fovy = math.to_radians(f32(45)),
							 aspect = WINDOW_ASPECT_RATIO,
							 near = 0.1,
							 far = 1000)

		glue.set_uniform(model_uniform, model)
		glue.set_uniform(view_uniform, view)
		glue.set_uniform(projection_uniform, projection)

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		glue.bind_mesh(terrain_mesh)

		for i in 0..<terrain_mesh.strip_count {
			strip_indices_offset := size_of(Terrain_Index) * terrain_mesh.vertices_per_strip * i
			gl.DrawElements(gl.TRIANGLE_STRIP,
					i32(terrain_mesh.vertices_per_strip),
					terrain_mesh.mesh.index_type,
					cast(rawptr)uintptr(terrain_mesh.mesh.index_data_offset + strip_indices_offset))
		}

		glue.swap_buffers()
		free_all(context.temp_allocator)
	}
}

Terrain_Mesh :: struct {
	using mesh: glue.Mesh,
	strip_count: u32,
	vertices_per_strip: u32,
}

Terrain_Vertex :: struct {
	position: Vec3,
}

@(rodata)
terrain_vertex_format := [?]glue.Vertex_Attribute{
	.Float_3,
}

Terrain_Index :: u32

create_terrain_mesh :: proc(path: string) -> (mesh: Terrain_Mesh, ok := false) {
	heightmap_file_data := os.read_entire_file(path, context.temp_allocator) or_return
	heightmap_image, error := image.load(heightmap_file_data, {}, context.temp_allocator)
	if error != nil {
		log.errorf("Failed to load heightmap from file `%v`: %v", path, error)
		return
	}
	defer image.destroy(heightmap_image, context.temp_allocator)

	pixels := bytes.buffer_to_bytes(&heightmap_image.pixels)

	vertex_count := heightmap_image.width * heightmap_image.height
	vertices := make([dynamic]Terrain_Vertex, 0, vertex_count, context.temp_allocator)

	Y_SCALE :: 64.0 / 256.0
	Y_SHIFT :: -16.0

	for i in 0..<heightmap_image.height {
		for j in 0..<heightmap_image.width {
			assert(heightmap_image.channels == 4)
			heightmap_y := cast(f32)pixels[(i * heightmap_image.width + j) * 4]
			x := f32(-heightmap_image.height / 2 + i)
			y := heightmap_y * Y_SCALE + Y_SHIFT
			z := f32(-heightmap_image.width / 2 + j)
			append(&vertices, Terrain_Vertex{{ x, y, z }})
		}
	}

	index_count := heightmap_image.width * heightmap_image.height * 6
	indices := make([dynamic]Terrain_Index, 0, index_count, context.temp_allocator)

	for i in 0..<heightmap_image.height - 1 {
		for j in 0..<heightmap_image.width {
			for k in 0..<2 {
				append(&indices, Terrain_Index(j + heightmap_image.width * (i + k)))
			}
		}
	}

	mesh.strip_count = u32(heightmap_image.height - 1)
	mesh.vertices_per_strip = u32(heightmap_image.width * 2)

	glue.create_mesh(&mesh,
			 slice.to_bytes(vertices[:]),
			 size_of(Terrain_Vertex),
			 terrain_vertex_format[:],
			 slice.to_bytes(indices[:]),
			 glue.gl_index(Terrain_Index))

	ok = true
	return
}

destroy_terrain_mesh :: proc(mesh: ^Terrain_Mesh) {
	glue.destroy_mesh(&mesh.mesh)
}

@(export, rodata)
NvOptimusEnablement: u32 = 1
@(export, rodata)
AmdPowerXpressRequestHighPerformance: u32 = 1
