/**
 * @title Listing
 * @dev The Listing contract represents a property for sale
 */

pragma solidity ^0.4.13;

import 'github.com/OpenZeppelin/zeppelin-solidity/contracts/lifecycle/Pausable.sol';
import 'github.com/OpenZeppelin/zeppelin-solidity/contracts/math/SafeMath.sol';
import 'github.com/pipermerriam/ethereum-uuid/contracts/UUIDProvider.sol';

/**
 * @title Listing
 * @dev The Listing contract represents a property for sale
 */
contract Listing is Pausable {
    using SafeMath for uint;
    
    // Address of contract that generates a GUID to uniquely identify the listing
    address constant GUID_PROVIDER = 0xbb17fcd3f0be84478c4772cdb1035089aa36d4d1;
    uint16 constant MINIMUM_LISTING_PERIOD_IN_DAYS = 90;
    uint256 constant OFFER_DEPOSIT_IN_WEI = 0.05 * 1 ether;
    uint256 constant OFFER_PRICE_IN_WEI = 0.01 * 1 ether;
    uint16 constant MIN_KEY_LEN = 32;
    // Failsafe to avoid locking up refunds if owner never sells
    uint constant BID_EXPIRATION_IN_DAYS = 365;
    
    enum Status { Active, Contingent, Sold, Expired, Withdrawn }
    
    /**
     * @title Offer
     * @dev Represent an offer for a property. Can only be one per buyer.
     *      Only one can be accepted
     * @param buyer - address of buyer
     * @param amountHash - dollar amount of offer (buyers can edit this by resubmitting)
     * @param encryptedTerms - terms encrypted with the seller's public key
     * @param dateSubmitted - when the buyer made the offer
     * @param dateAccepted - date the offer was accepted by the seller
     */
    struct Offer {
        address buyer;
        bytes32 amountHash;
        address mortgageCompany;
        address titleCompany;
        string encryptedTerms;
        uint dateSubmitted;
        uint dateAccepted;
        bool mortgageCommittment;
        bool titleCommittment;
    }

    // Geographic address of the property (could be a struct, but keep it simple for now)
    string public propertyAddress;
    // Current list price (can be edited by seller)
    uint256 public listPrice;
    // Final sale price (= final amount of winning offer)
    uint256 public salePrice;
    // Address of buyer who submitted the accepted offer
    address public successfulBuyer;
    // Submitting a bid after the expiration date will make the status Expired
    uint public expirationDate;
    // After this time, all buyers can withdraw their funds
    uint public refundDate;
    // Current availability status of the Listing
    Status public status;    
    // Unique identifier of this listing
    bytes16 public propertyGuid;
    // Key used to encrypt the terms
    string public sellerPublicKey;
    // Total offer fees; can be withdrawn by owner
    uint feeBalance;
    
    // Mapping to ensure unique bidders; array to support iteration
    Offer[] offers;
    mapping(address => Offer) offerMap;
    // Deposit less the price; to be withdrawn by buyers at the end
    mapping(address => uint256) refunds;
    
    // Don't disclose amount in bid events
    event LogOfferSubmitted(address indexed buyer, address indexed mortgage, address indexed title, uint date);
    event LogOfferWithdrawn(address indexed buyer, uint date);
    event LogOfferAccepted(address indexed buyer, uint date);
    event LogPropertySold(address indexed buyer, uint date, uint amount);
    event LogPropertyStatusChange(address indexed initiatedBy, Status oldStatus, Status newStatus, string reason);
    event LogPropertyRepositioned(uint newPrice, uint date);
    event LogListingExtended(uint numDays);

    // Some functions only make sense when the property is currently Active
    modifier onlyActive {
        require (status == Status.Active);
        _;
    }
    
    // Some functions only make sense when the property is already under contract
    modifier onlyContingent {
        require (status == Status.Contingent);
        _;
    }

    modifier onlyActiveOrContingent {
        require ((status == Status.Active) || (status == Status.Contingent));
        _;
    }

    /** 
     * @dev Listing constructor
     * @param _address - physical address of the property (legal description)
     * @param _price - list price of the property
     * @param listingPeriodInDays - after this, the property will expire
     */
    function Listing(string _address, string publicKey, uint256 _price, uint16 listingPeriodInDays) {
        // Identifying information cannot be blank
        require (bytes(_address).length > 0);
        require (listingPeriodInDays >= MINIMUM_LISTING_PERIOD_IN_DAYS);
        // Can't list properties for free
        require (_price > 0);
        require (bytes(publicKey).length > MIN_KEY_LEN);
        assert (OFFER_DEPOSIT_IN_WEI > OFFER_PRICE_IN_WEI);

        propertyAddress = _address;
        sellerPublicKey = publicKey;
        listPrice = _price;
        expirationDate = SafeMath.add(now, (listingPeriodInDays * 1 days));
        refundDate = SafeMath.add(now, (BID_EXPIRATION_IN_DAYS * 1 days));
        status = Status.Active;
        
        // Call the external contract to set the Guid
        var uuidProvider = UUIDProvider(GUID_PROVIDER);
        propertyGuid = uuidProvider.UUID4();
    }
    
    /**
     * @dev reposition - Owner can change the price (e.g., lower it)
     * @param newPrice - new price of the listing
     */
    function reposition(uint newPrice) onlyOwner onlyActive {
        require(newPrice > 0);
        require(newPrice != listPrice);
        
        listPrice = newPrice;
        
        LogPropertyRepositioned(newPrice, now);
    }
    
    /** 
     * @dev Must be a new offer; use updateBid to change an existing one
     *      Should eventually handle hand money
     *      If offer submitted after expiration period, expire the Listing
     * @param amountHash - has of the dollar amount of the offer and a key
     * @param terms - private terms encrypted to seller
     */
    function submitOffer(bytes32 amountHash, string terms, address mortgage, address title) payable onlyActive {
        require (offerMap[msg.sender].buyer == 0);
        // You can't bid on your own property
        require (msg.sender != owner);
        // You can't bid nothing (or have a 0 hash)
        require (amountHash > 0);
        require (msg.value >= OFFER_DEPOSIT_IN_WEI);
        require (bytes32(mortgage).length > 0);
        require (bytes32(title).length > 0);
        
        // Did the Listing expire?
        if (now > expirationDate) {
            status = Status.Expired;
            LogPropertyStatusChange(msg.sender, Status.Active, Status.Expired, "Offer submitted after deadline");
            revert();
        }
        
        var newOffer = Offer(msg.sender, amountHash, mortgage, title, terms, now, 0, false, false);
        offers.push(newOffer);
        offerMap[msg.sender] = newOffer;
        refunds[msg.sender] = SafeMath.sub(msg.value, OFFER_PRICE_IN_WEI);
        
        feeBalance += OFFER_PRICE_IN_WEI;
        assert(OFFER_PRICE_IN_WEI + refunds[msg.sender] == msg.value);
        
        LogOfferSubmitted(msg.sender, mortgage, title, newOffer.dateSubmitted);
    }
    
    /**
     * @dev Amount must be non-zero and different from the current offer
     * @param amountHash - new amount of the offer
     * @param terms - new encrypted terms
     */
    function updateOffer(bytes32 amountHash, address mortgage, address title, string terms) onlyActive {
        require (offerMap[msg.sender].buyer != 0);
        require (amountHash != 0);
        require (offerMap[msg.sender].amountHash != amountHash);
        assert(msg.sender != owner);
        
        offerMap[msg.sender].amountHash = amountHash;
        offerMap[msg.sender].encryptedTerms = terms;
        offerMap[msg.sender].mortgageCompany = mortgage;
        offerMap[msg.sender].titleCompany = title;
        
        LogOfferSubmitted(msg.sender, mortgage, title, now);
    }
    
    /**
     * @dev Signal mortgage approval
     */
    function approveMortgage(address buyer) onlyContingent {
        require (offerMap[buyer].buyer != 0);
        require (msg.sender == offerMap[buyer].mortgageCompany);
        
        offerMap[buyer].mortgageCommittment = true;
    }

    /**
     * @dev Signal mortgage approval
     */
    function approveTitle(address buyer) onlyContingent {
        require (offerMap[buyer].buyer != 0);
        require (msg.sender == offerMap[buyer].titleCompany);
        
        offerMap[buyer].titleCommittment = true;
    }
    
    /**
     * @dev Withdraw an existing offer -- can only be done by buyer
     *      Can't withdraw after acceptance
     */
    function withdrawOffer() onlyActiveOrContingent {
        require(offerMap[msg.sender].buyer != 0);
        require(msg.sender != successfulBuyer);
        assert(msg.sender != owner);
        
        delete offerMap[msg.sender];
        for (uint idx = 0; idx < offers.length; idx++) {
            if (offers[idx].buyer == msg.sender) {
                delete offers[idx];
                break;
            }
        }
        
        LogOfferWithdrawn(msg.sender, now);
    }
    
    /**
     * @dev Changes the status to Contingent and sets the successfulBuyer value
     * @param winner - address that submitted the winning offer
     * @param amount - amount of the offer being accepted
     * @param key - key provided by the buyer (if private)
     */
    function acceptOffer(address winner, uint amount, string key) onlyOwner onlyActive {
        require(offerMap[winner].buyer != 0);
        require(successfulBuyer == 0);

        // Make sure amount matches
        require (keccak256(amount, key) == offerMap[winner].amountHash);
        
        offerMap[winner].dateAccepted = now;
        successfulBuyer = winner;
        salePrice = amount;
        status = Status.Contingent;
        
        LogOfferAccepted(winner, offerMap[winner].dateAccepted);
        LogPropertyStatusChange(msg.sender, Status.Active, Status.Contingent, "Offer accepted");
    }
    
    /**
     * @dev Seller can withdraw the property from the market
     */
    function withdrawListing() onlyOwner onlyActive {
        status = Status.Withdrawn;
        
        LogPropertyStatusChange(msg.sender, Status.Active, Status.Withdrawn, "Listing withdrawn");
    }

    /**
     * @dev Seller can extend the listing period
     */
    function extendListing(uint numDays) onlyOwner onlyActive {
        expirationDate = SafeMath.add(expirationDate, numDays * 1 days);
        
        LogListingExtended(numDays);
    }

    /**
     * @dev Buyer can terminate the current transaction. 
     *      Future: handle inspection, etc, reason for termination, etc.
     */
    function terminateAgreement(string reason) onlyContingent {
        require(msg.sender == successfulBuyer);
        assert(offerMap[successfulBuyer].buyer != 0);

        // Delete the bid entirely; can't accept a bid more than once!
        delete offerMap[successfulBuyer];
        for (uint idx = 0; idx < offers.length; idx++) {
            if (offers[idx].buyer == successfulBuyer) {
                delete offers[idx];
                break;
            }
        }
        successfulBuyer = 0;
        status = Status.Active;

        // Refund the deposit if the deal falls through
        var refund = refunds[successfulBuyer];
        refunds[successfulBuyer] = 0;
        successfulBuyer.transfer(refund);
        
        LogPropertyStatusChange(msg.sender, Status.Contingent, Status.Active, reason);
    }
    
    /**
     * @dev Mark property as sold. Only seller. Maybe require both?
     */
    function propertySold() onlyOwner onlyContingent {
        require(offerMap[successfulBuyer].mortgageCommittment == true);
        require(offerMap[successfulBuyer].titleCommittment == true);
        
        assert(successfulBuyer != 0);
        
        status = Status.Sold;

        LogPropertySold(successfulBuyer, now, salePrice);
    }
    
    /**
     * @dev Owner can withdraw the bidding fees at any time
     */
    function withdrawFeeBalance() onlyOwner {
        require (feeBalance > 0);
        
        var refund = feeBalance;
        feeBalance = 0;
        
        owner.transfer(refund);
    }
    
    /**
     * @dev Check the bidding fees. Let anyone do this?
     */
     function feeBalanceInquiry() constant returns(uint) {
         return feeBalance;
     }
     
    /**
     * @dev Buyers can withdraw their deposits when the property is sold
     *      There is also a time limit, in case the contract gets stuck.
     *      If the listing Expired, it's also "over," so we should allow
     *      withdrawals.
     */
    function withdrawDeposit() {
        require ((Status.Sold == status) || (Status.Expired == status) || (now > refundDate));
        require (refunds[msg.sender] != 0);
        
        var refund = refunds[msg.sender];
        refunds[msg.sender] = 0;
        
        msg.sender.transfer(refund);
    }
    
    /**
     * @dev Make sure contract isn't broken
     */
    function checkInvariant() constant returns(bool) {
        // Must have valid address and Guid
        if ((bytes(propertyAddress).length == 0) || (propertyGuid.length == 0)) {
            return false;
        }
        
        // Make sure all bids are in the map (can't go the other way; maps aren't iterable)
        uint8 acceptedOffers = 0;
        for (uint idx = 0; idx < offers.length; idx++) {
            if (offerMap[offers[idx].buyer].buyer == 0) {
                return false;
            }
            
            if (offers[idx].dateAccepted != 0) {
                SafeMath.add(acceptedOffers, 1);
            }
        }
        
        // Can have 0 or 1 accepted bids
        if (acceptedOffers > 1) {
            return false;
        }
        
        // Have to set successful bidder if it's under contract
        if ((acceptedOffers == 1) && (successfulBuyer == 0)) {
            return false;
        }
        
        return true;
    }
}
