# Kumu's Blog

[blog.opskumu.com](https://blog.opskumu.com) 的 Org 源文件、样式及生成脚本。

## 本地生成

在源码仓库根目录执行：

```bash
emacs --batch -Q -l ./scripts/publish.el -f opskumu-org-publish
```

这个命令只生成本地站点。`html/` 是独立的 GitHub Pages 仓库，上线需要另行提交和推送。

首次准备、文章维护、本地预览、提交上线及常见问题见 [发布说明](PUBLISHING.md)。
