#pragma once

// Classical unsharp masking.
//
// Pixels are 8-bit RGBA (the canonical format produced by dcs229::ImageView),
// so a pixel occupies 4 consecutive bytes. The operator works on the three
// colour channels and copies alpha through untouched.
//
// Unsharp masking is the other classic sharpening operator (Gonzalez & Woods,
// Digital Image Processing):
//
//     mask = f - blur(f)           <- the "unsharp" (high-pass) mask
//     g    = f + amount * mask     <- add the mask back to the original
//
// `blur` is a separable Gaussian with standard deviation `sigma`, so the whole
// enhancement is a separable two-pass convolution followed by a pointwise
// blend. `amount == 0` leaves the image unchanged; larger amounts sharpen
// harder. Borders use "replicate" padding (sample coordinates are clamped).
//
// The template parameter `Channel` is the channel type: `uint8_t` (default) for
// the 8-bit path, `float` for an exact reference used by the tests.

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace dcs229::proj0306 {
// Gaussian kernel for the given sigma, normalised to sum to 1. The radius is
// ceil(3*sigma) so taps past three standard deviations (99.7% of the mass) are
// dropped. sigma <= 0 is treated as sigma = 1e-3 (a (near-)identity kernel).
[[nodiscard]] inline auto gaussian_kernel(float sigma) -> std::vector<float> {
	const float		   s				= std::max(sigma, 1e-3f);
	const int		   radius			= std::max(0, static_cast<int>(std::ceil(3.0f * s)));
	const int		   size				= 2 * radius + 1;
	const float		   inv_two_sigma_sq = 1.0f / (2.0f * s * s);

	std::vector<float> kernel(static_cast<size_t>(size));
	float			   sum = 0.0f;
	for (int i = 0; i < size; ++i) {
		const float x				   = static_cast<float>(i - radius);
		kernel[static_cast<size_t>(i)] = std::exp(-(x * x) * inv_two_sigma_sq);
		sum += kernel[static_cast<size_t>(i)];
	}
	for (auto& weight : kernel) weight /= sum;
	return kernel;
}

// Radius (in pixels) of the kernel produced by gaussian_kernel(sigma).
[[nodiscard]] inline auto gaussian_radius(float sigma) -> int {
	return std::max(0, static_cast<int>(std::ceil(3.0f * std::max(sigma, 1e-3f))));
}

// Clamp an index into [0, extent) so border samples read the nearest edge pixel.
[[nodiscard]] inline auto clamp_index(long long index, size_t extent) -> size_t {
	if (index < 0)
		return 0;
	const auto upper = static_cast<long long>(extent) - 1;
	if (index > upper)
		return static_cast<size_t>(upper);
	return static_cast<size_t>(index);
}

// Clamp a blended result back into the channel range.
template<typename Channel>
[[nodiscard]] inline auto clamp_channel(float value) noexcept -> Channel {
	if (value <= 0.0f)
		return static_cast<Channel>(0);
	if (value >= 255.0f)
		return static_cast<Channel>(255);
	return static_cast<Channel>(value + 0.5f);
}

// Host-side, single-threaded, straightforward reference. Two explicit
// separable passes plus a pointwise blend. `stride` counts `Channel` elements
// per row (== width * channels for a packed buffer); the last channel is
// treated as alpha and copied through unchanged.
template<typename Channel>
auto unsharp_reference(
	const Channel* src, Channel* dst, size_t width, size_t height, size_t channels, size_t stride,
	float sigma, float amount
) -> void {
	const size_t w		= width;
	const size_t h		= height;
	const size_t ch		= channels;
	const auto	 kernel = gaussian_kernel(sigma);
	const int	 radius = gaussian_radius(sigma);

	// Temporary horizontal blur, same layout as the source.
	std::vector<float> tmp(w * h * ch);
	std::vector<float> blur(w * h * ch);

	auto at = [&](const std::vector<float>& buf, size_t x, size_t y, size_t c) -> float {
		return buf[y * stride + x * ch + c];
	};

	// Horizontal pass.
	for (size_t y = 0; y < h; ++y) {
		for (size_t x = 0; x < w; ++x) {
			for (size_t c = 0; c < ch; ++c) {
				float acc = 0.0f;
				for (int k = -radius; k <= radius; ++k) {
					const auto sx = clamp_index(static_cast<long long>(x) + k, w);
					acc += kernel[static_cast<size_t>(k + radius)]
						 * static_cast<float>(src[y * stride + sx * ch + c]);
				}
				tmp[y * stride + x * ch + c] = acc;
			}
		}
	}

	// Vertical pass.
	for (size_t y = 0; y < h; ++y) {
		for (size_t x = 0; x < w; ++x) {
			for (size_t c = 0; c < ch; ++c) {
				float acc = 0.0f;
				for (int k = -radius; k <= radius; ++k) {
					const auto sy = clamp_index(static_cast<long long>(y) + k, h);
					acc += kernel[static_cast<size_t>(k + radius)] * at(tmp, x, sy, c);
				}
				blur[y * stride + x * ch + c] = acc;
			}
		}
	}

	// Blend: g = f + amount * (f - blur).
	for (size_t y = 0; y < h; ++y) {
		for (size_t x = 0; x < w; ++x) {
			for (size_t c = 0; c + 1 < ch; ++c) {  // skip alpha
				const float f				 = static_cast<float>(src[y * stride + x * ch + c]);
				const float b				 = blur[y * stride + x * ch + c];
				dst[y * stride + x * ch + c] = clamp_channel<Channel>(f + amount * (f - b));
			}
			dst[y * stride + x * ch + (ch - 1)] = src[y * stride + x * ch + (ch - 1)];	// alpha
		}
	}
}
}  // namespace dcs229::proj0306
