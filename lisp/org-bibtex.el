;;; org-bibtex.el --- Org links to BibTeX entries
;;
;; Copyright (C) 2007, 2008, 2009, 2010, 2011 Free Software Foundation, Inc.
;;
;; Author: Bastien Guerry <bzg at altern dot org>
;;         Carsten Dominik <carsten dot dominik at gmail dot com>
;;         Eric Schulte <schulte dot eric at gmail dot com>
;; Keywords: org, wp, remember
;; Version: 7.5
;;
;; This file is part of GNU Emacs.
;;
;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;; This file implements links to database entries in BibTeX files.
;; Instead of defining a special link prefix, it uses the normal file
;; links combined with a custom search mechanism to find entries
;; by reference key.  And it constructs a nice description tag for
;; the link that contains the author name, the year and a short title.
;;
;; It also stores detailed information about the entry so that
;; remember templates can access and enter this information easily.
;;
;; The available properties for each entry are listed here:
;;
;; :author        :publisher      :volume      :pages
;; :editor        :url            :number      :journal
;; :title         :year           :series      :address
;; :booktitle     :month          :annote      :abstract
;; :key           :btype
;;
;; Here is an example of a remember template that use some of this
;; information (:author :year :title :journal :pages):
;;
;; (setq org-remember-templates
;;   '((?b "* READ %?\n\n%a\n\n%:author (%:year): %:title\n   \
;;          In %:journal, %:pages.")))
;;
;; Let's say you want to remember this BibTeX entry:
;;
;; @Article{dolev83,
;;   author = 	 {Danny Dolev and Andrew C. Yao},
;;   title = 	 {On the security of public-key protocols},
;;   journal = 	 {IEEE Transaction on Information Theory},
;;   year = 	 1983,
;;   volume =	 2,
;;   number =	 29,
;;   pages =	 {198--208},
;;   month =	 {Mars}
;; }
;;
;; M-x `org-remember' on this entry will produce this buffer:
;;
;; =====================================================================
;; * READ <== [point here]
;;
;; [[file:file.bib::dolev83][Dolev & Yao 1983: security of public key protocols]]
;;
;; Danny Dolev and Andrew C. Yao (1983): On the security of public-key protocols
;; In IEEE Transaction on Information Theory, 198--208.
;; =====================================================================
;;
;; Additionally, the following functions are now available for storing
;; bibtex entries within Org-mode documents.
;;
;; - Run `org-bibtex' to export the current file to a .bib.
;;
;; - Run `org-bibtex-check' or `org-bibtex-check-all' to check and
;;   fill in missing field of either the current, or all headlines
;;
;; - Run `org-bibtex-create' to add a bibtex entry
;;
;; - Use `org-bibtex-read' to read a bibtex entry after `point' or in
;;   the active region, then call `org-bibtex-write' in a .org file to
;;   insert a heading for the read bibtex entry
;;
;; - All Bibtex information is taken from the document compiled by
;;   Andrew Roberts from the Bibtex manual, available at
;;   http://www.andy-roberts.net/misc/latex/sessions/bibtex/bibentries.pdf
;;
;;; History:
;;
;; The link creation part has been part of Org-mode for a long time.
;;
;; Creating better remember template information was inspired by a request
;; of Austin Frank: http://article.gmane.org/gmane.emacs.orgmode/4112
;; and then implemented by Bastien Guerry.
;;
;; Eric Schulte eventually added the functions for translating between
;; Org-mode headlines and Bibtex entries, and for fleshing out the Bibtex
;; fields of existing Org-mode headlines.
;;
;; Org-mode loads this module by default - if this is not what you want,
;; configure the variable `org-modules'.

;;; Code:

(require 'org)
(require 'bibtex)

(defvar description nil) ; dynamically scoped from org.el

(declare-function bibtex-beginning-of-entry "bibtex" ())
(declare-function bibtex-generate-autokey "bibtex" ())
(declare-function bibtex-parse-entry "bibtex" (&optional content))
(declare-function bibtex-url "bibtex" (&optional pos no-browse))
(declare-function longlines-mode "longlines" (&optional arg))


;;; Bibtex data
(defvar org-bibtex-types
  '((:article
     (:description . "An article from a journal or magazine")
     (:required :author :title :journal :year)
     (:optional :volume :number :pages :month :note))
    (:book
     (:description . "A book with an explicit publisher")
     (:required (:editor :author) :title :publisher :year)
     (:optional (:volume :number) :series :address :edition :month :note))
    (:booklet
     (:description . "A work that is printed and bound, but without a named publisher or sponsoring institution.")
     (:required :title)
     (:optional :author :howpublished :address :month :year :note))
    (:conference
     (:description . "")
     (:required :author :title :booktitle :year)
     (:optional :editor :pages :organization :publisher :address :month :note))
    (:inbook
     (:description . "A part of a book, which may be a chapter (or section or whatever) and/or a range of pages.")
     (:required (:author :editor) :title (:chapter :pages) :publisher :year)
     (:optional (:volume :number) :series :type :address :edition :month :note))
    (:incollection
     (:description . "A part of a book having its own title.")
     (:required :author :title :booktitle :publisher :year)
     (:optional :editor (:volume :number) :series :type :chapter :pages :address :edition :month :note))
    (:inproceedings
     (:description . "An article in a conference proceedings")
     (:required :author :title :booktitle :year)
     (:optional :editor (:volume :number) :series :pages :address :month :organization :publisher :note))
    (:manual
     (:description . "Technical documentation.")
     (:required :title)
     (:optional :author :organization :address :edition :month :year :note))
    (:mastersthesis
     (:description . "A Master’s thesis.")
     (:required :author :title :school :year)
     (:optional :type :address :month :note))
    (:misc
     (:description . "Use this type when nothing else fits.")
     (:required)
     (:optional :author :title :howpublished :month :year :note))
    (:phdthesis
     (:description . "A PhD thesis.")
     (:required :author :title :school :year)
     (:optional :type :address :month :note))
    (:proceedings
     (:description . "The proceedings of a conference.")
     (:required :title :year)
     (:optional :editor (:volume :number) :series :address :month :organization :publisher :note))
    (:techreport
     (:description . "A report published by a school or other institution.")
     (:required :author :title :institution :year)
     (:optional :type :address :month :note))
    (:unpublished
     (:description . "A document having an author and title, but not formally published.")
     (:required :author :title :note)
     (:optional :month :year)))
  "Bibtex entry types with required and optional parameters.")

(defvar org-bibtex-fields
  '((:address      . "Usually the address of the publisher or other type of institution. For major publishing houses, van Leunen recommends omitting the information entirely.  For small publishers, on the other hand, you can help the reader by giving the complete address.")
    (:annote       . "An annotation. It is not used by the standard bibliography styles, but may be used by others that produce an annotated bibliography.")
    (:author       . "The name(s) of the author(s), in the format described in the LaTeX book.  Remember, all names are separated with the and keyword, and not commas.")
    (:booktitle    . "Title of a book, part of which is being cited. See the LaTeX book for how to type titles. For book entries, use the title field instead.")
    (:chapter      . "A chapter (or section or whatever) number.")
    (:crossref     . "The database key of the entry being cross referenced.")
    (:edition      . "The edition of a book for example, 'Second'. This should be an ordinal, and should have the first letter capitalized, as shown here; the standard styles convert to lower case when necessary.")
    (:editor       . "Name(s) of editor(s), typed as indicated in the LaTeX book. If there is also an author field, then the editor field gives the editor of the book or collection in which the reference appears.")
    (:howpublished . "How something strange has been published. The first word should be capitalized.")
    (:institution  . "The sponsoring institution of a technical report.")
    (:journal      . "A journal name.")
    (:key          . "Used for alphabetizing, cross-referencing, and creating a label when the author information is missing. This field should not be confused with the key that appears in the \cite command and at the beginning of the database entry.")
    (:month        . "The month in which the work was published or, for an unpublished work, in which it was written. You should use the standard three-letter abbreviation,")
    (:note         . "Any additional information that can help the reader. The first word should be capitalized.")
    (:number       . "Any additional information that can help the reader. The first word should be capitalized.")
    (:organization . "The organization that sponsors a conference or that publishes a manual.")
    (:pages        . "One or more page numbers or range of numbers, such as 42-111 or 7,41,73-97 or 43+ (the ‘+’ in this last example indicates pages following that don’t form simple range). BibTEX requires double dashes for page ranges (--).")
    (:publisher    . "The publisher’s name.")
    (:school       . "The name of the school where a thesis was written.")
    (:series       . "The name of a series or set of books. When citing an entire book, the the title field gives its title and an optional series field gives the name of a series or multi-volume set in which the book is published.")
    (:title        . "The work’s title, typed as explained in the LaTeX book.")
    (:type         . "The type of a technical report for example, 'Research Note'.")
    (:volume       . "The volume of a journal or multi-volume book.")
    (:year         . "The year of publication or, for an unpublished work, the year it was written.  Generally it should consist of four numerals, such as 1984, although the standard styles can handle any year whose last four nonpunctuation characters are numerals, such as '(about 1984)'"))
  "Bibtex fields with descriptions.")

