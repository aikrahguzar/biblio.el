;;; biblio-arxiv.el --- Lookup and import bibliographic entries from arXiv -*- lexical-binding: t -*-

;; Copyright (C) 2016  Clément Pit-Claudel

;; Author: Clément Pit-Claudel
;; Version: 0.1
;; Package-Requires: ((biblio-core "0.0") (biblio-doi "0.0"))
;; Keywords: bib, tex, convenience, hypermedia
;; URL: http://github.com/cpitclaudel/biblio.el

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Lookup and download bibliographic records from arXiv using `arxiv-lookup'.
;; When a DOI is available, the metadata is fetched from the DOI's issuer;
;; otherwise, this package uses arXiv's metadata to generate an entry.
;;
;; This package uses `biblio-selection-mode', and plugs into the more general
;; `biblio' package (which see for more documentation).

;;; Code:

(require 'biblio-core)
(require 'biblio-doi)
(require 'parse-time)

(defgroup biblio-arxiv nil
  "arXiv support in biblio.el"
  :group 'biblio)

(defcustom biblio-arxiv-bibtex-header "online"
  "Which header to use for BibTeX entries generated from arXiv metadata."
  :group 'biblio
  :type 'string)

(defun biblio-arxiv--build-bibtex-1 (metadata)
  "Create an unformated BibTeX record for METADATA."
  (let-alist metadata
    (format "@%s{NO_KEY,
author = {%s},
title = {{%s}},
year = {%s},
archivePrefix = {arXiv},
eprint = {%s},
primaryClass = {%s}}"
            biblio-arxiv-bibtex-header
            (biblio-join-1 " AND " .authors)
            .title .year .identifier .category)))

(defun biblio-arxiv--build-bibtex (metadata)
  "Create a BibTeX record for METADATA."
  (let-alist metadata
    (message "Auto-generating a BibTeX entry for %S." .id)
    (biblio-format-bibtex (biblio-arxiv--build-bibtex-1 metadata) t)))

(defun biblio-arxiv--forward-bibtex (metadata forward-to)
  "Forward BibTeX for arXiv entry METADATA to FORWARD-TO."
  (let-alist metadata
    (if (seq-empty-p .doi)
        (funcall forward-to (biblio-arxiv--build-bibtex metadata))
      (biblio-doi-forward-bibtex .doi forward-to))))

(defun biblio-arxiv--format-author (author)
  "Format AUTHOR for arXiv search results."
  (when (eq (car-safe author) 'author)
    (let-alist (cdr author)
      (biblio-join " "
        (cadr .name)
        (biblio-parenthesize (cadr .arxiv:affiliation))))))

(defun biblio-arxiv--extract-id (id)
  "Extract identifier from ID, the URL of an arXiv abstract."
  (replace-regexp-in-string "http://arxiv.org/abs/" "" id))

(defconst biblio-arxiv--iso-8601-regexp
  (concat "\\`"
          "\\([0-9][0-9][0-9][0-9]\\)-\\([0-9][0-9]\\)-\\([0-9][0-9]\\)" "T"
          "\\([0-9][0-9]\\):\\([0-9][0-9]\\):\\([0-9][0-9]\\)"
          "\\(?:" "[-+]" "\\([0-9][0-9]\\):\\([0-9][0-9]\\)" "\\)?"
          "\\'"))

(defun biblio-arxiv--extract-year (date)
  "Parse an arXiv DATE and extract the year."
  (when (string-match biblio-arxiv--iso-8601-regexp date)
    (match-string 1 date)))

(defun biblio-arxiv--extract-interesting-fields (entry)
  "Prepare an arXiv search result ENTRY for display."
  (let-alist entry
    (let ((id (biblio-arxiv--extract-id (cadr .id))))
      (list (cons 'doi (cadr .arxiv:doi))
            (cons 'identifier id)
            (cons 'year (biblio-arxiv--extract-year (cadr .published)))
            (cons 'title (cadr .title))
            (cons 'authors (seq-map #'biblio-arxiv--format-author entry))
            (cons 'container (cadr .arxiv:journal_ref))
            (cons 'category
                  (biblio-alist-get 'term (car .arxiv:primary_category)))
            (cons 'references (list (cadr .arxiv:doi) id))
            (cons 'type "eprint")
            (cons 'url (biblio-alist-get 'href (car .link)))))))

(defun biblio-arxiv--entryp (entry)
  "Check if ENTRY is an arXiv entry."
  (eq (car-safe entry) 'entry))

(defun biblio-arxiv--parse-search-results ()
  "Extract search results from arXiv response."
  (let-alist (xml-parse-region (point-min) (point-max))
    (seq-map #'biblio-arxiv--extract-interesting-fields
             (seq-filter #'biblio-arxiv--entryp .feed))))

(defun biblio-arxiv--url (query)
  "Create an arXiv url to look up QUERY."
  (format "http://export.arxiv.org/api/query?search_query=%s"
          (url-encode-url query)))

(defun biblio-arxiv-backend (command &optional arg &rest more)
  "A arXiv backend for biblio.el.
COMMAND, ARG, MORE: See `biblio-backends'."
  (pcase command
    (`name "arXiv")
    (`prompt "arXiv query: ")
    (`url (biblio-arxiv--url arg))
    (`parse-buffer (biblio-arxiv--parse-search-results))
    (`forward-bibtex (biblio-arxiv--forward-bibtex arg (car more)))
    (`register (add-to-list 'biblio-backends #'biblio-arxiv-backend))))

;;;###autoload
(add-hook 'biblio-init-hook #'biblio-arxiv-backend)

;;;###autoload
(defun arxiv-lookup ()
  "Start an arXiv search."
  (interactive)
  (biblio-lookup #'biblio-arxiv-backend))

(provide 'biblio-arxiv)
;;; biblio-arxiv.el ends here
