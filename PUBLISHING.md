# 博客发布说明

本文说明从 Org 源文件到 [blog.opskumu.com](https://blog.opskumu.com) 的发布流程。下面的日常操作命令均在源码仓库根目录执行。

## 仓库与文件位置

博客使用两个独立的 Git 仓库，目前都使用 `master` 分支：

| 仓库 | 本地位置 | 用途 |
| --- | --- | --- |
| [org-mode-src](https://github.com/opskumu/org-mode-src) | 源码仓库根目录 | 保存文章、图片、模板、样式与发布脚本 |
| [opskumu.github.io](https://github.com/opskumu/opskumu.github.io) | 源码仓库下的 `html/` | 保存生成结果，供 GitHub Pages 部署 |

源码仓库通过 `.gitignore` 忽略 `html/`，它不是 Git 子模块。在源码仓库提交或推送，不会同时提交或推送站点仓库。

| 路径 | 修改内容 |
| --- | --- |
| `src/*.org` | 文章正文、标题、日期等 |
| `src/index.org` | 首页文章归档 |
| `images/` | 文章使用的本地图片 |
| `tpls/tpl.org` | 文章共用的 Org 导出设置与资源引用 |
| `static/css/site.css` | 全站样式 |
| `static/js/site.js` | 目录、归档、图片查看等浏览器交互 |
| `scripts/publish.el` | 导出、归档校验、页面导航、图片墙和订阅等生成逻辑 |
| `html/` | 生成结果；日常修改应回到对应源文件，再重新生成 |

## 首次准备

需要 Git、带有 Org HTML 导出功能的 Emacs，以及两个仓库的推送权限。本地预览使用 Python 3。

在想存放博客的目录中克隆源码，再将站点仓库克隆到其中的 `html/`：

```bash
git clone git@github.com:opskumu/org-mode-src.git org
cd org
git clone git@github.com:opskumu/opskumu.github.io.git html
```

已有本地仓库时直接使用现有目录。若 `html/` 已存在，先检查它是否为站点仓库；不要覆盖已有内容重新克隆。

可以用以下命令确认两个仓库的远端与分支：

```bash
git remote -v
git status --short --branch
git -C html remote -v
git -C html status --short --branch
```

`htmlize` 是可选依赖。安装后，Emacs 导出时可生成语法着色；未安装时仍可导出，页面会按需加载本地的 highlight.js。需要安装时，在 Emacs 执行 `M-x package-install RET htmlize RET`。

## 日常修改

新增文章时，在 `src/` 下创建 Org 文件，例如：

```org
#+TITLE: 文章标题
#+SETUPFILE: ../tpls/tpl.org
#+DATE: <2026-09-30 Wed>

正文。

* 章节标题

章节内容。
```

随后在 `src/index.org` 对应年份中添加条目，按日期从新到旧排列：

```org
- 2026-09-30 [[file:article-name.org][文章标题]]
```

归档中的文件名、标题、日期必须与文章一致。修改文章标题或发布日期时，也要更新归档。当前只有 `index.org` 和 `resume.org` 不要求列入归档。

章节使用 Org 原生标题，编号由导出器生成。默认保留自动编号；`#+OPTIONS: num:nil` 会关闭该篇文章的章节编号，`toc:2` 表示目录收录到第二级。正文、列表、表格、引用和代码块也应使用 Org 语法。

本地图片放在 `images/`，文章中可写为 `[[file:../images/example.jpg]]`。生成脚本会复制文章实际引用的本地图片，并重建 `html/images/`，因此图片原件应保存在源码仓库。

修改 CSS 或 JavaScript 后，同步更新下面两处对应资源的 `?v=` 版本号，例如 `20260930b`：

- `tpls/tpl.org`：文章页面的 CSS、JavaScript 引用。
- `scripts/publish.el`：生成图片墙时使用的 CSS、JavaScript 引用。

同一资源在这两处使用相同版本号，随后重新生成所有页面，让浏览器加载新资源。

## 生成与预览

```bash
emacs --batch -Q -l ./scripts/publish.el -f opskumu-org-publish
```

脚本先校验归档，再重新导出全部文章、复制静态资源和引用图片，生成文章导航、稳定的标题锚点、页面元信息、`gallery.html`、`atom.xml`、`sitemap.xml`、`robots.txt` 及域名配置等文件。

**这个命令只生成本地文件，不会执行 Git 提交、推送或线上部署。** 输出中的 `Publishing file` 也表示本地导出。

脚本以自身位置确定仓库根目录。从其他目录执行时，给 `-l` 传入 `scripts/publish.el` 的绝对路径即可。

也可以在 Emacs 中用 `M-x load-file` 加载该脚本，然后执行 `M-x opskumu-org-publish`。`tpls/.spacemacs` 提供了加载示例，其中的 `opskumu-org-source-root` 需要与本地源码路径一致。

生成成功后启动预览：

```bash
python3 -m http.server 8938 --bind 127.0.0.1 --directory html
```

打开 [本地首页](http://127.0.0.1:8938/index.html)，检查本次修改涉及的页面。样式或交互变更至少看一下首页、代表性正文和图片页，以及窄屏下的效果。预览服务在终端按 `Ctrl+C` 停止；端口被占用时可换一个端口。

## 提交与上线

先检查两个仓库，确认生成结果与本次修改一致：

```bash
git diff --check
git diff --stat
git status --short
git -C html diff --check
git -C html diff --stat
git -C html status --short
```

确认待提交文件都属于本次修改后，分别提交并推送。下面的提交说明应按实际修改替换；若有其他未完成的改动，将 `git add -A` 改为只添加本次要发布的文件。

```bash
git add -A
git diff --cached --stat
git commit -m "Update blog sources"
git push origin master

git -C html add -A
git -C html diff --cached --stat
git -C html commit -m "Publish blog updates"
git -C html push origin master
```

源码推送用于保存可复现的修改，站点推送用于更新线上内容。站点仓库推送后，等待现有 GitHub Pages 部署完成，再访问线上修改过的页面。Git 推送成功不等于页面已经完成部署；部署状态可在站点仓库的 Actions／Pages 页面查看。

## 常见问题

- **归档校验失败**：按报错核对 `src/index.org` 的文件、标题、日期和排序；新文章遗漏、重复条目也会阻止生成。
- **某篇标题没有编号**：检查该篇 `#+OPTIONS` 是否含 `num:nil`，或标题属性中是否设置了 `UNNUMBERED`。
- **本地样式看起来没更新**：确认已重新生成，浏览器访问的是 `html/` 对应的预览服务，并核对两个模板中的资源版本号；必要时强制刷新页面。
- **线上没有更新**：确认推送的是 `html/` 的站点仓库，再检查 Pages 部署状态和浏览器缓存。
- **文章删除或改名后旧页面仍在**：生成脚本不会清空全部旧 HTML。同步调整归档和文章链接，确认旧页面不再需要后，从站点仓库移除对应的旧 `.html` 文件，再提交发布。
