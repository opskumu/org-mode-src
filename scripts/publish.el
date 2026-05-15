;;; publish.el --- batch HTML export for opskumu blog -*- lexical-binding: t -*-
;;; Usage (from repo root):
;;;   emacs --batch -l ./scripts/publish.el -f opskumu-org-publish
;;;
;;; Same layout as tpls/.spacemacs `org-publish-project-alist`, paths derived
;;; from this file so the repo can live anywhere.
;;;
;;; Root is captured at load time: `load-file-name' is nil when `-f' runs after
;;; `-l', so we must not rely on it inside `opskumu-org-publish'.

(unless load-file-name
  (error "Load this file with emacs -l /path/to/scripts/publish.el"))

(defvar opskumu-org-repo-root
  (file-truename (expand-file-name ".." (file-name-directory load-file-name)))
  "Absolute path to blog repo (parent of scripts/).")

(defconst opskumu-org--site-url "https://blog.opskumu.com/"
  "Canonical base URL for exported pages.")

(defconst opskumu-org--chrome-html
  (concat
   "<a class=\"skip-link\" href=\"#content\">Skip to main content</a>"
   "<nav class=\"navbar\" role=\"navigation\" aria-label=\"Primary\">"
   "<a class=\"navbar-brand\" href=\"index.html\">Kumu's Blog</a>"
   "<div class=\"navbar-links\">"
   "<a href=\"index.html\" data-nav=\"blog\">Blog</a>"
   "<a href=\"https://wiki.opskumu.com\" target=\"_blank\" rel=\"noopener noreferrer\">Wiki</a>"
   "<a href=\"https://github.com/opskumu/issues\" target=\"_blank\" rel=\"noopener noreferrer\">Issues</a>"
   "<a href=\"https://github.com/opskumu\" target=\"_blank\" rel=\"noopener noreferrer\">GitHub</a>"
   "<a href=\"https://opskumu.com/\" target=\"_blank\" rel=\"noopener noreferrer\">About</a>"
   "</div>"
   "</nav>")
  "Static page chrome emitted by Org export before JavaScript enhancements.")

(defun opskumu-org--html-escape (text)
  "Escape TEXT for safe insertion into HTML attributes."
  (let ((escaped (or text "")))
    (setq escaped (replace-regexp-in-string "&" "&amp;" escaped t t))
    (setq escaped (replace-regexp-in-string "\"" "&quot;" escaped t t))
    (setq escaped (replace-regexp-in-string "<" "&lt;" escaped t t))
    (replace-regexp-in-string ">" "&gt;" escaped t t)))

(defun opskumu-org--current-page-url ()
  "Return the canonical URL for the Org file currently being exported."
  (let* ((file (buffer-file-name))
         (base (and file (file-name-base file))))
    (concat opskumu-org--site-url
            (if (or (not base) (string= base "index"))
                ""
              (concat base ".html")))))

(defun opskumu-org--match-head-content (html regexp)
  "Return first capture group from REGEXP in HTML."
  (when (string-match regexp html)
    (match-string 1 html)))

(defun opskumu-org--archive-posts ()
  "Return posts from `src/index.org' in homepage archive order."
  (let ((index-file (expand-file-name "src/index.org" opskumu-org-repo-root))
        posts)
    (when (file-readable-p index-file)
      (with-temp-buffer
        (insert-file-contents index-file)
        (goto-char (point-min))
        (while (re-search-forward
                "^- \\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\) \\[\\[file:\\([^]]+\\.org\\)\\]\\[\\([^]\n]+\\)\\]\\]"
                nil t)
          (push (list :date (match-string 1)
                      :file (match-string 2)
                      :title (match-string 3))
                posts))))
    (nreverse posts)))

(defun opskumu-org--post-url (post)
  "Return the exported HTML filename for POST."
  (concat (file-name-sans-extension (plist-get post :file)) ".html"))

(defun opskumu-org--article-nav-link (post rel label)
  "Return one article navigation link for POST with REL and LABEL."
  (concat
   "<a class=\"article-nav-link article-nav-" rel "\" href=\""
   (opskumu-org--html-escape (opskumu-org--post-url post))
   "\">"
   "<span class=\"article-nav-label\">" label "</span>"
   "<span class=\"article-nav-title\">"
   (opskumu-org--html-escape (plist-get post :title))
   "</span>"
   "<span class=\"article-nav-date\">"
   (opskumu-org--html-escape (plist-get post :date))
   "</span>"
   "</a>"))

