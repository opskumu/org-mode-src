#!/usr/bin/env python3
"""Upload backed-up blog images to OSS, then optionally update Org links.

Examples (from the repository root):
  python3 scripts/oss_images.py --article src/post.org --dry-run
  python3 scripts/oss_images.py --article src/post.org --update-links
  python3 scripts/oss_images.py images/example.png

Credentials: OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET, optional OSS_SESSION_TOKEN.
"""

from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass
import hashlib
import mimetypes
import os
from pathlib import Path
import re
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, urlsplit
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "images"
MAX_BYTES = 20 * 1024 * 1024
SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".avif"}


class UploadError(Exception):
    """An actionable message that never includes credential or SDK dumps."""


@dataclass(frozen=True)
class Image:
    path: Path
    key: str
    url: str
    sha256: str
    md5: str
    size: int


def local_image_links(text: str):
    """Read standalone native Org image links, excluding literal/example blocks."""
    literal_block = None
    for line_number, line in enumerate(text.splitlines()):
        if literal_block:
            if re.match(r"\s*#\+end_" + literal_block + r"\s*$", line, re.I):
                literal_block = None
            continue
        begin = re.match(r"\s*#\+begin_(src|example|export|comment)\b", line, re.I)
        if begin:
            literal_block = begin.group(1)
            continue
        match = re.fullmatch(r"\s*\[\[(file:[^]\n]+)\]\]\s*", line)
        if match and Path(unquote(match.group(1)[5:])).suffix.lower() in SUFFIXES:
            yield line_number, match.group(1)


def make_image(path: Path, prefix: str, base_url: str, images_dir=IMAGES) -> Image:
    path = path.resolve()
    try:
        relative = path.relative_to(images_dir.resolve())
    except ValueError:
        raise UploadError(f"图片须先备份到 {images_dir}：{path}") from None
    if not path.is_file() or path.suffix.lower() not in SUFFIXES:
        raise UploadError(f"不是支持的图片文件：{path}")
    size = path.stat().st_size
    if not 0 < size <= MAX_BYTES:
        raise UploadError(f"图片大小须在 1 字节到 20 MiB 之间：{path.name}")
    data = path.read_bytes()
    key = "/".join(part for part in (prefix, relative.as_posix()) if part)
    return Image(path, key, base_url.rstrip("/") + "/" + quote(key, safe="/"),
                 hashlib.sha256(data).hexdigest(),
                 base64.b64encode(hashlib.md5(data).digest()).decode("ascii"), len(data))


def public_digest(url: str) -> str | None:
    """Verify the actual public image bytes; ETags need not be content hashes."""
    request = Request(url, headers={"Cache-Control": "no-cache"})
    try:
        with urlopen(request, timeout=20) as response:
            digest = hashlib.sha256()
            size = 0
            while chunk := response.read(64 * 1024):
                size += len(chunk)
                if size > MAX_BYTES:
                    raise UploadError(f"线上对象超过 20 MiB，停止校验：{url}")
                digest.update(chunk)
            return digest.hexdigest()
    except HTTPError as error:
        if error.code == 404:
            return None
        raise UploadError(f"线上图片不可访问（HTTP {error.code}）：{url}") from None
    except (URLError, TimeoutError, OSError):
        raise UploadError(f"无法连接线上图片地址：{url}") from None


class SDKUploader:
    def __init__(self, bucket: str, region: str):
        missing = [key for key in ("OSS_ACCESS_KEY_ID", "OSS_ACCESS_KEY_SECRET")
                   if not os.environ.get(key)]
        if missing:
            raise UploadError("请在本机终端配置环境变量：" + "、".join(missing))
        try:
            import alibabacloud_oss_v2 as oss
        except ImportError:
            raise UploadError("请先安装依赖：python3 -m pip install -r scripts/requirements-oss.txt") from None
        self.oss, self.bucket = oss, bucket
        cfg = oss.config.load_default()
        cfg.region = region
        cfg.endpoint = f"https://oss-{region}.aliyuncs.com"
        cfg.credentials_provider = oss.credentials.EnvironmentVariableCredentialsProvider()
        self.client = oss.Client(cfg)

    def upload(self, image: Image, overwrite: bool):
        data = image.path.read_bytes()
        if hashlib.sha256(data).hexdigest() != image.sha256:
            raise UploadError(f"预览后图片发生变化，请重新执行：{image.path.name}")
        request = self.oss.PutObjectRequest(
            bucket=self.bucket, key=image.key, body=data,
            content_type=mimetypes.guess_type(image.path.name)[0] or "application/octet-stream",
            content_length=len(data), content_md5=image.md5,
            forbid_overwrite=not overwrite,
        )
        try:
            self.client.put_object(request)
        except Exception as error:
            # Never print str(error): SDK request details may contain authentication.
            status = getattr(error, "status_code", None)
            code = getattr(error, "code", None)
            detail = f"HTTP {status}" if isinstance(status, int) else type(error).__name__
            if isinstance(code, str) and re.fullmatch(r"[A-Za-z0-9_]+", code):
                detail += f" / {code}"
            raise UploadError(f"OSS 上传失败（{detail}）：{image.key}") from None