(defvar *org-bibtex-entries* nil
  "List to hold parsed bibtex entries.")

(defcustom org-bibtex-autogen-keys nil
  "Set to a truthy value to use `bibtex-generate-autokey' to generate keys."
  :group 'org-bibtex
  :type  'boolean)

(defcustom org-bibtex-prefix nil
  "Optional prefix for all bibtex property names.
For example setting to 'BIB_' would allow interoperability with fireforg."
  :group 'org-bibtex
  :type  'string)


;;; Utility functions
(defun org-bibtex-get (property)
  (or (org-entry-get (point) (upcase property))
      (org-entry-get (point) (concat org-bibtex-prefix (upcase property)))))

(defun org-bibtex-put (property value)
  (let ((prop (upcase (if (keywordp property)
                          (substring (symbol-name property) 1)
                        property))))
    (org-set-property
     (concat (unless (string= "CUSTOM_ID" prop) org-bibtex-prefix) prop)
     value)))

(defun org-bibtex-headline ()
  "Return a bibtex entry of the given headline as a string."
  (flet ((get (key lst) (cdr (assoc key lst)))
         (to-k (string) (intern (concat ":" string)))
         (from-k (key) (substring (symbol-name key) 1))
         (flatten (&rest lsts)
                  (apply #'append (mapcar
                                   (lambda (e)
                                     (if (listp e) (apply #'flatten e) (list e)))
                                   lsts))))
    (let ((notes (buffer-string))
          (id (org-bibtex-get "custom_id"))
          (type (org-bibtex-get "type")))
      (when type
        (let ((entry (format
                      "@%s{%s,\n%s\n}\n" type id
                      (mapconcat
                       (lambda (pair) (format "  %s={%s}" (car pair) (cdr pair)))
                       (remove nil
			 (mapcar
			  (lambda (field)
			    (let ((value (or (org-bibtex-get (from-k field))
					     (and (equal :title field)
						  (org-get-heading)))))
			      (when value (cons (from-k field) value))))
			  (flatten
			   (get :required (get (to-k type) org-bibtex-types))
			   (get :optional (get (to-k type) org-bibtex-types)))))
                       ",\n"))))
          (with-temp-buffer
            (insert entry)
            (bibtex-reformat) (buffer-string)))))))

(defun org-bibtex-ask (field)
  (unless (assoc field org-bibtex-fields)
    (error "field:%s is not known" field))
  (save-window-excursion
    (let* ((name (substring (symbol-name field) 1))
	   (buf-name (format "*Bibtex Help %s*" name)))
      (with-output-to-temp-buffer buf-name
	(princ (cdr (assoc field org-bibtex-fields))))
      (with-current-buffer buf-name (longlines-mode t))
      (org-fit-window-to-buffer (get-buffer-window buf-name))
      ((lambda (result) (when (> (length result) 0) result))
       (read-from-minibuffer (format "%s: " name))))))

(defun org-bibtex-autokey ()
  "Generate an autokey for the current headline"
  (org-bibtex-put "CUSTOM_ID"
                  (if org-bibtex-autogen-keys
                      (let ((entry (org-bibtex-headline)))
                        (with-temp-buffer
                          (insert entry)
                          (bibtex-generate-autokey)))
                    (read-from-minibuffer "id: "))))

(defun org-bibtex-fleshout (type &optional optional)
  "Fleshout the current heading, ensuring that all required fields are present.
With optional argument OPTIONAL, also prompt for optional fields."
  (flet ((get (key lst) (cdr (assoc key lst)))
	 (keyword (name) (intern (concat ":" (downcase name))))
         (name (keyword) (upcase (substring (symbol-name keyword) 1))))
    (dolist (field (append
		    (remove :title (get :required (get type org-bibtex-types)))
		    (when optional (get :optional (get type org-bibtex-types)))))
      (when (consp field) ; or'd pair of fields e.g., (:editor :author)
        (let ((present (first (remove nil
                                (mapcar
                                 (lambda (f) (when (org-bibtex-get (name f)) f))
                                 field)))))
          (setf field (or present (keyword (org-icompleting-read
					    "Field: " (mapcar #'name field)))))))
      (let ((name (name field)))
        (unless (org-bibtex-get name)
          (let ((prop (org-bibtex-ask field)))
            (when prop (org-bibtex-put name prop)))))))
  (when (and type (assoc type org-bibtex-types)
             (not (org-bibtex-get "CUSTOM_ID")))
    (org-bibtex-autokey)))


;;; Bibtex link functions
(org-add-link-type "bibtex" 'org-bibtex-open)
(add-hook 'org-store-link-functions 'org-bibtex-store-link)

(defun org-bibtex-open (path)
  "Visit the bibliography entry on PATH."
  (let* ((search (when (string-match "::\\(.+\\)\\'" path)
		   (match-string 1 path)))
	 (path (substring path 0 (match-beginning 0))))
    (org-open-file path t nil search)))

(defun org-bibtex-store-link ()
  "Store a link to a BibTeX entry."
  (when (eq major-mode 'bibtex-mode)
    (let* ((search (org-create-file-search-in-bibtex))
	   (link (concat "file:" (abbreviate-file-name buffer-file-name)
			 "::" search))
	   (entry (mapcar ; repair strings enclosed in "..." or {...}
		   (lambda(c)
		     (if (string-match
			  "^\\(?:{\\|\"\\)\\(.*\\)\\(?:}\\|\"\\)$" (cdr c))
			 (cons (car c) (match-string 1 (cdr c))) c))
		   (save-excursion
		     (bibtex-beginning-of-entry)
		     (bibtex-parse-entry)))))
      (org-store-link-props
       :key (cdr (assoc "=key=" entry))
       :author (or (cdr (assoc "author" entry)) "[no author]")
       :editor (or (cdr (assoc "editor" entry)) "[no editor]")
       :title (or (cdr (assoc "title" entry)) "[no title]")
       :booktitle (or (cdr (assoc "booktitle" entry)) "[no booktitle]")
       :journal (or (cdr (assoc "journal" entry)) "[no journal]")
       :publisher (or (cdr (assoc "publisher" entry)) "[no publisher]")
       :pages (or (cdr (assoc "pages" entry)) "[no pages]")
       :url (or (cdr (assoc "url" entry)) "[no url]")
       :year (or (cdr (assoc "year" entry)) "[no year]")
       :month (or (cdr (assoc "month" entry)) "[no month]")
       :address (or (cdr (assoc "address" entry)) "[no address]")
       :volume (or (cdr (assoc "volume" entry)) "[no volume]")
       :number (or (cdr (assoc "number" entry)) "[no number]")
       :annote (or (cdr (assoc "annote" entry)) "[no annotation]")
       :series (or (cdr (assoc "series" entry)) "[no series]")
       :abstract (or (cdr (assoc "abstract" entry)) "[no abstract]")
       :btype (or (cdr (assoc "=type=" entry)) "[no type]")
       :type "bibtex"
       :link link
       :description description))))

(defun org-create-file-search-in-bibtex ()
  "Create the search string and description for a BibTeX database entry."
  ;; Make a good description for this entry, using names, year and the title
  ;; Put it into the `description' variable which is dynamically scoped.
  (let ((bibtex-autokey-names 1)
	(bibtex-autokey-names-stretch 1)
	(bibtex-autokey-name-case-convert-function 'identity)
	(bibtex-autokey-name-separator " & ")
	(bibtex-autokey-additional-names " et al.")
	(bibtex-autokey-year-length 4)
	(bibtex-autokey-name-year-separator " ")
	(bibtex-autokey-titlewords 3)
	(bibtex-autokey-titleword-separator " ")
	(bibtex-autokey-titleword-case-convert-function 'identity)
	(bibtex-autokey-titleword-length 'infty)
	(bibtex-autokey-year-title-separator ": "))
    (setq description (bibtex-generate-autokey)))
  ;; Now parse the entry, get the key and return it.
  (save-excursion
    (bibtex-beginning-of-entry)
    (cdr (assoc "=key=" (bibtex-parse-entry)))))

(defun org-execute-file-search-in-bibtex (s)
  "Find the link search string S as a key for a database entry."
  (when (eq major-mode 'bibtex-mode)
    ;; Yes, we want to do the search in this file.
    ;; We construct a regexp that searches for "@entrytype{" followed by the key
    (goto-char (point-min))
    (and (re-search-forward (concat "@[a-zA-Z]+[ \t\n]*{[ \t\n]*"
				    (regexp-quote s) "[ \t\n]*,") nil t)
	 (goto-char (match-beginning 0)))
    (if (and (match-beginning 0) (equal current-prefix-arg '(16)))
	;; Use double prefix to indicate that any web link should be browsed
	(let ((b (current-buffer)) (p (point)))
	  ;; Restore the window configuration because we just use the web link
	  (set-window-configuration org-window-config-before-follow-link)
	  (with-current-buffer b
	    (goto-char p)
	    (bibtex-url)))
      (recenter 0))  ; Move entry start to beginning of window
    ;; return t to indicate that the search is done.
    t))

;; Finally add the link search function to the right hook.
(add-hook 'org-execute-file-search-functions 'org-execute-file-search-in-bibtex)


;;; Bibtex <-> Org-mode headline translation functions
(defun org-bibtex ()
  "Export each headline in the current file to a bibtex entry.
Headlines are exported using `org-bibtex-export-headline'."
  (interactive)
  (let ((bibtex-entries (remove nil (org-map-entries #'org-bibtex-headline))))
    (with-temp-file (concat (file-name-sans-extension (buffer-file-name)) ".bib")
      (insert (mapconcat #'identity bibtex-entries "\n")))))

(defun org-bibtex-check (&optional optional)
  "Check the current headline for required fields.
With prefix argument OPTIONAL also prompt for optional fields."
  (interactive "P")
  (save-restriction
    (org-narrow-to-subtree)
    (let ((type ((lambda (name) (when name (intern (concat ":" name))))
                 (org-bibtex-get "TYPE"))))
      (when type (org-bibtex-fleshout type optional)))))

(defun org-bibtex-check-all (&optional optional)
  "Check all headlines in the current file.
With prefix argument OPTIONAL also prompt for optional fields."
  (interactive) (org-map-entries (lambda () (org-bibtex-check optional))))

(defun org-bibtex-create (type)
  "Create a new entry at the given level."
  (interactive
   (list (org-icompleting-read
          "Type: "
	  (mapcar (lambda (type) (symbol-name (car type))) org-bibtex-types))))
  (let ((type (if (keywordp type) type (intern type))))
    (unless (assoc type org-bibtex-types)
      (error "type:%s is not known" type))
    (org-insert-heading)
    (let ((title (org-bibtex-ask :title)))
      (insert title) (org-bibtex-put "TITLE" title))
    (org-bibtex-put "TYPE" (substring (symbol-name type) 1))
    (org-bibtex-fleshout type)))

(defun org-bibtex-read ()
  "Read a bibtex entry and save to `*org-bibtex-entries*'.
This uses `bibtex-parse-entry'."
  (interactive)
  (flet ((keyword (str) (intern (concat ":" (downcase str))))
         (clean-space (str) (replace-regexp-in-string
                             "[[:space:]\n\r]+" " " str))
         (strip-delim (str)	     ; strip enclosing "..." and {...}
		      (dolist (pair '((34 . 34) (123 . 125) (123 . 125)))
			(when (and (= (aref str 0) (car pair))
				   (= (aref str (1- (length str))) (cdr pair)))
			  (setf str (subseq str 1 (1- (length str)))))) str))
    (push (mapcar
           (lambda (pair)
             (cons (let ((field (keyword (car pair))))
                     (case field
                       (:=type= :type)
                       (:=key= :key)
                       (otherwise field)))
                   (clean-space (strip-delim (cdr pair)))))
           (save-excursion (bibtex-beginning-of-entry) (bibtex-parse-entry)))
          *org-bibtex-entries*)))

(defun org-bibtex-write ()
  "Insert a heading built from the first element of `*org-bibtex-entries*'."
  (interactive)
  (when (= (length *org-bibtex-entries*) 0)
    (error "No entries in `*org-bibtex-entries*'."))
  (let ((entry (pop *org-bibtex-entries*))
	(org-special-properties nil)) ; avoids errors with `org-entry-put'
    (flet ((get (field) (cdr (assoc field entry))))
      (org-insert-heading)
      (insert (get :title))
      (org-bibtex-put "TITLE" (get :title))
      (org-bibtex-put "TYPE"  (downcase (get :type)))
      (dolist (pair entry)
        (case (car pair)
          (:title    nil)
          (:type     nil)
          (:key      (org-bibtex-put "CUSTOM_ID" (cdr pair)))
          (otherwise (org-bibtex-put (car pair)  (cdr pair))))))))

(defun org-bibtex-yank ()
  "If kill ring holds a bibtex entry yank it as an Org-mode headline."
  (interactive)
  (let (entry)
    (with-temp-buffer (yank 1) (setf entry (org-bibtex-read)))
    (if entry
	(org-bibtex-write)
      (error "yanked text does not appear to contain a bibtex entry"))))

(provide 'org-bibtex)

;; arch-tag: 83987d5a-01b8-41c7-85bc-77700f1285f5

;;; org-bibtex.el ends here
