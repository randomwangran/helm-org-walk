;;; org-olp.el --- Helpful olp functions

;; Author: Dustin Lacewell <dlacewell@gmail.com>
;; Version: 0.1.0
;; Keywords: org-mode olp

;; This is free and unencumbered software released into the public domain.

;; Anyone is free to copy, modify, publish, use, compile, sell, or
;; distribute this software, either in source code form or as a compiled
;; binary, for any purpose, commercial or non-commercial, and by any
;; means.

;; In jurisdictions that recognize copyright laws, the author or authors
;; of this software dedicate any and all copyright interest in the
;; software to the public domain. We make this dedication for the benefit
;; of the public at large and to the detriment of our heirs and
;; successors. We intend this dedication to be an overt act of
;; relinquishment in perpetuity of all present and future rights to this
;; software under copyright law.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
;; IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
;; OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
;; ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;; OTHER DEALINGS IN THE SOFTWARE.

;; For more information, please refer to <http://unlicense.org>

;;; Commentary:

;; Helpful olp functions
;;
;; See documentation at https://github.com/dustinlacewell/org-olp#functions

;;; Code:

(defmacro org-olp--with-buffer (file-name &rest body)
  "Open a temporary buffer with the contents of FILE-NAME and
execute BODY forms."
  (declare (indent defun))
  `(if ,file-name
       (with-temp-buffer
         (insert-file-contents (expand-file-name ,file-name))
         (org-mode)
         ,@body)
     (progn ,@body)))

(cl-defun org-olp--matches (file-name regexp &key (which 0))
  "Return a list of matches of REGEXP in FILE-NAME or the current buffer if nil."
  (let ((matches))
    (save-match-data
      (save-excursion
        (org-olp--with-buffer file-name
                              (save-restriction
                                (widen)
                                (goto-char 1)
                                (while (search-forward-regexp regexp nil t 1)
                                  (push (match-string which) matches)))))
      (reverse matches))))

(defun org-olp--top-level-headings (file-name)
  "Return top-level headings in FILE-NAME."
  (org-olp--matches file-name "^\\*[ ]+\\(.+\\)$" :which 1))

(defun org-olp--subheadings-at-point (&optional recursive)
  "Return a list of subheadings. If RECURSIVE, return a list of
   all headings in subheading subtrees."
  (org-save-outline-visibility t
      (save-excursion
        (let ((pred (lambda () (org-entry-get nil "ITEM"))))
          (if recursive
              (org-map-entries pred nil 'tree)
            (progn
              (org-back-to-heading t)
              (org-show-subtree)
              (if (org-goto-first-child)
                  (cl-loop collect (funcall pred)
                           until (let ((pos (point)))
                                   (null (org-forward-heading-same-level nil t))
                                   (eq pos (point)))))))))))

(defun org-olp--olp-subheadings (file-name olp &optional recursive)
  "Return subheadings of OLP in FILE-NAME, recursing if RECURSIVE."
  (org-olp--with-buffer file-name
                        (goto-char (org-find-olp olp 't))
                        (org-olp--subheadings-at-point recursive)))

(defun org-olp--goto-end ()
  "Either go to the end of line or to the end of the content for that element"
  (let ((cend (org-element-property :contents-end (org-element-at-point))))
    (goto-char (if cend cend (point-at-eol)))
    ))

(defun org-olp--select-agenda-file (&optional prompt)
  "Select a file from org-agenda-files using PROMPT"
  (let ((file-name (completing-read (or prompt "Select file: ") org-agenda-files)))
    (if (not (file-exists-p file-name))
        (concat org-directory file-name ".org")
      file-name)))

(cl-defun org-olp--helm-next ((file-name olp pick))
  (helm-org-olp-pick file-name `(,@olp ,pick)))

