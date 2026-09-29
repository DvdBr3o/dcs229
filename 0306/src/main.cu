#include "Unsharp.cuh"

#include "dcs229/Image.hpp"

#include <CLI/CLI.hpp>

#include <cstddef>
#include <cstdint>
#include <exception>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

// Command-line driver for the unsharp-masking image enhancement.
//
//   ./0306 <input> <output> [options]
//   ./0306 -i in.png -o out.png --amount 1.5 --sigma 2.0 --quality 95
//
// Reads any format `common` can decode (PNG/JPEG), runs the CUDA unsharp mask
// and writes the enhanced image, choosing the encoder from the output
// extension (.png / .jpg / .jpeg).
int main(int argc, char** argv) {
	CLI::App app {"Unsharp masking image enhancement (CUDA)"};
	app.set_version_flag("--version", "0306 1.0");

	std::string pos_input;
	std::string pos_output;
	std::string opt_input;
	std::string opt_output;
	int			quality = 90;
	double		amount	= 1.0;
	double		sigma	= 1.0;
	bool		quiet	= false;

	// Positional paths are the common case; -i/-o are also accepted as
	// alternatives. The two spellings are merged after parsing.
	app.add_option("infile", pos_input, "input image path (same as -i/--input)");
	app.add_option("outfile", pos_output, "output image path (same as -o/--output)");
	app.add_option("-i,--input", opt_input, "input image path (alternative to positional)");
	app.add_option("-o,--output", opt_output, "output image path (alternative to positional)");
	app.add_option("-a,--amount", amount, "mask strength (>0 sharpens, 0 copies input)")
		->check(CLI::NonNegativeNumber)
		->capture_default_str();
	app.add_option("-s,--sigma", sigma, "Gaussian blur standard deviation in pixels")
		->check(CLI::PositiveNumber)
		->capture_default_str();
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
		dcs229::proj0306::unsharp_sharpen(
			view.data,
			enhanced.data(),
			view.width,
			view.height,
			static_cast<float>(sigma),
			static_cast<float>(amount)
		);

		dcs229::save_image(
			{.data	 = enhanced.data(),
			 .size	 = enhanced.size(),
			 .width	 = view.width,
			 .height = view.height},
			out_path,
			quality
		);

		if (!quiet) {
			std::cout << "unsharp: " << view.width << 'x' << view.height << " (amount=" << amount
					  << ", sigma=" << sigma << ") -> " << out_path.string() << '\n';
		}
	} catch (const std::exception& e) {
		std::cerr << "error: " << e.what() << '\n';
		return 1;
	}
	return 0;
}
