# ZTE 服务器作业工具

服务器连接和 MATLAB 后台作业统一由 `zte-server.ps1` 管理。工具使用专用 SSH 密钥，不保存或传递登录密码。

## 常用命令

在项目根目录运行：

```powershell
# 检查 SSH、远端作业工具、MATLAB 和磁盘空间
pwsh -File .\tools\zte-server.ps1 check

# 上传一个 MATLAB 脚本并在后台启动
pwsh -File .\tools\zte-server.ps1 run .\task_example.m

# 查询一个任务；省略任务名时列出全部受管任务
pwsh -File .\tools\zte-server.ps1 status task_example
pwsh -File .\tools\zte-server.ps1 status

# 查看最新日志
pwsh -File .\tools\zte-server.ps1 tail task_example -Lines 80

# 打包并取回 MAT、LOG、CSV、TXT 结果
pwsh -File .\tools\zte-server.ps1 fetch task_example
```

结果默认保存到项目根目录的 `server-results`。`run` 会拒绝重复启动仍在运行的同名任务；SSH 断开不会终止 MATLAB。

需要终止任务时显式执行：

```powershell
pwsh -File .\tools\zte-server.ps1 cancel task_example
```

`cancel` 只发送 `SIGTERM`，不会自动强制杀死进程。

## 一次性安装

远端运行器更新后执行：

```powershell
pwsh -File .\tools\zte-server.ps1 install
```

当前配置固定使用：

- 服务器：`jzm123@100.120.122.2`
- 项目目录：`/home/jzm123/AAA_ZTEproject`
- MATLAB：`/home/jzm123/MATLAB/R2022b/bin/matlab`
- 本机密钥：`%USERPROFILE%\.ssh\codex_zte_automation_ed25519`
