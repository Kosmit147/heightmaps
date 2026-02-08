package heightmaps

import "glue"
import gl "vendor:OpenGL"

import "core:log"
import "core:slice"
import "core:math"
import "core:math/linalg"

Vec2 :: [2]f32
Mat4 :: matrix[4, 4]f32

Vertex :: struct { position: Vec2 }
@(rodata) vertex_format := [?]glue.Vertex_Attribute{ .Float_2 }

VERTEX_SOURCE ::
`
#version 460 core

layout (location = 0) in vec2 in_position;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

void main() {
	gl_Position = projection * view * model * vec4(in_position, 0.0, 1.0);
}
`

FRAGMENT_SOURCE ::
`
#version 460 core

out vec4 out_color;

void main() {
	out_color = vec4(1.0);
}
`

@(rodata)
vertices := [4]Vertex{
	{ position = { -0.5, -0.5 } },
	{ position = { -0.5,  0.5 } },
	{ position = {  0.5,  0.5 } },
	{ position = {  0.5, -0.5 } },
}

@(rodata)
indices := [6]u32{ 0, 1, 2, 0, 2, 3 }

WINDOW_TITLE  :: "Example"
WINDOW_WIDTH  :: 1920
WINDOW_HEIGHT :: 1080
WINDOW_ASPECT_RATIO :: 1920.0 / 1080.0

main :: proc() {
	context.logger = log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
	defer log.destroy_console_logger(context.logger)

	if !glue.create_window(WINDOW_WIDTH, WINDOW_HEIGHT, WINDOW_TITLE) do log.panic("Failed to create a window")
	defer glue.destroy_window()

	glue.set_cursor_enabled(false)
	glue.set_raw_mouse_motion_enabled(true)

	vertex_array: glue.Vertex_Array
	glue.create_vertex_array(&vertex_array)
	defer glue.destroy_vertex_array(&vertex_array)

	vertex_buffer: glue.Gl_Buffer
	glue.create_static_gl_buffer_with_data(&vertex_buffer, slice.to_bytes(vertices[:]))
	defer glue.destroy_gl_buffer(&vertex_buffer)

	index_buffer: glue.Gl_Buffer
	glue.create_static_gl_buffer_with_data(&index_buffer, slice.to_bytes(indices[:]))
	defer glue.destroy_gl_buffer(&index_buffer)

	shader, shader_ok := glue.create_shader(VERTEX_SOURCE, FRAGMENT_SOURCE)
	if !shader_ok do log.panic("Failed to compile the shader.")
	defer glue.destroy_shader(shader)

	camera := glue.Camera {
		position = { 0, 0, 2 },
		yaw = math.to_radians(f32(-90.0)),
	}

	model_uniform := glue.get_uniform(shader, "model", Mat4)
	view_uniform := glue.get_uniform(shader, "view", Mat4)
	projection_uniform := glue.get_uniform(shader, "projection", Mat4)

	glue.bind_vertex_array(vertex_array)
	glue.set_vertex_array_format(vertex_array, vertex_format[:])
	glue.bind_vertex_buffer(vertex_array, vertex_buffer, size_of(Vertex))
	glue.bind_index_buffer(vertex_array, index_buffer)
	glue.use_shader(shader)

	gl.ClearColor(0, 0, 0, 1)

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

		MOVEMENT_SPEED :: 5
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

		gl.Clear(gl.COLOR_BUFFER_BIT)
		gl.DrawElements(gl.TRIANGLES, len(indices), glue.gl_index(u32), nil)

		glue.swap_buffers()
		free_all(context.temp_allocator)
	}
}
