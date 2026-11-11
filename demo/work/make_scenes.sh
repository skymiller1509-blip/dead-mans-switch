#!/bin/bash
set -e
cd "$(dirname "$0")/.."
mk() { # frame vo dur out
  ffmpeg -y -v error -loop 1 -i "frames/$1" -i "work/vo/$2" -filter_complex "[1:a]apad[a]" -map 0:v -map "[a]" -t "$3" -c:v libx264 -preset fast -crf 23 -pix_fmt yuv420p -r 25 -c:a aac -movflags +faststart "work/scenes/$4"
}
mk 01_hook.png 01.mp3 6.56 s01.mp4
mk 02_fix.png 02.mp3 14.89 s02.mp4
mk 03_how.png 03.mp3 22.81 s03.mp4
mk 07_frontend.png 04.mp3 11.72 s04.mp4
mk 04_proof1.png 05.mp3 11.17 s05.mp4
mk 05_proof2.png 06.mp3 9.03 s06.mp4
mk 08_explorer_lasna.png 07.mp3 6.25 s07.mp4
mk 06_end.png 08.mp3 6.85 s08.mp4
printf "file 'work/scenes/s01.mp4'\nfile 'work/scenes/s02.mp4'\nfile 'work/scenes/s03.mp4'\nfile 'work/scenes/s04.mp4'\nfile 'work/scenes/s05.mp4'\nfile 'work/scenes/s06.mp4'\nfile 'work/scenes/s07.mp4'\nfile 'work/scenes/s08.mp4'\n" > work/concat.txt
ffmpeg -y -v error -f concat -safe 0 -i work/concat.txt -c copy dead_mans_switch_demo.mp4
echo BUILT
ffprobe -v error -show_entries format=duration,size,bit_rate -show_entries stream=codec_name,width,height,r_frame_rate -of default=noprint_wrappers=1 dead_mans_switch_demo.mp4
ls -lh dead_mans_switch_demo.mp4