(defun opskumu-org--article-nav-html ()
  "Return previous/next article navigation HTML for the current export."
  (let* ((source-file (buffer-file-name))
         (current (and source-file (file-name-nondirectory source-file)))
         (posts (opskumu-org--archive-posts))
         (index 0)
         match-index)
    (unless (or (not current) (string= current "index.org"))
      (while (and posts (not match-index))
        (when (string= current (plist-get (car posts) :file))
          (setq match-index index))
        (setq posts (cdr posts)
              index (1+ index)))
      (when match-index
        (let* ((all-posts (opskumu-org--archive-posts))
               (newer (and (> match-index 0) (nth (1- match-index) all-posts)))
               (older (nth (1+ match-index) all-posts))
               (links ""))
          (when newer
            (setq links (concat links (opskumu-org--article-nav-link newer "newer" "Newer"))))
          (when older
            (setq links (concat links (opskumu-org--article-nav-link older "older" "Older"))))
          (unless (string-empty-p links)
            (concat "<nav class=\"article-nav\" aria-label=\"Article navigation\">"
                    links
                    "</nav>")))))))

(defun opskumu-org--article-nav-html-for-neighbors (newer older)
  "Return article navigation HTML for NEWER and OLDER posts."
  (let ((links ""))
    (when newer
      (setq links (concat links (opskumu-org--article-nav-link newer "newer" "Newer"))))
    (when older
      (setq links (concat links (opskumu-org--article-nav-link older "older" "Older"))))
    (unless (string-empty-p links)
      (concat "<nav class=\"article-nav\" aria-label=\"Article navigation\">"
              links
              "</nav>"))))

(defun opskumu-org--inject-article-nav (html)
  "Insert article navigation into exported HTML."
  (let ((nav (opskumu-org--article-nav-html)))
    (if (or (not nav) (string-match-p "class=\"article-nav\"" html))
        html
      (replace-regexp-in-string
       "\n<div id=\"postamble\""
       (concat "\n" nav "\n<div id=\"postamble\"")
       html t t))))

(defun opskumu-org--strip-article-nav (html)
  "Remove existing generated article navigation from HTML."
  (replace-regexp-in-string
   "\n?<nav class=\"article-nav\"[^>]*>.*?</nav>\n?"
   "\n"
   html t t))

(defun opskumu-org--insert-article-nav-html (html nav)
  "Insert NAV before the postamble in HTML."
  (replace-regexp-in-string
   "\n<div id=\"postamble\""
   (concat "\n" nav "\n<div id=\"postamble\"")
   (opskumu-org--strip-article-nav html)
   t t))

