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

(defconst opskumu-org--image-cdn-url
  "https://opskumu.oss-cn-beijing.aliyuncs.com/images/"
  "Legacy image URL prefix rewritten to local published assets when possible.")

(defconst opskumu-org--archive-excluded-files '("index.org" "resume.org")
  "Org files intentionally excluded from the public archive.")

(defconst opskumu-org--chrome-html
  (concat
   "<a class=\"skip-link\" href=\"#content\">跳到正文</a>"
   "<nav class=\"navbar\" role=\"navigation\" aria-label=\"主导航\">"
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

(defun opskumu-org--export-paper-ref-links (_backend)
  "Export GitHub-friendly paper reference links with stable HTML anchors.
GitHub's Org renderer needs `#ref-N' links to stay on the current page;
the blog export should use the same stable anchors instead of generated ids."
  (goto-char (point-min))
  (while (re-search-forward "\\[\\[#\\(ref-[0-9]+\\)\\]\\[\\([^]\n]+\\)\\]\\]" nil t)
    (replace-match
     (format "@@html:<a href=\"#%s\">%s</a>@@"
             (match-string 1)
             (match-string 2))
     t t)))

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

(defun opskumu-org--source-keyword (file keyword)
  "Return FILE's local Org KEYWORD value, without inherited setup values."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward
               (format "^#\\+%s:[ \t]*\\(.+\\)$" (regexp-quote keyword))
               nil t)
          (string-trim (match-string 1)))))))

(defun opskumu-org--source-date (file &optional keyword)
  "Return FILE's YYYY-MM-DD Org date from KEYWORD, defaulting to DATE."
  (let ((raw (opskumu-org--source-keyword file (or keyword "DATE"))))
    (when (and raw
               (string-match
                "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)"
                raw))
      (match-string 1 raw))))

(defun opskumu-org--validate-archive ()
  "Validate archive entries against article metadata before publishing."
  (let* ((src-dir (expand-file-name "src/" opskumu-org-repo-root))
         (posts (opskumu-org--archive-posts))
         (seen (make-hash-table :test #'equal))
         previous-date)
    (dolist (post posts)
      (let* ((name (plist-get post :file))
             (file (expand-file-name name src-dir))
             (archive-title (string-trim (plist-get post :title)))
             (archive-date (plist-get post :date))
             (source-title (opskumu-org--source-keyword file "TITLE"))
             (source-date (opskumu-org--source-date file)))
        (unless (file-readable-p file)
          (error "Archive references missing source file: %s" name))
        (when (gethash name seen)
          (error "Archive contains duplicate source file: %s" name))
        (puthash name t seen)
        (unless (equal archive-title source-title)
          (error "Title mismatch for %s: archive=%S source=%S"
                 name archive-title source-title))
        (unless (equal archive-date source-date)
          (error "Date mismatch for %s: archive=%S source=%S"
                 name archive-date source-date))
        (when (and previous-date (string< previous-date archive-date))
          (error "Archive is not in reverse chronological order near %s" name))
        (setq previous-date archive-date)))
    (dolist (name (directory-files src-dir nil "\\.org\\'"))
      (unless (or (string-prefix-p "." name)
                  (member name opskumu-org--archive-excluded-files)
                  (gethash name seen))
        (error "Public Org source is missing from archive: %s" name)))))

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
            (setq links (concat links (opskumu-org--article-nav-link newer "newer" "上一篇"))))
          (when older
            (setq links (concat links (opskumu-org--article-nav-link older "older" "下一篇"))))
          (unless (string-empty-p links)
            (concat "<nav class=\"article-nav\" aria-label=\"Article navigation\">"
                    links
                    "</nav>")))))))

