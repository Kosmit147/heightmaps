#version 460 core

layout (location = 0) in vec3 in_position;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

out float Y;

void main() {
	float y = in_position.y;
	y += 16.0;
	y /= (64.0 / 256.0);
	y /= 255.0;
	Y = y;
	gl_Position = projection * view * model * vec4(in_position, 1.0);
}
