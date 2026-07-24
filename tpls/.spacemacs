;; -*- mode: emacs-lisp -*-
;; Copy this file to ~/.spacemacs when publishing the blog interactively.

;; Org buffers wrap naturally while editing.
(add-hook 'org-mode-hook #'toggle-truncate-lines)

(require 'org-tempo)

;; Keep interactive and batch publishing on the same implementation.
(defconst opskumu-org-source-root
  (expand-file-name "~/Dev/personal/opskumu/org/")
  "Local checkout containing the blog Org sources.")

(load-file (expand-file-name "scripts/publish.el" opskumu-org-source-root))

;; Publish with:
;;   M-x opskumu-org-publish
