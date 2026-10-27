# Guide pictures

The screenshots the guides show. Never edited by hand: the `guides`
self-test stages each surface with invented data (Jean-François Martaing,
Margot Martin, Camille, `example.com`) and captures it in the light and
dark appearance; the site shows the `-dark` twin in dark mode.

To make them all again, after a change people will see:

```sh
./script/build_and_run.sh remote guides && script/guide-images.sh
```

The first runs on the test Mac and brings the pictures back to
`dist/remote/guides`; the second copies them here, only when that run
was green and every picture has its dark twin.

Then look at each one before committing: no real names, paths, menu-bar
contents or apps of the test Mac. A guide shows one with
`![What it shows](images/<name>.png "Its caption")` on its own line.

A short loop of a few seconds can be an `.mp4` (H.264, no sound, under
2 MB): it plays silent, looping, in place of a picture.
