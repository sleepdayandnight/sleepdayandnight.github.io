# 队友请就位

大学生破冰活动的大屏主持端和手机参与端。GitHub Pages 托管页面，Supabase Realtime 同步抽色、匿名便签和点赞。

## 发布前设置

1. 在 [Supabase](https://supabase.com/) 用 GitHub 账号或邮箱创建项目。
2. 打开项目左侧的 SQL Editor，新建查询，完整粘贴并运行 `supabase-setup.sql`。如果之前运行过，直接再次运行即可；脚本已支持重复执行。
3. 到 Project Settings 的 API 页面，复制 Project URL 和 anon public key。
4. 将它们填到 `supabase-config.js` 的 `url` 和 `anonKey` 中。不要使用 `service_role` key。
5. 在 Database 的 Replication 页面确认 `rooms`、`players`、`notes` 和 `task_claims` 已加入 `supabase_realtime` 发布。
6. 将本文件夹推送到 GitHub 仓库，在 Pages 设置中选择从 `main` 分支根目录发布。

发布后的大屏地址是 `https://你的用户名.github.io/仓库名/`。大屏自动生成手机参与端二维码；手机访问同一地址附加 `?mode=join` 即可进入。每次首次打开大屏，会生成一个新的活动房间编号。

## 手机任务核验

进入手机端后，先填写昵称并抽取颜色，系统会自动生成一张匿名活动身份卡。主持人在“请问可不可以”页面点击“开始 15 分钟”，同学在手机任务列表中点击“发起核验”，把一次性 6 位验证码展示给伙伴。伙伴在自己手机对应的任务输入框填写验证码并点击“确认”，任务才会计入队伍统计和个人前三名。每个任务只能核验一次，同一伙伴不能重复确认同一人的多个任务；验证码 3 分钟内有效且只能使用一次，双方必须是不同的活动身份。

任务核验需要再次运行更新后的 `supabase-setup.sql`，并在 Supabase 的 Replication 页面确认 `task_claims` 已开启。网页端只使用 publishable/anon key，不要填写 service_role key。

## 图片

把看图复刻的参考照片放入 `assets/photos/`，然后在 `index.html` 中把对应图片地址改为 `assets/photos/文件名.jpg`。

## 隐私

昵称只用于手机端确认个人抽色和提交记录。大屏只显示队伍颜色、人数、匿名便签内容与点赞数。
