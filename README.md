# README

个人博客源文件

+ Link: [blog.opskumu.com](https://blog.opskumu.com)

## 发布方式

* Emacs 内：`M-x org-publish-project`，选 `org`（与 `tpls/.spacemacs` 中配置一致）。
* 命令行（任意目录，建议仓库根目录）：

```bash
emacs --batch -l ./scripts/publish.el -f opskumu-org-publish
```

会强制重新导出 `src/*.org` 到 `html/`，并同步 `static/`、`images/`。路径由 `scripts/publish.el` 相对解析，不依赖 `~/Dev/...`。

批量导出时会尽量与 `tpls/.spacemacs` 一致（HTML5、postamble、`org-html-htmlize-output-type` 等）。若未安装 **htmlize**，导出仍成功，但源码块没有语法着色，且可能刷屏 “Cannot fontify” 类提示；安装一次即可：`M-x package-install RET htmlize RET`（或在你常用的 Emacs 配置里启用 ELPA 后安装）。
