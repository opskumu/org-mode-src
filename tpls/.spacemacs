;; -*- mode: emacs-lisp -*-
;; This file is loaded by Spacemacs at startup.
;; It must be stored in your home directory.

;; org 自动换行
(add-hook 'org-mode-hook 'toggle-truncate-lines)

(require 'ox-publish)
(require 'ox-html)
(require 'org-tempo)

;; Postamble.
(setq org-html-postamble t
      org-html-postamble-format
      '(("en" "<a class=\"author\"
         href=\"https://blog.opskumu.com\">%a</a> / <span
         class=\"date\">%d</span><span class=\"creator\">%c</span>")))

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
