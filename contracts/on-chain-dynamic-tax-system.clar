(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-ENOUGH-BALANCE (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-INVALID-RECIPIENT (err u103))
(define-constant ERR-INSUFFICIENT-TAX (err u104))
(define-constant ERR-ALREADY-EXEMPTED (err u105))
(define-constant ERR-NOT-EXEMPTED (err u106))
(define-constant ERR-INVALID-HOLIDAY-PERIOD (err u107))
(define-constant ERR-HOLIDAY-ALREADY-ACTIVE (err u108))

(define-fungible-token dynamic-token)

(define-data-var token-name (string-ascii 32) "DynamicTax")
(define-data-var token-symbol (string-ascii 10) "DTAX")
(define-data-var token-decimals uint u6)
(define-data-var base-tax-rate uint u100)
(define-data-var max-tax-rate uint u1000)
(define-data-var volume-threshold uint u1000000)
(define-data-var tax-adjustment-factor uint u50)
(define-data-var treasury principal CONTRACT-OWNER)
(define-data-var current-block-volume uint u0)
(define-data-var last-volume-reset-block uint u0)
(define-data-var total-tax-collected uint u0)
(define-data-var volume-reset-interval uint u144)
(define-data-var tax-holiday-active bool false)
(define-data-var tax-holiday-start uint u0)
(define-data-var tax-holiday-end uint u0)
(define-data-var tax-holiday-discount uint u0)

(define-map user-balances principal uint)
(define-map transaction-history uint {sender: principal, recipient: principal, amount: uint, tax-paid: uint, block-height: uint})
(define-map daily-volume uint uint)
(define-map tax-exemptions principal bool)



(define-read-only (get-token-name)
  (ok (var-get token-name)))

(define-read-only (get-token-symbol)
  (ok (var-get token-symbol)))

(define-read-only (get-decimals)
  (ok (var-get token-decimals)))

(define-read-only (get-balance (account principal))
  (ok (ft-get-balance dynamic-token account)))

(define-read-only (get-total-supply)
  (ok (ft-get-supply dynamic-token)))

(define-read-only (get-current-tax-rate)
  (let ((current-volume (var-get current-block-volume))
        (threshold (var-get volume-threshold))
        (base-rate (var-get base-tax-rate))
        (max-rate (var-get max-tax-rate))
        (adjustment (var-get tax-adjustment-factor)))
    (if (> current-volume threshold)
      (let ((volume-multiplier (/ (* current-volume adjustment) threshold)))
        (if (> (+ base-rate volume-multiplier) max-rate)
          (ok max-rate)
          (ok (+ base-rate volume-multiplier))))
      (ok base-rate))))

(define-read-only (get-treasury)
  (ok (var-get treasury)))

(define-read-only (get-total-tax-collected)
  (ok (var-get total-tax-collected)))

(define-read-only (get-current-volume)
  (ok (var-get current-block-volume)))

(define-read-only (is-tax-exempt (address principal))
  (default-to false (map-get? tax-exemptions address)))

(define-read-only (is-tax-holiday-active)
  (let ((current-block burn-block-height)
        (start (var-get tax-holiday-start))
        (end (var-get tax-holiday-end))
        (active (var-get tax-holiday-active)))
    (and active (>= current-block start) (<= current-block end))))

(define-read-only (get-tax-holiday-info)
  (ok {
    active: (var-get tax-holiday-active),
    start: (var-get tax-holiday-start),
    end: (var-get tax-holiday-end),
    discount: (var-get tax-holiday-discount),
    currently-active: (is-tax-holiday-active)
  }))

(define-read-only (calculate-tax (amount uint))
  (let ((tax-rate (unwrap-panic (get-current-tax-rate))))
    (ok (/ (* amount tax-rate) u10000))))

(define-read-only (calculate-tax-for-user (amount uint) (user principal))
  (if (is-tax-exempt user)
    (ok u0)
    (let ((base-tax (unwrap-panic (calculate-tax amount))))
      (if (is-tax-holiday-active)
        (let ((discount (var-get tax-holiday-discount)))
          (ok (/ (* base-tax (- u10000 discount)) u10000)))
        (ok base-tax)))))

(define-private (should-reset-volume)
  (let ((current-block burn-block-height)
        (last-reset (var-get last-volume-reset-block))
        (interval (var-get volume-reset-interval)))
    (>= (- current-block last-reset) interval)))

(define-private (maybe-reset-volume)
  (if (should-reset-volume)
    (begin
      (var-set current-block-volume u0)
      (var-set last-volume-reset-block burn-block-height)
      true)
    false))

(define-private (update-volume (amount uint))
  (let ((current-volume (var-get current-block-volume)))
    (var-set current-block-volume (+ current-volume amount))))

(define-private (collect-tax (tax-amount uint))
  (let ((treasury-addr (var-get treasury))
        (current-collected (var-get total-tax-collected)))
    (begin
      (try! (ft-mint? dynamic-token tax-amount treasury-addr))
      (var-set total-tax-collected (+ current-collected tax-amount))
      (ok true))))

(define-public (mint (amount uint) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (ft-mint? dynamic-token amount recipient))
    (ok true)))

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (begin
    (asserts! (is-eq tx-sender sender) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (is-eq sender recipient)) ERR-INVALID-RECIPIENT)
    
    (maybe-reset-volume)
    
    (let ((tax-amount (unwrap-panic (calculate-tax-for-user amount sender))))
      (let ((total-deduction (+ amount tax-amount)))
        (asserts! (>= (ft-get-balance dynamic-token sender) total-deduction) ERR-NOT-ENOUGH-BALANCE)
        (try! (ft-transfer? dynamic-token amount sender recipient))
        (if (> tax-amount u0)
          (try! (ft-transfer? dynamic-token tax-amount sender (var-get treasury)))
          true)
        (update-volume amount)
        (var-set total-tax-collected (+ (var-get total-tax-collected) tax-amount))
        (ok true)))))

