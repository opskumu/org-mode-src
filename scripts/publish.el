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
  (setq org-html-html5-fancy t
        org-html-doctype "html5"
        org-html-validation-link nil
        org-export-with-sub-superscripts '{}
        org-html-postamble t
        org-html-postamble-format
        '(("en" "<a class=\"author\" href=\"https://blog.opskumu.com\">%a</a><span class=\"postamble-sep\" aria-hidden=\"true\"> / </span><span class=\"date\">%d</span><span class=\"creator\">%c</span>")))
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
         (html-images (expand-file-name "html/images/" root)))
    (unless (file-directory-p src)
      (error "Expected src at %s" src))
    (opskumu-org--init-export-settings)
    (require 'ox-html)
    (require 'ox-publish)
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
    (org-publish-project "org" t)))
