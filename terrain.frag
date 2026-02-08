#version 460 core

in float Y;

out vec4 out_color;

void main() {
	out_color = vec4(Y, Y, Y, 1.0);
}
