# 队友请就位

大学生破冰活动的大屏主持端和手机参与端。GitHub Pages 托管页面，Supabase Realtime 同步抽色、匿名便签和点赞。

## 发布前设置

1. 在 [Supabase](https://supabase.com/) 用 GitHub 账号或邮箱创建项目。
2. 打开项目左侧的 SQL Editor，新建查询，完整粘贴并运行 `supabase-setup.sql`。如果之前运行过，直接再次运行即可；脚本已支持重复执行。
3. 到 Project Settings 的 API 页面，复制 Project URL 和 anon public key。
4. 将它们填到 `supabase-config.js` 的 `url` 和 `anonKey` 中。不要使用 `service_role` key。
5. 在 Database 的 Replication 页面确认 `rooms`、`players` 和 `notes` 已加入 `supabase_realtime` 发布。
6. 将本文件夹推送到 GitHub 仓库，在 Pages 设置中选择从 `main` 分支根目录发布。

发布后的大屏地址是 `https://你的用户名.github.io/仓库名/`。大屏自动生成手机参与端二维码；手机访问同一地址附加 `?mode=join` 即可进入。每次首次打开大屏，会生成一个新的活动房间编号。

## 图片

把看图复刻的参考照片放入 `assets/photos/`，然后在 `index.html` 中把对应图片地址改为 `assets/photos/文件名.jpg`。

## 隐私

昵称只用于手机端确认个人抽色和提交记录。大屏只显示队伍颜色、人数、匿名便签内容与点赞数。