(cl-defun org-olp--helm-previous ((file-name olp pick))
  (if olp
      (helm-org-olp-pick file-name (butlast olp))
    (if file-name
        (helm-org-olp-find '(1))
      (helm-org-olp-pick file-name))))

(cl-defun org-olp--helm-visit ((file-name olp pick))
  `(,@olp ,pick))

(defun org-olp--helm-abort (_) nil)

(defvar org-olp-helm-actions
  '(("Select" . org-olp--helm-next)
    ("Previous" . org-olp--helm-previous)
    ("Visit" . org-olp--helm-visit)
    ("Abort" . org-olp--helm-abort)))

(defun org-olp--next-pick ()
  (interactive)
  (helm-exit-and-execute-action 'org-olp--helm-next))

(defun org-olp--previous-pick ()
  (interactive)
  (helm-exit-and-execute-action 'org-olp--helm-previous))

(defun org-olp--pick-visit ()
  (interactive)
  (helm-exit-and-execute-action 'org-olp--helm-visit))

(defun org-olp--pick-abort ()
  (interactive)
  (helm-exit-and-execute-action 'org-olp--helm-abort))

(setq helm-org-olp-find-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map helm-map)
    (define-key map (kbd "C-<backspace>") 'org-olp--previous-pick)
    (define-key map (kbd "C-<return>") 'org-olp--pick-visit)
    (define-key map (kbd "C-g") 'org-olp--pick-abort)
    map))

(defun helm-org-olp-pick (file-name &optional olp)
  "Use helm to pick headings from FILE-NAME, starting at OLP, to form a new olp path."
  (org-olp--with-buffer file-name
                        (-let* ((children (if olp (org-olp--olp-subheadings file-name olp)
                                            (org-olp--top-level-headings file-name))))
                          (if (not children) olp
                            (-let* ((candidates (--map (cons it `(,file-name ,olp ,it)) children))
                                    (actions org-olp-helm-actions)
                                    (sources (helm-build-sync-source (s-join "/" olp)
                                               :keymap helm-org-olp-find-map
                                               :candidates candidates
                                               :action actions)))
                              (helm :sources sources))))))

(cl-defun org-olp-visit (file-name olp)
  "Visit the heading in FILE-NAME denoted by OLP"
  (let ((marker (if file-name
                    (org-find-olp `(,file-name ,@olp))
                  (org-find-olp olp t))))
    (switch-to-buffer (marker-buffer marker))
    (goto-char marker)
    (call-interactively 'recenter-top-bottom)))

(defun org-olp-refile (src-file-name olp-src dst-file-name olp-dst)
  "This function takes a filename and two olp paths it uses the
org-element api to remove the heading specified by the first olp and
then inserts the element *under* the heading pointed to by the second olp
"

  (org-olp-visit src-file-name olp-src)
  (let ((src-level (org-element-property :level (org-element-at-point))))
    (org-cut-subtree)
    (org-olp-visit dst-file-name olp-dst)
    (outline-show-all)
    (let ((dst-level (org-element-property :level (org-element-at-point)))
          (dst-contents-end (org-element-property :contents-end (org-element-at-point))))
      (cond ((= src-level (+ dst-level 1)) (progn
                                             (org-olp--goto-end)
                                             (org-paste-subtree (+ dst-level 1))))
            ((> src-level (+ dst-level 1)) (progn
                                             (org-olp--goto-end)
                                             (org-paste-subtree (+ dst-level 1))))
            ((< src-level (+ dst-level 1)) (progn
                                             (org-olp--goto-end)
                                             (org-paste-subtree (+ dst-level 1))))))
    (org-content 1)
    (setq current-prefix-arg '(8))
    (org-reveal t)
    (call-interactively 'org-cycle)))

(cl-defun helm-org-olp-find (file-name &optional olp)
  "Run org-olp-recursive-select on FILE-NAME, starting from OLP
or top-level, then visit the selected heading."
  (interactive "P")
  (let* ((file-name (if (and file-name (listp file-name))
                        (org-olp--select-agenda-file)
                      file-name)))
    (-when-let (olp (helm-org-olp-pick file-name olp))
      (org-olp-visit file-name olp)
      (beginning-of-line)
      (call-interactively 'org-cycle))))

(defun helm-org-olp-refile-this (arg)
  (interactive "P")
  (let* ((src-file-name nil)
         (src-olp (org-get-outline-path t t))
         (dst-file-name (if (and arg (listp arg))
                            (org-olp--select-agenda-file)
                          src-file-name))
         (dst-olp (helm-org-olp-pick dst-file-name)))
    (org-olp-refile src-file-name src-olp dst-file-name dst-olp)))

(provide 'org-olp)