def sync_images(images, *, overwrite, uploader_factory, digest=public_digest):
    """Preflight every object before uploading; never overwrite by default."""
    pending = []
    for image in images:
        existing = digest(image.url)
        if existing == image.sha256:
            print(f"已存在且内容一致：{image.key}", file=sys.stderr)
        elif existing is not None and not overwrite:
            raise UploadError(f"同名对象内容不同，未覆盖：{image.key}；如确需替换，请显式使用 --overwrite")
        else:
            pending.append(image)
    uploader = uploader_factory() if pending else None
    for image in pending:
        uploader.upload(image, overwrite)
        for attempt in range(3):
            if digest(image.url) == image.sha256:
                break
            if attempt == 2:
                raise UploadError(f"上传后公开地址的内容校验未通过，未更新文章：{image.url}")
            time.sleep(0.5 * (attempt + 1))
        print(f"已上传并校验：{image.key}", file=sys.stderr)


def update_article(path: Path, original: str, replacements):
    """Change links only after the entire batch passed, preserving backups."""
    if path.read_text(encoding="utf-8") != original:
        raise UploadError("上传期间文章发生变化，未更新链接，请重新执行")
    lines = original.splitlines(keepends=True)
    for line_number, old in local_image_links(original):
        if old in replacements:
            lines[line_number] = lines[line_number].replace(
                "[[" + old + "]]", "[[" + replacements[old] + "]]")
    updated = "".join(lines)
    if updated == original:
        return
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=".oss-links-", delete=False) as temp:
            temp_name = temp.name
            temp.write(updated)
        os.chmod(temp_name, path.stat().st_mode & 0o777)
        os.replace(temp_name, path)
    finally:
        if temp_name and Path(temp_name).exists():
            Path(temp_name).unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description="上传博客备份图片到 OSS，校验后输出 Org 链接")
    parser.add_argument("files", nargs="*", type=Path, help="images/ 内的图片路径")
    parser.add_argument("--article", type=Path, help="读取 Org 文章中的本地图片链接")
    parser.add_argument("--update-links", action="store_true", help="全部校验成功后替换文章中的本地图片链接")
    parser.add_argument("--dry-run", action="store_true", help="只预览，不联网、上传或改写文章")
    parser.add_argument("--overwrite", action="store_true", help="允许覆盖内容不同的同名对象")
    parser.add_argument("--bucket", default="opskumu")
    parser.add_argument("--region", default="cn-beijing")
    parser.add_argument("--prefix", default="images", help="OSS 对象目录，默认 images")
    parser.add_argument("--base-url", help="公开访问域名；默认使用 bucket 的 OSS 域名")
    args = parser.parse_args(argv)
    if not args.files and not args.article:
        parser.error("请明确指定图片路径或 --article，不会自动上传整个备份目录")
    if args.update_links and not args.article:
        parser.error("--update-links 需要配合 --article")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]", args.bucket):
        parser.error("bucket 名称不合法")
    if not re.fullmatch(r"[a-z]{2}-[a-z0-9-]+", args.region):
        parser.error("region 不合法")
    prefix = args.prefix.strip("/")
    if "\\" in prefix or any(part in (".", "..") for part in prefix.split("/")):
        parser.error("prefix 不能包含反斜杠、. 或 .. 路径段")
    base_url = args.base_url or f"https://{args.bucket}.oss-{args.region}.aliyuncs.com"
    parsed = urlsplit(base_url)
    if (parsed.scheme != "https" or not parsed.netloc or parsed.username
            or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("", "/")):
        parser.error("base-url 必须是无凭据、查询参数或路径的 HTTPS 域名")
    try:
        article = args.article.resolve() if args.article else None
        original = article.read_text(encoding="utf-8") if article else ""
        links = list(local_image_links(original))
        targets = [(path.resolve(), None) for path in args.files]
        targets += [(article.parent / unquote(link[5:]), link) for _, link in links]
        images, replacements = {}, {}
        for path, link in targets:
            image = make_image(path, prefix, base_url)
            images[image.path] = image
            if link:
                replacements[link] = image.url
        plan = list(images.values())
        if not plan:
            print("没有待上传的本地图片链接。", file=sys.stderr)
            return 0
        if args.dry_run:
            for image in plan:
                print(f"预览：{image.path.relative_to(ROOT)} → {image.url}（{image.size} 字节）")
            print("仅预览；尚未上传或更新文章。")
            return 0
        sync_images(plan, overwrite=args.overwrite,
                    uploader_factory=lambda: SDKUploader(args.bucket, args.region))
        if args.update_links:
            update_article(article, original, replacements)
            print(f"已更新文章图片链接：{article}", file=sys.stderr)
        for image in plan:
            print(f"[[{image.url}]]")
        return 0
    except (UploadError, OSError, UnicodeError) as error:
        print(f"错误：{error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