(defun opskumu-org--write-article-navs (html-dir)
  "Write static previous/next navigation into generated files under HTML-DIR."
  (let* ((posts (opskumu-org--archive-posts))
         (count (length posts))
         (index 0))
    (while (< index count)
      (let* ((post (nth index posts))
             (newer (and (> index 0) (nth (1- index) posts)))
             (older (and (< index (1- count)) (nth (1+ index) posts)))
             (nav (opskumu-org--article-nav-html-for-neighbors newer older))
             (html-file (expand-file-name (opskumu-org--post-url post) html-dir)))
        (when (and nav (file-readable-p html-file))
          (with-temp-buffer
            (insert-file-contents html-file)
            (let ((updated (opskumu-org--insert-article-nav-html (buffer-string) nav)))
              (erase-buffer)
              (insert updated)
              (write-region (point-min) (point-max) html-file nil 'silent)))))
      (setq index (1+ index)))))

(defun opskumu-org--inject-head-metadata (html backend info)
  "Add crawler-visible canonical and social metadata to exported HTML."
  (if (not (org-export-derived-backend-p backend 'html))
      html
    (let* ((title (or (opskumu-org--match-head-content html "<title>\\([^<]+\\)</title>")
                      "Kumu's Blog"))
           (description (or (opskumu-org--match-head-content
                             html
                             "<meta name=\"description\" content=\"\\([^\"]+\\)\"")
                            "Personal notes on Kubernetes, Linux, Emacs, and tools."))
           (url (opskumu-org--current-page-url))
           (extra ""))
      (unless (string-match-p "rel=\"canonical\"" html)
        (setq extra (concat extra "<link rel=\"canonical\" href=\"" (opskumu-org--html-escape url) "\"/>\n")))
      (unless (string-match-p "property=\"og:title\"" html)
        (setq extra (concat extra "<meta property=\"og:title\" content=\"" (opskumu-org--html-escape title) "\"/>\n")))
      (unless (string-match-p "property=\"og:description\"" html)
        (setq extra (concat extra "<meta property=\"og:description\" content=\"" (opskumu-org--html-escape description) "\"/>\n")))
      (unless (string-match-p "property=\"og:url\"" html)
        (setq extra (concat extra "<meta property=\"og:url\" content=\"" (opskumu-org--html-escape url) "\"/>\n")))
      (unless (string-match-p "name=\"twitter:title\"" html)
        (setq extra (concat extra "<meta name=\"twitter:title\" content=\"" (opskumu-org--html-escape title) "\"/>\n")))
      (unless (string-match-p "name=\"twitter:description\"" html)
        (setq extra (concat extra "<meta name=\"twitter:description\" content=\"" (opskumu-org--html-escape description) "\"/>\n")))
      (if (string-empty-p extra)
          html
        (setq html (replace-regexp-in-string "</head>" (concat extra "</head>") html t t)))
      (opskumu-org--inject-article-nav html))))

(defun opskumu-org--push-htmlize-from-elpa ()
  "If GNU ELPA htmlize is under ~/.emacs.d/elpa, add it to `load-path'.
Helps `emacs --batch' find htmlize without a full interactive init."
  (let ((elpa (expand-file-name ".emacs.d/elpa" (expand-file-name "~"))))
    (when (file-directory-p elpa)
      (ignore-errors
        (dolist (d (directory-files elpa t "^htmlize-" t))
          (when (file-directory-p d)
            (push d load-path)))))))

(defun opskumu-org--init-export-settings ()
  "Match `tpls/.spacemacs' + safe fallback when ELPA htmlize is missing in batch."
  (require 'ox-html)
  (setq org-html-html5-fancy t
        org-html-doctype "html5"
        org-html-validation-link nil
        org-export-with-sub-superscripts '{}
        org-export-default-language "zh-CN"
        org-html-preamble t
        org-html-preamble-format
        `(("zh-CN" ,opskumu-org--chrome-html)
          ("en" ,opskumu-org--chrome-html))
        org-html-postamble t
        org-html-postamble-format
        '(("zh-CN" "<a class=\"author\" href=\"https://blog.opskumu.com\">%a</a><span class=\"postamble-sep\" aria-hidden=\"true\"> / </span><span class=\"date\">%d</span><span class=\"creator\">%c</span>")
          ("en" "<a class=\"author\" href=\"https://blog.opskumu.com\">%a</a><span class=\"postamble-sep\" aria-hidden=\"true\"> / </span><span class=\"date\">%d</span><span class=\"creator\">%c</span>")))
  (add-to-list 'org-export-filter-final-output-functions
               #'opskumu-org--inject-head-metadata)
  ;; `htmlize' is required when `org-html-htmlize-output-type' is `css';
  ;; without it, batch export prints a warning per source block.
  (opskumu-org--push-htmlize-from-elpa)
  (when (and (fboundp 'package-initialize)
             (locate-library "package"))
    (setq package-enable-at-startup nil)
    (ignore-errors (package-initialize)))
  (if (require 'htmlize nil t)
      (setq org-html-htmlize-output-type 'css)
    (setq org-html-htmlize-output-type nil)
    (message "opskumu-org-publish: package `htmlize' not found; install with `M-x package-install RET htmlize RET' for colored src blocks.")))

(defun opskumu-org-publish ()
  "Publish all components of project `org' (notes + static + images)."
  (let* ((root opskumu-org-repo-root)
         (src (expand-file-name "src/" root))
         (static (expand-file-name "static/" root))
         (images (expand-file-name "images/" root))
         (html (expand-file-name "html/" root))
         (html-images (expand-file-name "html/images/" root))
         (timestamps (expand-file-name ".org-timestamps/" html)))
    (unless (file-directory-p src)
      (error "Expected src at %s" src))
    (opskumu-org--init-export-settings)
    (require 'ox-publish)
    (make-directory timestamps t)
    (setq org-publish-timestamp-directory timestamps)
    (setq org-publish-project-alist
          `(("notes"
             :base-directory ,src
             :base-extension "org"
             :publishing-directory ,html
             :recursive t
             :publishing-function org-html-publish-to-html
             :headline-levels 4
             :auto-preamble t)
            ("static"
             :base-directory ,static
             :base-extension "css\\|js\\|png\\|jpg\\|gif\\|pdf\\|mp3\\|ogg\\|swf"
             :publishing-directory ,html
             :recursive t
             :publishing-function org-publish-attachment)
            ("images"
             :base-directory ,images
             :base-extension "png\\|jpg\\|gif"
             :publishing-directory ,html-images
             :recursive t
             :publishing-function org-publish-attachment)
            ("org" :components ("notes" "static" "images"))))
    ;; Force: regenerate all HTML and recopy assets (avoids stale head/CSS).
    (org-publish-project "org" t)
    (opskumu-org--write-article-navs html)))
