;;; lisp/lib/projects.el -*- lexical-binding: t; -*-

;; HACK We forward declare these variables because they are let-bound in a
;;      number of places with no guarantee that they've been defined yet (i.e.
;;      that `projectile' is loaded). If a variable is defined with `defvar'
;;      while it is lexically bound, you get "Defining as dynamic an already
;;      lexical var" errors in Emacs 28+).
;;;###autoload (defvar projectile-project-root nil)
;;;###autoload (defvar projectile-enable-caching (not noninteractive))
;;;###autoload (defvar projectile-require-project-root 'prompt)

;;;###autodef
(cl-defun set-project-type! (name &key predicate compile run test configure dir)
  "Add a project type to `projectile-project-type'."
  (declare (indent 1))
  (after! projectile
    (add-to-list 'projectile-project-types
                 (list name
                       'marker-files predicate
                       'compilation-dir dir
                       'configure-command configure
                       'compile-command compile
                       'test-command test
                       'run-command run))))


;;
;;; Macros

;;;###autoload
(defmacro project-file-exists-p! (files &optional base-directory)
  "Checks if FILES exist at the current project's root.

The project's root is determined by `projectile', starting from BASE-DIRECTORY
(defaults to `default-directory'). FILES are paths relative to the project root,
unless they begin with a slash."
  `(file-exists-p! ,files (doom-project-root ,base-directory)))


;;
;;; Commands

;;;###autoload
(defun doom/find-file-in-other-project (project-root)
  "Performs `projectile-find-file' in a known project of your choosing."
  (interactive
   (list
    (completing-read "Find file in project: " (projectile-relevant-known-projects))))
  (unless (file-directory-p project-root)
    (error "Project directory '%s' doesn't exist" project-root))
  (doom-project-find-file project-root))

;;;###autoload
(defun doom/browse-in-other-project (project-root)
  "Performs `find-file' in a known project of your choosing."
  (interactive
   (list
    (completing-read "Browse in project: " (projectile-relevant-known-projects))))
  (unless (file-directory-p project-root)
    (error "Project directory '%s' doesn't exist" project-root))
  (doom-project-browse project-root))

;;;###autoload
(defun doom/browse-in-emacsd ()
  "Browse files from `doom-emacs-dir'."
  (interactive) (doom-project-browse doom-emacs-dir))

;;;###autoload
(defun doom/find-file-in-emacsd ()
  "Find a file under `doom-emacs-dir', recursively."
  (interactive) (doom-project-find-file doom-emacs-dir))

;;;###autoload
(defun doom/add-directory-as-project (dir)
  "Register an arbitrary directory as a project.

Unlike `projectile-add-known-project', if DIR isn't a valid project, a .project
file will be created within it so that it will always be treated as one. This
command will throw an error if a parent of DIR is a valid project (which would
mask DIR)."
  (interactive "D")
  (when-let ((proj-dir (doom-project-root dir)))
    (if (file-equal-p proj-dir dir)
        (user-error "ERROR: Directory is already a project: %s" proj-dir)
      (user-error "ERROR: Directory is already inside another project: %s" proj-dir)))
  (let ((short-dir (abbreviate-file-name dir)))
    (when (projectile-ignored-project-p dir)
      (user-error "ERROR: Directory is in projectile's ignore list: %s" short-dir))
    (dolist (proj projectile-known-projects)
      (when (file-in-directory-p proj dir)
        (user-error "ERROR: Directory contains a known project: %s" short-dir))
      (when (file-equal-p proj dir)
        (user-error "ERROR: Directory is already a known project: %s" short-dir)))
    (with-temp-file (doom-path dir ".project"))
    (message "Added directory as a project: %s" short-dir)
    (projectile-add-known-project dir)))


;;
;;; Library

;;;###autoload
(defun doom-project-p (&optional dir)
  "Return t if DIR (defaults to `default-directory') is a valid project."
  (and (doom-project-root dir)
       t))

;;;###autoload
(defun doom-project-root (&optional dir)
  "Return the project root of DIR (defaults to `default-directory').
Returns nil if not in a project."
  (let ((projectile-project-root
         (unless dir (bound-and-true-p projectile-project-root)))
        projectile-require-project-root)
    (projectile-project-root dir)))

;;;###autoload
(defun doom-project-name (&optional dir)
  "Return the name of the current project.

Returns '-' if not in a valid project."
  (if-let* ((project-root (or (doom-project-root dir)
                              (if dir (expand-file-name dir)))))
      (funcall projectile-project-name-function project-root)
    "-"))

;;;###autoload
(defun doom-project-expand (name &optional dir)
  "Expand NAME to project root."
  (expand-file-name name (doom-project-root dir)))

;;;###autoload
(defun doom-project-find-file (dir)
  "Jump to a file in DIR (searched recursively).

If DIR is not a project, it will be indexed (but not cached)."
  (unless (file-directory-p dir)
    (error "Directory %S does not exist" dir))
  (unless (file-readable-p dir)
    (error "Directory %S isn't readable" dir))
  (let* ((default-directory (file-truename dir))
         (projectile-project-root (doom-project-root dir))
         (projectile-enable-caching projectile-enable-caching))
    (cond ((and projectile-project-root (file-equal-p projectile-project-root default-directory))
           (unless (doom-project-p default-directory)
             ;; Disable caching if this is not a real project; caching
             ;; non-projects easily has the potential to inflate the projectile
             ;; cache beyond reason.
             (setq projectile-enable-caching nil))
           (call-interactively
            ;; Intentionally avoid `helm-projectile-find-file', because it runs
            ;; asynchronously, and thus doesn't see the lexical
            ;; `default-directory'
            (if (doom-module-active-p :completion 'ivy)
                #'counsel-projectile-find-file
              #'projectile-find-file)))
          ((and (bound-and-true-p ivy-mode)
                (fboundp 'counsel-file-jump))
           (call-interactively #'counsel-file-jump))
          ((and (bound-and-true-p helm-mode)
                (fboundp 'helm-find-files))
           (call-interactively #'helm-find-files))
          ((when-let* ((project-current-directory-override dir)
                       (pr (project-current t dir)))
             (condition-case _
                 (project-find-file-in nil (list dir) pr t)
               ;; FIX: project.el throws errors if DIR is an empty directory,
               ;;   which is poor UX.
               (wrong-type-argument
                (call-interactively #'find-file)))))
          ((call-interactively #'find-file)))))

;;;###autoload
(defun doom-project-browse (dir)
  "Traverse a file structure starting linearly from DIR."
  (let ((default-directory (file-truename (expand-file-name dir))))
    (call-interactively
     (cond ((doom-module-active-p :completion 'ivy)
            #'counsel-find-file)
           ((doom-module-active-p :completion 'helm)
            #'helm-find-files)
           (#'find-file)))))

;;;###autoload
(defun doom-project-ignored-p (project-root)
  "Return non-nil if temporary file or a straight package."
  (unless (file-remote-p project-root)
    (or (file-in-directory-p project-root temporary-file-directory)
        (file-in-directory-p project-root doom-local-dir))))

(provide 'doom-lib '(projects))
;;; projects.el ends here
