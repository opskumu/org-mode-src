"""Upload failure boundaries, idempotency, and native Org link preservation."""

import base64
from contextlib import redirect_stderr, redirect_stdout
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("oss_images", ROOT / "scripts/oss_images.py")
oss_images = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = oss_images
spec.loader.exec_module(oss_images)


class ImagesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.images = self.root / "images"
        self.images.mkdir()

    def image(self, name="image.png", data=b"image bytes"):
        path = self.images / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return oss_images.make_image(path, "images", "https://example.com", self.images)

    def test_backup_paths_cannot_escape_through_symlinks(self):
        outside = self.root / "outside.png"
        outside.write_bytes(b"outside")
        link = self.images / "link.png"
        link.symlink_to(outside)
        with self.assertRaises(oss_images.UploadError):
            oss_images.make_image(link, "images", "https://example.com", self.images)

    def test_subfolders_and_spaces_have_stable_public_urls(self):
        image = self.image("diagrams/my image.png")
        self.assertEqual(image.key, "images/diagrams/my image.png")
        self.assertEqual(image.url, "https://example.com/images/diagrams/my%20image.png")

    def test_rerun_skips_identical_objects_without_credentials(self):
        image = self.image()
        factory = Mock(side_effect=AssertionError("should not need credentials"))
        with redirect_stderr(io.StringIO()):
            oss_images.sync_images([image], overwrite=False, uploader_factory=factory,
                                   digest=lambda url: image.sha256)
        factory.assert_not_called()

    def test_any_collision_prevents_the_entire_batch_from_uploading(self):
        first, second = self.image("one.png"), self.image("two.png")
        factory = Mock()
        digest = lambda url: None if url == first.url else "different-content"
        with self.assertRaises(oss_images.UploadError):
            oss_images.sync_images([first, second], overwrite=False,
                                   uploader_factory=factory, digest=digest)
        factory.assert_not_called()

    def test_upload_needs_a_public_content_match(self):
        image = self.image()
        uploader = Mock()
        with patch.object(oss_images.time, "sleep"), self.assertRaises(oss_images.UploadError):
            oss_images.sync_images([image], overwrite=False,
                                   uploader_factory=lambda: uploader, digest=lambda url: None)
        uploader.upload.assert_called_once_with(image, False)

    def test_org_examples_are_ignored_and_preserved_when_rewriting(self):
        link = "[[file:../images/image.png]]"
        original = "#+CAPTION: diagram\n" + link + "\n\n#+begin_example\n" + link + "\n#+end_example\n"
        self.assertEqual(list(oss_images.local_image_links(original)), [(1, "file:../images/image.png")])
        article = self.root / "post.org"
        article.write_text(original)
        oss_images.update_article(article, original,
                                  {"file:../images/image.png": "https://example.com/images/image.png"})
        result = article.read_text()
        self.assertIn("#+CAPTION: diagram\n[[https://example.com/images/image.png]]", result)
        self.assertIn("#+begin_example\n" + link + "\n#+end_example", result)
        self.assertEqual(list(self.root.glob(".oss-links-*")), [])

    def test_concurrent_article_edit_is_not_overwritten(self):
        article = self.root / "post.org"
        article.write_text("new user edit\n")
        with self.assertRaises(oss_images.UploadError):
            oss_images.update_article(article, "old article\n", {})
        self.assertEqual(article.read_text(), "new user edit\n")

    def test_dry_run_does_not_contact_oss_or_modify_article(self):
        article = ROOT / "src/llm-from-token-to-transformer.org"
        before = article.read_bytes()
        with patch.object(oss_images, "public_digest", side_effect=AssertionError("network")), \
                patch.object(oss_images, "SDKUploader", side_effect=AssertionError("credentials")), \
                redirect_stdout(io.StringIO()) as output:
            result = oss_images.main(["--article", str(article), "--update-links", "--dry-run"])
        self.assertEqual(result, 0)
        self.assertEqual(article.read_bytes(), before)
        self.assertIn("仅预览", output.getvalue())

    def test_missing_credentials_produces_actionable_message(self):
        with patch.dict(os.environ, {}, clear=True), self.assertRaisesRegex(
                oss_images.UploadError, "OSS_ACCESS_KEY_ID"):
            oss_images.SDKUploader("opskumu", "cn-beijing")

    def test_sdk_put_has_content_integrity_and_server_side_no_overwrite(self):
        try:
            import alibabacloud_oss_v2 as oss
        except ImportError:
            self.skipTest("install scripts/requirements-oss.txt to test SDK integration")
        image = self.image()
        client = Mock()
        with patch.dict(os.environ, {"OSS_ACCESS_KEY_ID": "test-id", "OSS_ACCESS_KEY_SECRET": "test-secret"}), \
                patch.object(oss, "Client", return_value=client):
            uploader = oss_images.SDKUploader("opskumu", "cn-beijing")
            uploader.upload(image, False)
        request = client.put_object.call_args.args[0]
        self.assertTrue(request.forbid_overwrite)
        self.assertEqual(request.body, image.path.read_bytes())
        self.assertEqual(request.content_md5, base64.b64encode(hashlib.md5(request.body).digest()).decode())
        self.assertIsNone(request.acl)
        uploader.upload(image, True)
        self.assertFalse(client.put_object.call_args.args[0].forbid_overwrite)


if __name__ == "__main__":
    unittest.main()