(define-public (transfer-with-tax (amount uint) (recipient principal))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (is-eq tx-sender recipient)) ERR-INVALID-RECIPIENT)
    
    (maybe-reset-volume)
    
    (let ((tax-amount (unwrap-panic (calculate-tax-for-user amount tx-sender))))
      (let ((total-deduction (+ amount tax-amount)))
        (asserts! (>= (ft-get-balance dynamic-token tx-sender) total-deduction) ERR-NOT-ENOUGH-BALANCE)
        (try! (ft-transfer? dynamic-token amount tx-sender recipient))
        (if (> tax-amount u0)
          (try! (collect-tax tax-amount))
          true)
        (update-volume amount)
        (ok {amount: amount, tax-paid: tax-amount})))))

(define-public (burn (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (ft-burn? dynamic-token amount tx-sender))
    (ok true)))

(define-public (set-base-tax-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= new-rate (var-get max-tax-rate)) ERR-INVALID-AMOUNT)
    (var-set base-tax-rate new-rate)
    (ok true)))

(define-public (set-max-tax-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (>= new-rate (var-get base-tax-rate)) ERR-INVALID-AMOUNT)
    (var-set max-tax-rate new-rate)
    (ok true)))

(define-public (set-volume-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> new-threshold u0) ERR-INVALID-AMOUNT)
    (var-set volume-threshold new-threshold)
    (ok true)))

(define-public (set-tax-adjustment-factor (new-factor uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set tax-adjustment-factor new-factor)
    (ok true)))

(define-public (set-treasury (new-treasury principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set treasury new-treasury)
    (ok true)))

(define-public (set-volume-reset-interval (new-interval uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> new-interval u0) ERR-INVALID-AMOUNT)
    (var-set volume-reset-interval new-interval)
    (ok true)))

(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set max-tax-rate u10000)
    (ok true)))

