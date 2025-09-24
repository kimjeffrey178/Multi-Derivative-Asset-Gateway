(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_OWNER_ONLY (err u100))
(define-constant ERR_NOT_AUTHORIZED (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_INSUFFICIENT_BALANCE (err u103))
(define-constant ERR_DEPOSIT_NOT_FOUND (err u104))
(define-constant ERR_ALREADY_MINTED (err u105))
(define-constant ERR_INVALID_ADDRESS (err u106))
(define-constant ERR_TOKEN_NOT_FOUND (err u107))
(define-constant ERR_PAUSED (err u108))

(define-data-var contract-paused bool false)
(define-data-var next-deposit-id uint u1)

(define-map deposits
  { deposit-id: uint }
  {
    eth-address: (buff 20),
    stx-recipient: principal,
    token-contract: (buff 20),
    amount: uint,
    block-height: uint,
    tx-hash: (buff 32),
    is-minted: bool,
    mint-tx-id: (optional uint)
  }
)

(define-map ethereum-deposits
  { tx-hash: (buff 32), token-contract: (buff 20) }
  { deposit-id: uint }
)

(define-map user-balances
  { user: principal, token-contract: (buff 20) }
  { balance: uint }
)

(define-map token-info
  { token-contract: (buff 20) }
  {
    name: (string-ascii 32),
    symbol: (string-ascii 10),
    decimals: uint,
    total-supply: uint,
    is-active: bool
  }
)

(define-map authorized-oracles principal bool)

(define-public (register-token (token-contract (buff 20)) (name (string-ascii 32)) (symbol (string-ascii 10)) (decimals uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (map-set token-info
      { token-contract: token-contract }
      {
        name: name,
        symbol: symbol,
        decimals: decimals,
        total-supply: u0,
        is-active: true
      }
    ))
  )
)

(define-public (add-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (map-set authorized-oracles oracle true))
  )
)

(define-public (remove-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (map-delete authorized-oracles oracle))
  )
)

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (var-set contract-paused true))
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_OWNER_ONLY)
    (ok (var-set contract-paused false))
  )
)

(define-public (record-deposit 
  (eth-address (buff 20))
  (stx-recipient principal)
  (token-contract (buff 20))
  (amount uint)
  (block-height uint)
  (tx-hash (buff 32))
)
  (let (
    (deposit-id (var-get next-deposit-id))
    (oracle-authorized (default-to false (map-get? authorized-oracles tx-sender)))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) oracle-authorized) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? ethereum-deposits { tx-hash: tx-hash, token-contract: token-contract })) ERR_ALREADY_MINTED)
    
    (map-set deposits
      { deposit-id: deposit-id }
      {
        eth-address: eth-address,
        stx-recipient: stx-recipient,
        token-contract: token-contract,
        amount: amount,
        block-height: block-height,
        tx-hash: tx-hash,
        is-minted: false,
        mint-tx-id: none
      }
    )
    
    (map-set ethereum-deposits
      { tx-hash: tx-hash, token-contract: token-contract }
      { deposit-id: deposit-id }
    )
    
    (var-set next-deposit-id (+ deposit-id u1))
    (ok deposit-id)
  )
)

(define-public (mint-derivative-token (deposit-id uint))
  (let (
    (deposit-info (unwrap! (map-get? deposits { deposit-id: deposit-id }) ERR_DEPOSIT_NOT_FOUND))
    (token-contract (get token-contract deposit-info))
    (amount (get amount deposit-info))
    (recipient (get stx-recipient deposit-info))
    (current-balance (default-to u0 (get balance (map-get? user-balances { user: recipient, token-contract: token-contract }))))
    (token-data (unwrap! (map-get? token-info { token-contract: token-contract }) ERR_TOKEN_NOT_FOUND))
    (oracle-authorized (default-to false (map-get? authorized-oracles tx-sender)))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (or (is-eq tx-sender CONTRACT_OWNER) oracle-authorized) ERR_NOT_AUTHORIZED)
    (asserts! (not (get is-minted deposit-info)) ERR_ALREADY_MINTED)
    (asserts! (get is-active token-data) ERR_TOKEN_NOT_FOUND)
    
    (map-set user-balances
      { user: recipient, token-contract: token-contract }
      { balance: (+ current-balance amount) }
    )
    
    (map-set deposits
      { deposit-id: deposit-id }
      (merge deposit-info { is-minted: true, mint-tx-id: (some block-height) })
    )
    
    (map-set token-info
      { token-contract: token-contract }
      (merge token-data { total-supply: (+ (get total-supply token-data) amount) })
    )
    
    (print { 
      action: "mint",
      deposit-id: deposit-id,
      recipient: recipient,
      token-contract: token-contract,
      amount: amount
    })
    
    (ok true)
  )
)

(define-public (burn-derivative-token (token-contract (buff 20)) (amount uint) (eth-recipient (buff 20)))
  (let (
    (user-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender, token-contract: token-contract }))))
    (token-data (unwrap! (map-get? token-info { token-contract: token-contract }) ERR_TOKEN_NOT_FOUND))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= user-balance amount) ERR_INSUFFICIENT_BALANCE)
    (asserts! (get is-active token-data) ERR_TOKEN_NOT_FOUND)
    
    (map-set user-balances
      { user: tx-sender, token-contract: token-contract }
      { balance: (- user-balance amount) }
    )
    
    (map-set token-info
      { token-contract: token-contract }
      (merge token-data { total-supply: (- (get total-supply token-data) amount) })
    )
    
    (print { 
      action: "burn",
      user: tx-sender,
      token-contract: token-contract,
      amount: amount,
      eth-recipient: eth-recipient,
      burn-block: block-height
    })
    
    (ok true)
  )
)

(define-public (transfer (to principal) (token-contract (buff 20)) (amount uint))
  (let (
    (sender-balance (default-to u0 (get balance (map-get? user-balances { user: tx-sender, token-contract: token-contract }))))
    (recipient-balance (default-to u0 (get balance (map-get? user-balances { user: to, token-contract: token-contract }))))
  )
    (asserts! (not (var-get contract-paused)) ERR_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
    
    (map-set user-balances
      { user: tx-sender, token-contract: token-contract }
      { balance: (- sender-balance amount) }
    )
    
    (map-set user-balances
      { user: to, token-contract: token-contract }
      { balance: (+ recipient-balance amount) }
    )
    
    (print { 
      action: "transfer",
      from: tx-sender,
      to: to,
      token-contract: token-contract,
      amount: amount
    })
    
    (ok true)
  )
)

(define-read-only (get-balance (user principal) (token-contract (buff 20)))
  (default-to u0 (get balance (map-get? user-balances { user: user, token-contract: token-contract })))
)

(define-read-only (get-deposit-info (deposit-id uint))
  (map-get? deposits { deposit-id: deposit-id })
)

(define-read-only (get-deposit-by-tx (tx-hash (buff 32)) (token-contract (buff 20)))
  (let (
    (deposit-lookup (map-get? ethereum-deposits { tx-hash: tx-hash, token-contract: token-contract }))
  )
    (match deposit-lookup
      lookup-data (map-get? deposits { deposit-id: (get deposit-id lookup-data) })
      none
    )
  )
)

(define-read-only (get-token-info (token-contract (buff 20)))
  (map-get? token-info { token-contract: token-contract })
)

(define-read-only (is-oracle-authorized (oracle principal))
  (default-to false (map-get? authorized-oracles oracle))
)

(define-read-only (get-contract-info)
  {
    owner: CONTRACT_OWNER,
    paused: (var-get contract-paused),
    next-deposit-id: (var-get next-deposit-id)
  }
)