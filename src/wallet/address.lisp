;;;; This file is part of monero-tools
;;;; Copyright 2016-2017 Guillaume LE VAILLANT
;;;; Distributed under the GNU GPL v3 or later.
;;;; See the file LICENSE for terms of use and distribution.


(in-package :monero-tools)


(defconstant +address-base58-prefix+ 18)
(defconstant +integrated-address-base58-prefix+ 19)
(defconstant +subaddress-base58-prefix+ 42)
(defconstant +testnet-address-base58-prefix+ 53)
(defconstant +testnet-integrated-address-base58-prefix+ 54)
(defconstant +testnet-subaddress-base58-prefix+ 63)

(defun encode-address (public-spend-key public-view-key &key payment-id subaddress testnet)
  "Return the base58 encoded Monero address matching the
PUBLIC-SPEND-KEY and PUBLIC-VIEW-KEY. If a PAYMENT-ID is supplied, an
integrated address is returned. If SUBADDRESS is T, a subaddress is
returned. If TESTNET is T, a testnet address is returned."
  (when (and payment-id subaddress)
    (error "Integrated subaddress not supported."))
  (macrolet ((concat (&rest sequences)
               `(concatenate 'octet-vector ,@sequences)))
    (let* ((tag (vector (if testnet
                            (cond (subaddress +testnet-subaddress-base58-prefix+)
                                  (payment-id +testnet-integrated-address-base58-prefix+)
                                  (t +testnet-address-base58-prefix+))
                            (cond (subaddress +subaddress-base58-prefix+)
                                  (payment-id +integrated-address-base58-prefix+)
                                  (t +address-base58-prefix+)))))
           (data (concat tag public-spend-key public-view-key payment-id))
           (hash (subseq (fast-hash data) 0 +base58-checksum-size+)))
      (base58-encode (concat data hash)))))

(defun decode-address (address)
  "Return an alist containing the components of a Monero ADDRESS."
  (let* ((data (base58-decode address))
         (size (length data))
         (tag (aref data 0))
         (testnet (or (= tag +testnet-address-base58-prefix+)
                      (= tag +testnet-integrated-address-base58-prefix+)
                      (= tag +testnet-subaddress-base58-prefix+)))
         (integrated-address (or (= tag +integrated-address-base58-prefix+)
                                 (= tag +testnet-integrated-address-base58-prefix+)))
         (subaddress (or (= tag +subaddress-base58-prefix+)
                         (= tag +testnet-subaddress-base58-prefix+)))
         (public-spend-key (subseq data 1 33))
         (public-view-key (subseq data 33 65))
         (payment-id (when integrated-address
                       (subseq data 65 (- size +base58-checksum-size+))))
         (hash (subseq data (- size +base58-checksum-size+) size)))
    (let* ((data (subseq data 0 (- size +base58-checksum-size+)))
           (computed-hash (subseq (fast-hash data) 0 +base58-checksum-size+)))
      (unless (equalp hash computed-hash)
        (error "Bad checksum.")))
    (append (list (cons :public-spend-key public-spend-key)
                  (cons :public-view-key public-view-key))
            (when testnet
              (list (cons :testnet t)))
            (when integrated-address
              (list (cons :payment-id payment-id)))
            (when subaddress
              (list (cons :subaddress subaddress))))))

(defun public-keys->address (public-spend-key public-view-key &key subaddress testnet)
  "Get the Monero address matching the PUBLIC-SPEND-KEY and
PUBLIC-VIEW-KEY. If SUBADDRESS is T, a subaddress is returned. If
TESTNET is T, a testnet address is returned."
  (encode-address public-spend-key public-view-key :subaddress subaddress :testnet testnet))

(defun public-keys->subaddress (public-spend-key secret-view-key major-index minor-index &key testnet)
  "Get the Monero subaddress matching the PUBLIC-SPEND-KEY,
SECRET-VIEW-KEY, MAJOR-INDEX and MINOR-INDEX. If TESTNET is T,
a testnet address is returned."
  (let* ((public-spend-subkey (derive-public-spend-subkey secret-view-key
                                                          public-spend-key
                                                          major-index
                                                          minor-index))
         (public-view-subkey (public-spend-subkey->public-view-subkey secret-view-key
                                                                      public-spend-subkey)))
    (public-keys->address public-spend-subkey public-view-subkey :subaddress t :testnet testnet)))

(defun secret-spend-key->address (secret-spend-key &key testnet)
  "Get the Monero address matching the SECRET-SPEND-KEY. If TESTNET is
T, a testnet address is returned."
  (let* ((keys (recover-keys secret-spend-key))
         (public-spend-key (geta keys :public-spend-key))
         (public-view-key (geta keys :public-view-key)))
    (public-keys->address public-spend-key public-view-key :testnet testnet)))

(defun secret-spend-key->subaddress (secret-spend-key major-index minor-index &key testnet)
  "Get the Monero subaddress matching the SECRET-SPEND-KEY,
MAJOR-INDEX and MINOR-INDEX. If TESTNET is T, a testnet address is
returned."
  (let* ((keys (recover-keys secret-spend-key))
         (public-spend-key (geta keys :public-spend-key))
         (secret-view-key (geta keys :secret-view-key)))
    (public-keys->subaddress public-spend-key
                             secret-view-key
                             major-index
                             minor-index
                             :testnet testnet)))

(defun make-integrated-address (address payment-id)
  "Return an integrated address made from a Monero ADDRESS and a PAYMENT-ID."
  (let* ((address-info (decode-address address))
         (public-spend-key (geta address-info :public-spend-key))
         (public-view-key (geta address-info :public-view-key))
         (testnet (geta address-info :testnet)))
    (when (geta address-info :subaddress)
      (error "Integrated subaddress not supported."))
    (when (geta address-info :payment-id)
      (warn "~a is already an integrated address." address))
    (unless (= (length payment-id) 8)
      (error "Bad payment-id length."))
    (encode-address public-spend-key public-view-key :payment-id payment-id :testnet testnet)))