(define-public (withdraw-treasury (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (try! (ft-transfer? dynamic-token amount (var-get treasury) tx-sender))
    (ok true)))

(define-public (grant-tax-exemption (address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (not (is-tax-exempt address)) ERR-ALREADY-EXEMPTED)
    (map-set tax-exemptions address true)
    (ok true)))

(define-public (revoke-tax-exemption (address principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (is-tax-exempt address) ERR-NOT-EXEMPTED)
    (map-delete tax-exemptions address)
    (ok true)))

(define-private (grant-exemption (addr principal))
  (begin
    (if (is-tax-exempt addr)
      true
      (map-set tax-exemptions addr true))
    true))

(define-private (revoke-exemption (addr principal))
  (begin
    (if (is-tax-exempt addr)
      (map-delete tax-exemptions addr)
      true)
    true))

(define-public (grant-tax-exemptions-batch (addresses (list 200 principal)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (map grant-exemption addresses)
    (ok true)))

(define-public (revoke-tax-exemptions-batch (addresses (list 200 principal)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (map revoke-exemption addresses)
    (ok true)))

(define-public (activate-tax-holiday (start-block uint) (end-block uint) (discount-percent uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (not (var-get tax-holiday-active)) ERR-HOLIDAY-ALREADY-ACTIVE)
    (asserts! (> end-block start-block) ERR-INVALID-HOLIDAY-PERIOD)
    (asserts! (<= discount-percent u10000) ERR-INVALID-AMOUNT)
    (var-set tax-holiday-active true)
    (var-set tax-holiday-start start-block)
    (var-set tax-holiday-end end-block)
    (var-set tax-holiday-discount discount-percent)
    (ok true)))

(define-public (deactivate-tax-holiday)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (var-set tax-holiday-active false)
    (var-set tax-holiday-start u0)
    (var-set tax-holiday-end u0)
    (var-set tax-holiday-discount u0)
    (ok true)))

(define-public (extend-tax-holiday (new-end-block uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (var-get tax-holiday-active) ERR-INVALID-HOLIDAY-PERIOD)
    (asserts! (> new-end-block (var-get tax-holiday-end)) ERR-INVALID-HOLIDAY-PERIOD)
    (var-set tax-holiday-end new-end-block)
    (ok true)))

(begin
  (try! (ft-mint? dynamic-token u1000000000000 CONTRACT-OWNER))
  (var-set last-volume-reset-block burn-block-height))
 
 (define-read-only (quote-transfer (amount uint) (sender principal) (recipient principal))
   (let (
         (sender-match (is-eq tx-sender sender))
         (amount-positive (> amount u0))
         (recipient-different (not (is-eq sender recipient)))
         (tax-amount (unwrap-panic (calculate-tax-for-user amount sender)))
         (total (+ amount tax-amount))
         (balance (ft-get-balance dynamic-token sender))
         (sufficient (>= balance total)))
     (ok {
       sender-match: sender-match,
       valid-amount: amount-positive,
       valid-recipient: recipient-different,
       sufficient-balance: sufficient,
       amount: amount,
       tax: tax-amount,
       total-deduction: total,
       recipient-credit: amount
     })))

 (define-private (accumulate-batch (entry {amount: uint, recipient: principal}) (acc {sender: principal, total-amount: uint, total-tax: uint, total-deduction: uint, any-invalid: bool, initial-balance: uint}))
   (let (
         (entry-amount (get amount entry))
         (entry-recipient (get recipient entry))
         (acc-sender (get sender acc))
         (amount-positive (> entry-amount u0))
         (recipient-different (not (is-eq entry-recipient acc-sender)))
         (tax-amount (unwrap-panic (calculate-tax-for-user entry-amount acc-sender)))
         (new-total-amount (+ (get total-amount acc) entry-amount))
         (new-total-tax (+ (get total-tax acc) tax-amount))
         (new-total-deduction (+ (get total-deduction acc) (+ entry-amount tax-amount)))
         (invalid (or (not amount-positive) (not recipient-different)))
       )
     {
       sender: acc-sender,
       total-amount: new-total-amount,
       total-tax: new-total-tax,
       total-deduction: new-total-deduction,
       any-invalid: (or (get any-invalid acc) invalid),
       initial-balance: (get initial-balance acc)
     }))

 (define-read-only (quote-batch-transfer (entries (list 200 {amount: uint, recipient: principal})) (sender principal))
   (let (
         (initial-balance (ft-get-balance dynamic-token sender))
         (initial-acc {
           sender: sender,
           total-amount: u0,
           total-tax: u0,
           total-deduction: u0,
           any-invalid: false,
           initial-balance: initial-balance
         })
         (acc (fold accumulate-batch entries initial-acc))
         (sufficient (>= (get initial-balance acc) (get total-deduction acc)))
       )
     (ok {
       sender-match: (is-eq tx-sender sender),
       all-valid: (not (get any-invalid acc)),
       sufficient-balance: sufficient,
       total-amount: (get total-amount acc),
       total-tax: (get total-tax acc),
       total-deduction: (get total-deduction acc),
       initial-balance: (get initial-balance acc)
     })))
