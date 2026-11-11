# 原生播放验证视频

`playback.mp4` 是 FFmpeg 从零生成的 160×90、5 fps、240 秒灰阶变化 H.264 视频，不含音轨、账号或外部媒体。仅供独立 debug 验证入口，通过编译参数进入沙箱临时目录；正式 main 入口不引用，不作为应用资源发布。

生成：`ffmpeg -f lavfi -i "nullsrc=size=160x90:rate=5,geq=lum='32+mod(N,180)':cb=128:cr=128" -t 240 -an -c:v libx264 -preset ultrafast -crf 35 -pix_fmt yuv420p -threads 1 -movflags +faststart playback.mp4`。

SHA-256：`89997eb90867d5471e8160b27281a2c13198a17789ff7c35dc791b080ec8a294`。初始 Y4M 夹具未进入播放，失败记录独立保存；更换常用媒体格式不改变后台策略，仍须验证真实播放和遮挡事件。
