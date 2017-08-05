# private_sales
Private Real Estate sales

Purpose: Reduce cost and reliance on lawyers by automating many processes involved in a private sale of real estate, including escrow of funds. (This could apply to real estate in general, but the legal and business interests regulating public sales (i.e., through Realtors) is so entrenched and powerful, I believe it would have to start with private sales between individuals.)

Description: In most jurisdictions, private sellers are required to comply with the same disclosure and other laws as a real estate broker listing the property. A system of smart contracts could -- provably and immutably -- ensure compliance with these laws and even store the documents (e.g., using IPFS or Storj or similar service). It doesn't need to be all that fast: one characteristic of real estate transactions is they happen slowly, over days and weeks (even the closing takes hours). It's not like a POS system that has to process transactions in seconds.

The next part of the process is the bidding and negotiation. Again, sellers could choose the type of sale they wanted to have (auction, sealed bid, open bid, what policy for multiple offers, etc.), and contracts could accept bids (including escrowed hand money), and the seller could take action, for instance, accepting a certain bid, which would automatically refund the others and escrow the deposit funds.

Private sellers are still subject to fair housing regulations, just as brokers are, and a system like this, immutably recording offers, could eliminate disputes about who offered what and when, and why someone was denied. The contract rules treat every buyer the same, and don't know about age, ethnicity, gender, etc. It would be hard to argue that a contract was racist!

HUD and auction sites already do something very like this, albeit not on the blockchain, and not with real money. Using Oracles or Slock.it services, it would even be possible to vet buyers in some ways (e.g., checking credit).

The rest of the process could also be mediated through contracts, right up to (and possibly eventually including) the closing itself. For instance, the buyer could call a contract method to specify a home inspector and a radon inspector, who would have known public addresses (ENS would be helpful here). The contract would then accept reports from those addresses. The time periods could all be encoded into the contract so that, for instance, the buyer could call "terminateContract()," which would succeed inside the inspection time period (and release the escrow back to the buyer). After the inspection period, the call would fail.

The lender could also have a public address, and could send a transaction from that known address clearing the loan approval conditions. At closing, the title company could send a transaction saying all the documents were signed and the money disbursed, which would release the escrowed hand money to the title company. All these legal entities would still do their thing (conventional paper processes with legal backing), but at the end, they'd send the contract notification that all the "human/legal stuff" was done, and the transaction would move to a new state.

This would eliminate disputes about timing (I once almost lost $5,000 because I hand delivered a contract termination which they claimed they never received!), and the transaction data could always contain a hash of the actual document (and maybe a key to retrieve it from IPFS or Storj), so there could be no lost documents or disputes about what was signed when by whom. This could cut down on litigation considerably.

Note: I'm a Realtor with 15 years experience, very familiar with the industry and its challenges. I'm also thinking about a system based on the Quorum project (or maybe Hyperledger) for coordinating the various parties needed for a conventional real estate closing. Automation could reduce costs and errors (replacing reconciliation across multiple independent databases with consensus).