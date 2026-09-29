# Test image data

These are the classic digital-image-processing sample photographs used by the
`0306.tests` Catch2 suite (the same fixtures as `0305/tests/data`). They are
deterministic fixtures, downscaled from the images bundled with OpenCV's
`samples/data` (OpenCV is distributed under the Apache License 2.0):

| file               | source            | notes                              |
| ------------------ | ----------------- | ---------------------------------- |
| `lena.png`         | OpenCV `lena.jpg` | 512x512 -> 256x256, RGB            |
| `baboon.png`       | OpenCV `baboon.jpg` | 512x512 -> 256x256, RGB          |
| `board.png`        | OpenCV `board.jpg` | resized to 256x256, RGB            |
| `checkerboard.png` | generated         | 256x256 synthetic checkerboard     |

All files are stored as 8-bit PNG so the decoder output is exactly reproducible.
They are used only as test inputs; no derivative of them is distributed.