(defun opskumu-org--article-nav-html-for-neighbors (newer older)
  "Return article navigation HTML for NEWER and OLDER posts."
  (let ((links ""))
    (when newer
      (setq links (concat links (opskumu-org--article-nav-link newer "newer" "上一篇"))))
    (when older
      (setq links (concat links (opskumu-org--article-nav-link older "older" "下一篇"))))
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

(defun opskumu-org--read-u16-be (data offset)
  "Read a big-endian unsigned 16-bit integer from DATA at OFFSET."
  (+ (lsh (aref data offset) 8)
     (aref data (1+ offset))))

(defun opskumu-org--read-u16-le (data offset)
  "Read a little-endian unsigned 16-bit integer from DATA at OFFSET."
  (+ (aref data offset)
     (lsh (aref data (1+ offset)) 8)))

(defun opskumu-org--read-u32-be (data offset)
  "Read a big-endian unsigned 32-bit integer from DATA at OFFSET."
  (+ (lsh (aref data offset) 24)
     (lsh (aref data (+ offset 1)) 16)
     (lsh (aref data (+ offset 2)) 8)
     (aref data (+ offset 3))))

(defun opskumu-org--image-dimensions (file)
  "Return FILE image dimensions as (WIDTH . HEIGHT), or nil."
  (when (file-readable-p file)
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert-file-contents-literally file)
      (let* ((data (buffer-string))
             (length (length data)))
        (cond
         ((and (>= length 24)
               (= (aref data 0) #x89)
               (string= (substring data 1 4) "PNG"))
          (cons (opskumu-org--read-u32-be data 16)
                (opskumu-org--read-u32-be data 20)))
         ((and (>= length 10)
               (string= (substring data 0 3) "GIF"))
          (cons (opskumu-org--read-u16-le data 6)
                (opskumu-org--read-u16-le data 8)))
         ((and (>= length 4)
               (= (aref data 0) #xff)
               (= (aref data 1) #xd8))
          (let ((offset 2)
                dimensions)
            (while (and (not dimensions) (< (+ offset 8) length))
              (if (/= (aref data offset) #xff)
                  (setq offset (1+ offset))
                (while (and (< offset length)
                            (= (aref data offset) #xff))
                  (setq offset (1+ offset)))
                (when (< offset length)
                  (let ((marker (aref data offset)))
                    (setq offset (1+ offset))
                    (if (or (= marker #x01)
                            (and (>= marker #xd0) (<= marker #xd9)))
                        nil
                      (when (< (1+ offset) length)
                        (let ((segment-length
                               (opskumu-org--read-u16-be data offset)))
                          (if (and (memq marker
                                          '(#xc0 #xc1 #xc2 #xc3
                                            #xc5 #xc6 #xc7
                                            #xc9 #xca #xcb
                                            #xcd #xce #xcf))
                                   (<= (+ offset 6) (1- length)))
                              (setq dimensions
                                    (cons
                                     (opskumu-org--read-u16-be data (+ offset 5))
                                     (opskumu-org--read-u16-be data (+ offset 3))))
                            (setq offset (+ offset segment-length))))))))))
            dimensions)))))))

(defun opskumu-org--rewrite-image-tags (html)
  "Localize available image URLs and add stable loading/dimension attributes."
  (let ((start 0)
        (first-image t)
        (images-root (expand-file-name "images/" opskumu-org-repo-root)))
    (while (string-match "<img\\([^>]*\\)>" html start)
      (let* ((begin (match-beginning 0))
             (end (match-end 0))
             (tag (match-string 0 html))
             (src (and (string-match "src=\"\\([^\"]+\\)\"" tag)
                       (match-string 1 tag)))
             local-relative
             local-file)
        (when (and src (string-prefix-p opskumu-org--image-cdn-url src))
          (setq local-relative
                (substring src (length opskumu-org--image-cdn-url))
                local-file (expand-file-name local-relative images-root))
          (when (file-readable-p local-file)
            (setq tag
                  (replace-regexp-in-string
                   (concat "src=\"" (regexp-quote src) "\"")
                   (concat "src=\"images/" local-relative "\"")
                   tag t t))))
        (unless (string-match-p "\\bdecoding=" tag)
          (setq tag
                (replace-regexp-in-string
                 "/?>\\'"
                 " decoding=\"async\">"
                 tag t t)))
        (unless (string-match-p "\\bloading=" tag)
          (setq tag
                (replace-regexp-in-string
                 "/?>\\'"
                 (if first-image
                     " loading=\"eager\" fetchpriority=\"high\">"
                   " loading=\"lazy\">")
                 tag t t)))
        (when (and local-file
                   (file-readable-p local-file)
                   (not (string-match-p "\\bwidth=" tag))
                   (not (string-match-p "\\bheight=" tag)))
          (let ((dimensions (opskumu-org--image-dimensions local-file)))
            (when dimensions
              (setq tag
                    (replace-regexp-in-string
                     "/?>\\'"
                     (format " width=\"%d\" height=\"%d\">"
                             (car dimensions) (cdr dimensions))
                     tag t t)))))
        (setq html (concat (substring html 0 begin)
                           tag
                           (substring html end))
              start (+ begin (length tag))
              first-image nil)))
    html))

(defun opskumu-org--normalize-generated-ids (html)
  "Replace Org's process-random internal IDs in HTML deterministically."
  (let ((mapping (make-hash-table :test #'equal))
        (counter 0)
        (start 0))
    (while (string-match "\\borg[[:xdigit:]]\\{7,\\}\\b" html start)
      (let* ((begin (match-beginning 0))
             (old (match-string 0 html))
             (replacement
              (or (gethash old mapping)
                  (let ((value (format "generated-%d" (setq counter (1+ counter)))))
                    (puthash old value mapping)
                    value))))
        (setq html (replace-match replacement t t html)
              start (+ begin (length replacement)))))
    html))

(defun opskumu-org--normalize-heading-ids (html)
  "Replace generated heading IDs in HTML with content-based stable IDs."
  (let ((start 0)
        (seen (make-hash-table :test #'equal))
        mapping)
    (while (string-match
            "<h[2-6] id=\"\\(org[[:xdigit:]]\\{7,\\}\\)\"[^>]*>\\([^\n]*\\)</h[2-6]>"
            html start)
      (let* ((heading-end (match-end 0))
             (old (match-string 1 html))
             (heading-html
              (replace-regexp-in-string
               "<span class=\"section-number-[^\"]+\">[^<]*</span>"
               ""
               (match-string 2 html) t t))
             (title (downcase
                     (opskumu-org--decode-html-text heading-html)))
             (base (concat "section-"
                           (substring (secure-hash 'sha1 title) 0 12)))
             (count (1+ (gethash base seen 0)))
             (stable (if (= count 1)
                         base
                       (format "%s-%d" base count))))
        (puthash base count seen)
        (push (cons old stable) mapping)
        (setq start heading-end)))
    (dolist (pair mapping)
      (setq html
            (replace-regexp-in-string
             (regexp-quote (car pair)) (cdr pair) html t t)))
    html))

(defun opskumu-org--decode-html-text (text)
  "Convert a small HTML fragment TEXT into normalized plain text."
  (setq text (replace-regexp-in-string "<[^>]+>" " " text))
  (setq text
        (replace-regexp-in-string
         "&#x\\([0-9a-fA-F]+\\);"
         (lambda (match)
           (char-to-string (string-to-number (match-string 1 match) 16)))
         text t))
  (setq text
        (replace-regexp-in-string
         "&#\\([0-9]+\\);"
         (lambda (match)
           (char-to-string (string-to-number (match-string 1 match) 10)))
         text t))
  (dolist (entity '(("&nbsp;" . " ")
                    ("&amp;" . "&")
                    ("&lt;" . "<")
                    ("&gt;" . ">")
                    ("&quot;" . "\"")
                    ("&#39;" . "'")))
    (setq text
          (replace-regexp-in-string
           (regexp-quote (car entity)) (cdr entity) text t t)))
  (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " text)))

(defun opskumu-org--description-from-html (html)
  "Return the first useful paragraph from HTML as a short description."
  (let ((start (or (string-match "<div id=\"content\"" html) 0))
        description)
    (while (and (not description)
                (string-match
                 "<p[^>]*>\\(\\(?:.\\|\n\\)*?\\)</p>"
                 html start))
      (let ((paragraph-end (match-end 0))
            (candidate
             (opskumu-org--decode-html-text (match-string 1 html))))
        (setq start paragraph-end)
        (when (and (>= (length candidate) 50)
                   (not (string-match-p
                         "\\`\\(?:图\\(?:摘自\\|片\\|中\\)\\|如[上下]?图\\|[上下]图\\)"
                         candidate)))
          (setq description candidate))))
    (when description
      (if (> (length description) 160)
          (concat (substring description 0 157) "…")
        description))))

(defun opskumu-org--page-description (html)
  "Return an explicit or automatically derived description for current HTML."
  (let* ((file (buffer-file-name))
         (explicit (and file
                        (opskumu-org--source-keyword file "DESCRIPTION"))))
    (or explicit
        (opskumu-org--description-from-html html)
        "Kumu 的个人博客，记录 Kubernetes、Linux、Emacs 与工程实践。")))

(defun opskumu-org--first-image-url (html)
  "Return the first image in HTML as an absolute URL."
  (when (string-match "<img[^>]+src=\"\\([^\"]+\\)\"" html)
    (let ((src (match-string 1 html)))
      (if (string-match-p "\\`https?://" src)
          src
        (concat opskumu-org--site-url
                (replace-regexp-in-string "\\`\\./" "" src))))))

(defun opskumu-org--json-ld-html
    (title description url is-index published modified image)
  "Return JSON-LD script HTML for the current page metadata."
  (require 'json)
  (let* ((author '(("@type" . "Person")
                   ("name" . "Kumu")
                   ("url" . "https://opskumu.com/")))
         (schema
          (if is-index
              `(("@context" . "https://schema.org")
                ("@type" . "Blog")
                ("name" . ,title)
                ("description" . ,description)
                ("url" . ,url)
                ("inLanguage" . "zh-CN")
                ("author" . ,author))
            `(("@context" . "https://schema.org")
              ("@type" . "BlogPosting")
              ("headline" . ,title)
              ("description" . ,description)
              ("url" . ,url)
              ("mainEntityOfPage" . ,url)
              ("inLanguage" . "zh-CN")
              ("datePublished" . ,published)
              ("dateModified" . ,modified)
              ("author" . ,author)
              ("publisher" . ,author)
              ,@(when image `(("image" . ,image))))))
         (json (json-encode schema)))
    (concat "<script type=\"application/ld+json\">"
            (replace-regexp-in-string "</" "<\\/" json t t)
            "</script>\n")))

(defun opskumu-org--inject-head-metadata (html backend _info)
  "Add crawler-visible canonical and social metadata to exported HTML."
  (if (not (org-export-derived-backend-p backend 'html))
      html
    (setq html (opskumu-org--rewrite-image-tags html))
    (setq html (opskumu-org--normalize-heading-ids html))
    (setq html (opskumu-org--normalize-generated-ids html))
    (let* ((title (or (opskumu-org--match-head-content html "<title>\\([^<]+\\)</title>")
                      "Kumu's Blog"))
           (description (opskumu-org--page-description html))
           (url (opskumu-org--current-page-url))
           (is-index (string= url opskumu-org--site-url))
           (og-type (if is-index "website" "article"))
           (published (and (not is-index)
                           (buffer-file-name)
                           (opskumu-org--source-date (buffer-file-name))))
           (modified (and (not is-index)
                          (buffer-file-name)
                          (or (opskumu-org--source-date
                               (buffer-file-name) "UPDATED")
                              published)))
           (image (opskumu-org--first-image-url html))
           (extra ""))
      (setq html
            (replace-regexp-in-string
             "<meta name=\"description\" content=\"[^\"]*\" ?/?>"
             (concat "<meta name=\"description\" content=\""
                     (opskumu-org--html-escape description) "\" />")
             html t t))
      (unless (string-match-p "rel=\"canonical\"" html)
        (setq extra (concat extra "<link rel=\"canonical\" href=\"" (opskumu-org--html-escape url) "\"/>\n")))
      (unless (string-match-p "property=\"og:title\"" html)
        (setq extra (concat extra "<meta property=\"og:title\" content=\"" (opskumu-org--html-escape title) "\"/>\n")))
      (unless (string-match-p "property=\"og:description\"" html)
        (setq extra (concat extra "<meta property=\"og:description\" content=\"" (opskumu-org--html-escape description) "\"/>\n")))
      (unless (string-match-p "property=\"og:url\"" html)
        (setq extra (concat extra "<meta property=\"og:url\" content=\"" (opskumu-org--html-escape url) "\"/>\n")))
      (unless (string-match-p "property=\"og:type\"" html)
        (setq extra (concat extra "<meta property=\"og:type\" content=\"" og-type "\"/>\n")))
      (when (and published
                 (not (string-match-p "property=\"article:published_time\"" html)))
        (setq extra
              (concat extra
                      "<meta property=\"article:published_time\" content=\""
                      published "T00:00:00+08:00\"/>\n")))
      (when (and modified
                 (not (equal modified published))
                 (not (string-match-p "property=\"article:modified_time\"" html)))
        (setq extra
              (concat extra
                      "<meta property=\"article:modified_time\" content=\""
                      modified "T00:00:00+08:00\"/>\n")))
      (when (and image (not (string-match-p "property=\"og:image\"" html)))
        (setq extra
              (concat extra "<meta property=\"og:image\" content=\""
                      (opskumu-org--html-escape image) "\"/>\n")))
      (unless (string-match-p "name=\"twitter:title\"" html)
        (setq extra (concat extra "<meta name=\"twitter:title\" content=\"" (opskumu-org--html-escape title) "\"/>\n")))
      (unless (string-match-p "name=\"twitter:description\"" html)
        (setq extra (concat extra "<meta name=\"twitter:description\" content=\"" (opskumu-org--html-escape description) "\"/>\n")))
      (when (and image (not (string-match-p "name=\"twitter:image\"" html)))
        (setq extra
              (concat extra "<meta name=\"twitter:image\" content=\""
                      (opskumu-org--html-escape image) "\"/>\n")))
      (unless (string-match-p "type=\"application/atom\\+xml\"" html)
        (setq extra
              (concat extra
                      "<link rel=\"alternate\" type=\"application/atom+xml\" "
                      "title=\"Kumu's Blog\" href=\""
                      opskumu-org--site-url "atom.xml\"/>\n")))
      (unless (string-match-p "type=\"application/ld\\+json\"" html)
        (setq extra
              (concat extra
                      (opskumu-org--json-ld-html
                       title description url is-index published modified image))))
      (when image
        (setq html
              (replace-regexp-in-string
               "<meta name=\"twitter:card\" content=\"[^\"]*\" ?/?>"
               "<meta name=\"twitter:card\" content=\"summary_large_image\"/>"
               html t t)))
      (if (string-empty-p extra)
          html
        (setq html (replace-regexp-in-string "</head>" (concat extra "</head>") html t t)))
      (opskumu-org--inject-article-nav html))))

(defun opskumu-org--html-description-from-file (file)
  "Read FILE's exported meta description."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward
             "<meta name=\"description\" content=\"\\([^\"]*\\)\""
             nil t)
        (opskumu-org--decode-html-text (match-string 1))))))

(defun opskumu-org--xml-escape (text)
  "Escape TEXT for use in XML text nodes."
  (let ((escaped (or text "")))
    (setq escaped (replace-regexp-in-string "&" "&amp;" escaped t t))
    (setq escaped (replace-regexp-in-string "<" "&lt;" escaped t t))
    (replace-regexp-in-string ">" "&gt;" escaped t t)))

(defun opskumu-org--write-discovery-files (html-dir)
  "Write sitemap.xml and atom.xml into HTML-DIR."
  (let* ((posts (opskumu-org--archive-posts))
         (updated (or (plist-get (car posts) :date) "1970-01-01"))
         (sitemap-file (expand-file-name "sitemap.xml" html-dir))
         (atom-file (expand-file-name "atom.xml" html-dir)))
    (with-temp-file sitemap-file
      (insert "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
      (insert "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n")
      (insert "  <url><loc>" opskumu-org--site-url "</loc><lastmod>"
              updated "</lastmod></url>\n")
      (dolist (post posts)
        (insert "  <url><loc>"
                (opskumu-org--xml-escape
                 (concat opskumu-org--site-url
                         (opskumu-org--post-url post)))
                "</loc><lastmod>" (plist-get post :date)
                "</lastmod></url>\n"))
      (insert "</urlset>\n"))
    (with-temp-file atom-file
      (insert "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
      (insert "<feed xmlns=\"http://www.w3.org/2005/Atom\" xml:lang=\"zh-CN\">\n")
      (insert "  <title>Kumu's Blog</title>\n")
      (insert "  <id>" opskumu-org--site-url "</id>\n")
      (insert "  <link href=\"" opskumu-org--site-url "\"/>\n")
      (insert "  <link rel=\"self\" href=\"" opskumu-org--site-url
              "atom.xml\"/>\n")
      (insert "  <updated>" updated "T00:00:00+08:00</updated>\n")
      (dolist (post (seq-take posts 20))
        (let* ((url (concat opskumu-org--site-url
                            (opskumu-org--post-url post)))
               (html-file (expand-file-name
                           (opskumu-org--post-url post) html-dir))
               (description
                (or (opskumu-org--html-description-from-file html-file)
                    (plist-get post :title))))
          (insert "  <entry>\n")
          (insert "    <title>"
                  (opskumu-org--xml-escape (plist-get post :title))
                  "</title>\n")
          (insert "    <id>" (opskumu-org--xml-escape url) "</id>\n")
          (insert "    <link href=\"" (opskumu-org--xml-escape url) "\"/>\n")
          (insert "    <updated>" (plist-get post :date)
                  "T00:00:00+08:00</updated>\n")
          (insert "    <summary type=\"text\">"
                  (opskumu-org--xml-escape description)
                  "</summary>\n")
          (insert "  </entry>\n")))
      (insert "</feed>\n"))))

(defun opskumu-org--copy-referenced-images (html-dir images-dir)
  "Copy only images referenced by generated pages into HTML-DIR."
  (let ((target-root (expand-file-name "images/" html-dir))
        (referenced (make-hash-table :test #'equal)))
    (dolist (html-file (directory-files html-dir t "\\.html\\'"))
      (with-temp-buffer
        (insert-file-contents html-file)
        (goto-char (point-min))
        (while (re-search-forward "src=\"images/\\([^\"]+\\)\"" nil t)
          (puthash (match-string 1) t referenced))))
    (when (file-directory-p target-root)
      (delete-directory target-root t))
    (maphash
     (lambda (relative _)
       (unless (or (file-name-absolute-p relative)
                   (string-match-p "\\.\\." relative))
         (let ((source (expand-file-name relative images-dir))
               (target (expand-file-name relative target-root)))
           (when (file-readable-p source)
             (make-directory (file-name-directory target) t)
             (copy-file source target t t)))))
     referenced)))

(defun opskumu-org--copy-deployment-assets (static-dir html-dir)
  "Copy deployment metadata from STATIC-DIR to HTML-DIR."
  (dolist (name '("CNAME" ".nojekyll" "favicon.ico" "robots.txt"))
    (let ((source (expand-file-name name static-dir))
          (target (expand-file-name name html-dir)))
      (when (file-readable-p source)
        (copy-file source target t t)))))

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
  (add-to-list 'org-export-before-parsing-functions
               #'opskumu-org--export-paper-ref-links)
  (setq org-html-html5-fancy t
        org-html-doctype "html5"
        org-html-validation-link nil
        org-export-time-stamp-file nil
        org-export-with-sub-superscripts '{}
        org-export-default-language "zh-CN"
        org-html-preamble t
        org-html-preamble-format
        `(("zh-CN" ,opskumu-org--chrome-html)
          ("en" ,opskumu-org--chrome-html))
        org-html-postamble t
        org-html-postamble-format
        '(("zh-CN" "<a class=\"author\" href=\"https://blog.opskumu.com\">%a</a><span class=\"postamble-sep\" aria-hidden=\"true\"> / </span><span class=\"date\">%d</span><span class=\"creator\"><a href=\"atom.xml\">Atom 订阅</a><span class=\"postamble-sep\" aria-hidden=\"true\"> · </span>Generated with <a href=\"https://www.gnu.org/software/emacs/\">Emacs</a> + <a href=\"https://orgmode.org/\">Org</a></span>")
          ("en" "<a class=\"author\" href=\"https://blog.opskumu.com\">%a</a><span class=\"postamble-sep\" aria-hidden=\"true\"> / </span><span class=\"date\">%d</span><span class=\"creator\"><a href=\"atom.xml\">Atom feed</a><span class=\"postamble-sep\" aria-hidden=\"true\"> · </span>Generated with <a href=\"https://www.gnu.org/software/emacs/\">Emacs</a> + <a href=\"https://orgmode.org/\">Org</a></span>")))
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
         (timestamps (expand-file-name ".org-timestamps/" html)))
    (unless (file-directory-p src)
      (error "Expected src at %s" src))
    (opskumu-org--validate-archive)
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
             :exclude "\\`\\."
             :publishing-function org-html-publish-to-html
             :headline-levels 4
             :auto-preamble t)
            ("static"
             :base-directory ,static
             :base-extension "css\\|js\\|ico\\|txt\\|png\\|jpg\\|gif\\|pdf\\|mp3\\|ogg\\|swf"
             :publishing-directory ,html
             :recursive t
             :publishing-function org-publish-attachment)
            ("org" :components ("notes" "static"))))
    ;; Force: regenerate all HTML and recopy assets (avoids stale head/CSS).
    (org-publish-project "org" t)
    (opskumu-org--write-article-navs html)
    (opskumu-org--copy-referenced-images html images)
    (opskumu-org--copy-deployment-assets static html)
    (opskumu-org--write-discovery-files html)))
