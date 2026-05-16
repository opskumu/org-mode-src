;; -*- mode: emacs-lisp -*-
;; This file is loaded by Spacemacs at startup.
;; It must be stored in your home directory.


;; org 自动换行
(add-hook 'org-mode-hook 'toggle-truncate-lines)

(require 'ox-publish)
(require 'ox-html)
(require 'org-tempo)
(setq org-html-html5-fancy t
      org-html-doctype "html5")

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
   "</nav>"))

(defun opskumu-org--html-escape (text)
  "Escape TEXT for safe insertion into HTML attributes."
  (let ((escaped (or text "")))
    (setq escaped (replace-regexp-in-string "&" "&amp;" escaped t t))
    (setq escaped (replace-regexp-in-string "\"" "&quot;" escaped t t))
    (setq escaped (replace-regexp-in-string "<" "&lt;" escaped t t))
    (replace-regexp-in-string ">" "&gt;" escaped t t)))

(defun opskumu-org--paper-ref-export (path _description backend _info)
  "Export paper-style reference PATH as a compact superscript citation."
  (let* ((refs (split-string (or path "") "[,;[:space:]]+" t))
         (label (mapconcat #'identity refs ", ")))
    (if (org-export-derived-backend-p backend 'html)
        (concat
         "<sup class=\"paper-ref\">"
         (mapconcat
          (lambda (ref)
            (let ((escaped (opskumu-org--html-escape ref)))
              (concat "<a href=\"#ref-" escaped "\">" escaped "</a>")))
          refs
          ", ")
         "</sup>")
      (concat "[" label "]"))))

(org-link-set-parameters "paperref" :export #'opskumu-org--paper-ref-export)

;; Postamble.
(setq org-export-default-language "zh-CN"
      org-html-preamble t
      org-html-preamble-format
      `(("zh-CN" ,opskumu-org--chrome-html)
        ("en" ,opskumu-org--chrome-html))
      org-html-postamble t
      org-html-postamble-format
      '(("zh-CN" "<a class=\"author\" href=\"https://blog.opskumu.com\">%a</a><span class=\"postamble-sep\" aria-hidden=\"true\"> / </span><span class=\"date\">%d</span><span class=\"creator\">%c</span>")
        ("en" "<a class=\"author\" href=\"https://blog.opskumu.com\">%a</a><span class=\"postamble-sep\" aria-hidden=\"true\"> / </span><span class=\"date\">%d</span><span class=\"creator\">%c</span>")))

(setq org-html-htmlize-output-type 'css)
(setq org-html-validation-link nil)
(setq org-export-with-sub-superscripts '{})
;; (setq org-publish-use-timestamps-flag nil)

;; Postamble.
(setq org-publish-project-alist
      '(
        ("notes"
         :base-directory "~/Dev/personal/opskumu/org/src/"
         :base-extension "org"
         :publishing-directory "~/Dev/personal/opskumu/org/html/"
         :recursive t
         :publishing-function org-html-publish-to-html
         :headline-levels 4             ; Just the default for this project.
         :auto-preamble t
        )
        ("static"
         :base-directory "~/Dev/personal/opskumu/org/static/"
         :base-extension "css\\|js\\|png\\|jpg\\|gif\\|pdf\\|mp3\\|ogg\\|swf"
         :publishing-directory "~/Dev/personal/opskumu/org/html/"
         :recursive t
         :publishing-function org-publish-attachment
         )
        ("images"
         :base-directory "~/Dev/personal/opskumu/org/images/"
         :base-extension "png\\|jpg\\|gif"
         :publishing-directory "~/Dev/personal/opskumu/org/html/images/"
         :recursive t
         :publishing-function org-publish-attachment
         )

        ("org" :components ("notes" "static" "images"))
      ))
