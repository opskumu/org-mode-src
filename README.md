# README

个人博客源文件

+ Link: [blog.opskumu.com](https://blog.opskumu.com)

## 发布方式

* Emacs 内：使用 `tpls/.spacemacs` 加载统一发布脚本，然后执行
  `M-x opskumu-org-publish`。
* 命令行（任意目录，建议仓库根目录）：

```bash
emacs --batch -Q -l ./scripts/publish.el -f opskumu-org-publish
```

发布前会校验首页归档与文章的 `TITLE`、`DATE` 是否一致；随后重新导出
`src/*.org` 到 `html/`，复制 `static/` 资源及文章实际引用的本地图片，并生成：

* 稳定的标题锚点和页面元信息
* `atom.xml`、`sitemap.xml`、`robots.txt`
* `CNAME`、`.nojekyll`、`favicon.ico`

路径由 `scripts/publish.el` 相对解析，不依赖个人目录。`html/` 是独立的
GitHub Pages 仓库；发布完成后在该目录检查变更、提交并推送即可。

若未安装 **htmlize**，导出仍会成功，但源码块没有 Emacs 侧语法着色；
浏览器仍会按需加载 highlight.js。需要安装时执行：
`M-x package-install RET htmlize RET`。
