# TokenDance MiniMax H3

`minimax_video.py` 是一个零依赖命令行客户端，通过 TokenDance MiniMax v2 网关调用 MiniMax H3 视频生成接口。API Key 只从环境变量读取，避免写入仓库。

```sh
export TOKENDANCE_API_KEY="你的 TokenDance Key"
python3 scripts/minimax_video.py "一只橘猫在雨后的城市街道慢慢骑自行车，电影感，8秒"
```

常用参数：

```sh
python3 scripts/minimax_video.py "海边日落" \
  --image "https://example.com/first-frame.jpg" \
  --duration 8 \
  --model minimax-h3
```

网关地址默认是 `https://tokendance.space`，脚本提交 `/gateway/minimax/v2/video_generation` 任务，再轮询 `/gateway/minimax/v2/query/video_generation/{id}`，成功后只输出 `task.content.url` 视频地址，便于继续用 `curl` 或下载工具处理。文生视频默认使用 `16:9`、`2K`、6 秒。

如果你的 TokenDance 文档版本使用了不同的路径，可通过 `TOKENDANCE_VIDEO_CREATE_PATH`、`TOKENDANCE_VIDEO_STATUS_PATH`（其中用 `{id}` 表示任务 ID）或对应命令行参数覆盖。
