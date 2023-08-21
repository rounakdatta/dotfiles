;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "Rounak Datta"
      user-mail-address "rounakdatta12@gmail.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; They all accept either a font-spec, font string ("Input Mono-12"), or xlfd
;; font string. You generally only need these two:
;; (setq doom-font (font-spec :family "monospace" :size 12 :weight 'semi-light)
;;       doom-variable-pitch-font (font-spec :family "sans" :size 13))

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one-light)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/personal/rounakdatta.github.io/")

(setq projectile-project-search-path '("~/personal/" "~/hotstar/" "~/tooling/"))

;; org-roam setting
(setq org-roam-link-title-format "R:%s")
(setq org-roam-directory "~/personal/rounakdatta.github.io")
(setq org-roam-index-file "index.org")
;;org-roam completion system
(setq org-roam-completion-system 'default)
;; org-roam template
(setq org-roam-capture-templates
      '(("h" "blog" plain
       (function org-roam--capture-get-point)
       "%?"
       :file-name "%<%Y%m%d%H%M%S>-${slug}"
       :head "#+HUGO_BASE_DIR: ./src
#+HUGO_TAGS: %^{Tags}
#+EXPORT_FILE_NAME: %^{export name}
#+TITLE: ${title}
#+AUTHOR: Rounak Datta
#+DATE: %t"
       :unnarrowed t)
        ("r" "interviewer" plain
       (function org-roam--capture-get-point)
       "%?"
       :file-name "%<%Y%m%d%H%M%S>-${slug}"
       :head "#+HUGO_BASE_DIR: ./src
#+HUGO_TAGS: %^{Tags}
#+EXPORT_FILE_NAME: %^{export name}
#+TITLE: Hotstar Interview Candidate - ${title}
#+AUTHOR: Rounak Datta
#+DATE: %t

* ${title}
- Lever: [[LEVER_URL]]
- Vote: DECISION
- Competencies being covered: COMPETENCY

** Highlights


** Raises the bar
-

** At the bar
-

** Below the bar
-

** Reasons for leaving the company
-

** Questions for the team
-

** Problems asked & Candidate's solution
*** ORG_BACKLINK_TO_PROBLEM
#+begin_src LANGUAGE
#+end_src

**** Pros
-
**** Cons
-
"
       :unnarrowed t)
        ("p" "problem" plain
       (function org-roam--capture-get-point)
       "%?"
       :file-name "%<%Y%m%d%H%M%S>-${slug}"
       :head "#+HUGO_BASE_DIR: ./src
#+HUGO_TAGS: %^{Tags}
#+EXPORT_FILE_NAME: %^{export name}
#+TITLE: Hotstar Interview Problem - ${title}
#+AUTHOR: Rounak Datta
#+DATE: %t

* ${title}

** Problem Statement


** Discussion


** Input
#+begin_src
Input:
Output:
#+end_src

** Solution
#+begin_src C++ :flags --std=c++11 :exports both
#+end_src

"
       :unnarrowed t)
        ("g" "self-goals" plain
       (function org-roam--capture-get-point)
       "%?"
       :file-name "%<%Y%m%d%H%M%S>-${slug}"
       :head "#+HUGO_BASE_DIR: ./src
#+HUGO_TAGS: %^{Tags}
#+EXPORT_FILE_NAME: %^{export name}
#+TITLE: Where do you see yourself in ${title}
#+AUTHOR: Rounak Datta
#+DATE: %t

* Current
** Career
*** Interesting turns
*** Pain points
*** Investment scope
** Hobby
*** Interesting turns
*** Pain points
*** Investment scope
** Life
*** Interesting turns
*** Pain points
*** Investment scope

* The future time point
** Career
*** Investment returns
*** Regret minimization
*** Furthur investment scope
** Hobby
*** Investment returns
*** Regret minimization
*** Furthur investment scope
** Life
*** Investment returns
*** Regret minimization
*** Furthur investment scope
"
       :unnarrowed t)
      ("d" "default" plain
       (function org-roam--capture-get-point)
       "%?"
       :file-name "%<%Y%m%d%H%M%S>-${slug}"
       :head "#+TITLE: ${title} \n#+ROAM_ALIAS: \n - tags :: \n"
       :unnarrowed t)

      ("r" "ref" plain
       (function org-roam--capture-get-point)
         "%?"
         :file-name "%<%Y%m%d%H%M%S>-${slug}"
         :head "#+ROAM_KEY: ${ref}
#+TITLE: ${title}\n - tags :: \n"
         :unnarrowed t)
      ))

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)


;; Here are some additional functions/macros that could help you configure Doom:
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.