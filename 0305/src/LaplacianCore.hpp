#pragma once

// Classical Laplacian image enhancement.
//
// Pixels are 8-bit RGBA (the canonical format produced by dcs229::ImageView),
// so a pixel occupies 4 consecutive bytes. The operator works on the three
// colour channels and copies alpha through untouched.
//
// The discrete Laplacian uses the standard 4-neighbour (cross) stencil
//
//         0  1  0
//     L = 1 -4  1
//         0  1  0
//
// and the *enhanced* image is obtained by subtracting it from the original
// ("unsharp" masking form used in Gonzalez & Woods, Digital Image Processing):
//
//     g(x, y) = f(x, y) - Lap{f}(x, y)
//
// which is exactly what a 3x3 correlation kernel
//
//          0 -1  0
//     K = -1  5 -1
//          0 -1  0
//
// computes. Border pixels are left unchanged because the 3x3 stencil is only
// defined where all four neighbours exist.
//
// The template parameter `T` is the channel type: `uint8_t` (default) for the
// 8-bit path, `float`/`double` for an exact reference used by the tests.

#include <concepts>
#include <cstddef>
#include <cstdint>
#include <type_traits>

namespace dcs229::proj0305 {
// 4-neighbour Laplacian at `(x, y)` for a single channel, read through
// `at(x, y) -> channel_type`. Result is returned in the channel's wider type so
// it can be compared against zero without overflow (e.g. int for uint8_t).
template<typename Channel, typename Sampler>
constexpr auto laplacian_at(const Sampler& at, size_t x, size_t y) noexcept {
	using acc_t = std::conditional_t<
		sizeof(Channel) < sizeof(int),
		int,
		std::conditional_t<std::is_floating_point_v<Channel>, Channel, long long>>;
	const acc_t center = static_cast<acc_t>(at(x, y));
	const acc_t up	   = static_cast<acc_t>(at(x, y - 1));
	const acc_t down   = static_cast<acc_t>(at(x, y + 1));
	const acc_t left   = static_cast<acc_t>(at(x - 1, y));
	const acc_t right  = static_cast<acc_t>(at(x + 1, y));
	return static_cast<acc_t>(up + down + left + right - 4 * center);
}

// Clamp a Laplacian-enhanced value back into the channel range.
template<typename Channel, typename Value>
constexpr auto clamp_channel(Value value) noexcept -> Channel {
	if constexpr (std::is_floating_point_v<Channel>) {
		return static_cast<Channel>(value);
	} else {
		constexpr auto lo = static_cast<Value>(0);
		constexpr auto hi = static_cast<Value>(255);
		if (value < lo)
			return static_cast<Channel>(lo);
		if (value > hi)
			return static_cast<Channel>(hi);
		return static_cast<Channel>(value);
	}
}

// Sharpen a single channel: g = f - Lap{f}, clamped. Returns the new value.
template<typename Channel, typename Sampler>
constexpr auto sharpen_channel(const Sampler& at, size_t x, size_t y) noexcept -> Channel {
	using acc_t = std::conditional_t<
		sizeof(Channel) < sizeof(int),
		int,
		std::conditional_t<std::is_floating_point_v<Channel>, Channel, long long>>;
	const auto center = static_cast<acc_t>(at(x, y));
	const auto lap	  = laplacian_at<Channel>(at, x, y);
	return clamp_channel<Channel>(center - lap);
}

// Host-side, single-threaded reference over an interleaved buffer of `Channel`
// with `channels` components per pixel. `stride` is the number of `Channel`
// elements per row (== width * channels for a packed buffer). The last channel
// is treated as alpha and copied through. Borders (x == 0 || y == 0 ||
// x == width-1 || y == height-1) are copied through unchanged.
template<typename Channel>
auto sharpen_reference(
	const Channel* src, Channel* dst, size_t width, size_t height, size_t channels, size_t stride
) -> void {
	const auto* base = src;
	const auto	w	 = width;
	const auto	h	 = height;
	const auto	ch	 = channels;

	auto		at	 = [&](size_t x, size_t y, size_t c) -> Channel {
		return base[y * stride + x * ch + c];
	};

	auto* out = dst;
	for (size_t y = 0; y < h; ++y) {
		for (size_t x = 0; x < w; ++x) {
			for (size_t c = 0; c + 1 < ch; ++c) {  // skip alpha (last channel)
				auto sample = [&](size_t sx, size_t sy) -> Channel { return at(sx, sy, c); };
				out[y * stride + x * ch + c] = (x == 0 || y == 0 || x + 1 == w || y + 1 == h) ?
												   at(x, y, c) :
												   sharpen_channel<Channel>(sample, x, y);
			}
			out[y * stride + x * ch + (ch - 1)] = at(x, y, ch - 1);	 // alpha
		}
	}
}
}  // namespace dcs229::proj0305
