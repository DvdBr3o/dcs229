#include "Laplacian.cuh"

#include "dcs229/Image.hpp"

#include <CLI/CLI.hpp>

#include <cstddef>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

// Command-line driver for the Laplacian image enhancement.
//
//   ./0305 <input> <output> [options]
//   ./0305 -i in.png -o out.png --quality 95 --quiet
//
// Reads any format `common` can decode (PNG/JPEG), runs the CUDA Laplacian
// sharpening and writes the enhanced image, choosing the encoder from the
// output extension (.png / .jpg / .jpeg).
int main(int argc, char** argv) {
	CLI::App app {"Laplacian image enhancement (CUDA)"};
	app.set_version_flag("--version", "0305 1.0");

	std::string pos_input;
	std::string pos_output;
	std::string opt_input;
	std::string opt_output;
	int			quality = 90;
	bool		quiet	= false;

	// Positional paths are the common case; -i/-o are also accepted as
	// alternatives (useful in scripts). The two spellings are merged after
	// parsing so either can fill each required value.
	app.add_option("infile", pos_input, "input image path (same as -i/--input)");
	app.add_option("outfile", pos_output, "output image path (same as -o/--output)");
	app.add_option("-i,--input", opt_input, "input image path (alternative to positional)");
	app.add_option("-o,--output", opt_output, "output image path (alternative to positional)");
	app.add_option("-q,--quality", quality, "JPEG quality, 1-100")
		->check(CLI::Range(1, 100))
		->capture_default_str();
	app.add_flag("--quiet", quiet, "suppress progress output");

	try {
		CLI11_PARSE(app, argc, argv);
	} catch (const CLI::ParseError& e) { return app.exit(e); }

	const std::string input	 = pos_input.empty() ? opt_input : pos_input;
	const std::string output = pos_output.empty() ? opt_output : pos_output;

	if (input.empty()) {
		std::cerr << "error: an input image is required (positional or -i/--input)\n";
		return 1;
	}
	if (output.empty()) {
		std::cerr << "error: an output image is required (positional or -o/--output)\n";
		return 1;
	}
	if (!std::filesystem::exists(input)) {
		std::cerr << "error: input file does not exist: " << input << '\n';
		return 1;
	}

	try {
		const auto in_path	= std::filesystem::path(input);
		const auto out_path = std::filesystem::path(output);

		// `load_image` owns the decoded pixels, so the view stays valid.
		const auto		  image = dcs229::load_image(in_path);
		const auto		  view	= image.view();

		std::vector<char> enhanced(view.size);
		dcs229::proj0305::laplacian_sharpen(view.data, enhanced.data(), view.width, view.height);

		dcs229::save_image(
			{.data	 = enhanced.data(),
			 .size	 = enhanced.size(),
			 .width	 = view.width,
			 .height = view.height},
			out_path,
			quality
		);

		if (!quiet) {
			std::cout << "laplacian: " << view.width << 'x' << view.height << " -> "
					  << out_path.string() << '\n';
		}
	} catch (const std::exception& e) {
		std::cerr << "error: " << e.what() << '\n';
		return 1;
	}
	return 0;
}
