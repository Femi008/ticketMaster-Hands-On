// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interfaces/ERC1155.sol";

interface ITicketMaster {
    struct Event {
        string name;
        string metadata;
        address organizer;
        uint256 maxSupply;
        uint256 totalMinted;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        bool active;
        bool transferable;
        bool dynamicPricing;
        uint16 royaltyBps;
    }

    struct TicketProof {
        uint256 eventId;
        address originalOwner;
        uint256 mintTimestamp;
        bytes32 proofHash;
        bool isValid;
    }

    event EventCreated(uint256 indexed eventId, address indexed organizer, string name, uint256 maxSupply, uint256 price);
    event TicketMinted(uint256 indexed eventId, address indexed buyer, uint256 quantity, uint256 totalPrice);
    event TicketUsed(uint256 indexed eventId, address indexed owner, uint256 ticketId);
    event EventStatusChanged(uint256 indexed eventId, bool active);
    event RoyaltyPaid(uint256 indexed eventId, address indexed from, address indexed to, uint256 amount);
    event TicketVerified(uint256 indexed eventId, uint256 indexed ticketId, address indexed owner, bytes32 proofHash);
    event FraudAttemptDetected(uint256 indexed eventId, uint256 indexed ticketId, address indexed attacker, string reason);
    event TicketInvalidated(uint256 indexed eventId, uint256 indexed ticketId, string reason);
}

contract TicketMaster is ERC1155, ITicketMaster {
    // ------------------------
    // Errors
    // ------------------------
    error Err_InvalidFeeRecipient();
    error Err_NotOrganizer();
    error Err_NotAdmin();
    error Err_EventNotExist();
    error Err_InvalidVerifier();
    error Err_InvalidParams();
    error Err_MaxSupplyExceeded();
    error Err_EventNotActive();
    error Err_InsufficientPayment();
    error Err_TransferNotAllowed();
    error Err_TicketInvalid();
    error Err_TicketUsed();
    error Err_NotTicketOwner();
    error Err_Blacklisted();
    error Err_RoyaltyPaymentFailed();
    error Err_PaymentFailed();
    error Err_UnsafeTransfer();

    // ------------------------
    // State - Optimized packing
    // ------------------------
    uint256 private _eventIdCounter;
    uint256 private _ticketIdCounter;

    mapping(uint256 => Event) private _events;

    // Simplified ticket tracking - reduced storage operations
    mapping(uint256 => TicketProof) private _ticketProofs;
    mapping(uint256 => mapping(address => uint256[])) private _userTickets;

    // Minimal tracking for transfers
    mapping(uint256 => address) private _currentTicketOwner;
    mapping(uint256 => uint8) private _ticketTransferCount;

    // Essential verifications only
    mapping(uint256 => address) private _eventVerifiers;
    mapping(uint256 => mapping(uint256 => bool)) private _usedTickets;
    mapping(address => bool) private _blacklisted;

    uint16 public platformFeeBps = 250; // 2.5%
    address public platformFeeRecipient;
    address public admin;

    uint8 private _locked = 1;

    // ------------------------
    // Modifiers
    // ------------------------
    modifier nonReentrant() {
        if (_locked != 1) revert Err_InvalidParams();
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlyOrganizer(uint256 eventId) {
        if (_events[eventId].organizer != msg.sender) revert Err_NotOrganizer();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Err_NotAdmin();
        _;
    }

    modifier notBlacklisted() {
        if (_blacklisted[msg.sender]) revert Err_Blacklisted();
        _;
    }

    // ------------------------
    // Constructor
    // ------------------------
    constructor(address _platformFeeRecipient) ERC1155() {
        if (_platformFeeRecipient == address(0)) revert Err_InvalidFeeRecipient();
        platformFeeRecipient = _platformFeeRecipient;
        admin = msg.sender;
    }

    // ------------------------
    // Create event (verifier optional)
    // ------------------------
    function createEvent(
        string calldata name,
        string calldata metadata,
        uint256 maxSupply,
        uint256 price,
        uint256 startTime,
        uint256 endTime,
        bool transferable,
        bool dynamicPricing,
        uint16 royaltyBps,
        address verifier
    ) external returns (uint256 eventId) {
        if (bytes(name).length == 0 || maxSupply == 0) revert Err_InvalidParams();
        if (startTime >= endTime) revert Err_InvalidParams();
        if (royaltyBps > 5000) revert Err_InvalidParams();

        // verifier is optional; do not revert if address(0)

        eventId = _eventIdCounter++;
        _events[eventId] = Event({
            name: name,
            metadata: metadata,
            organizer: msg.sender,
            maxSupply: maxSupply,
            totalMinted: 0,
            price: price,
            startTime: startTime,
            endTime: endTime,
            active: true,
            transferable: transferable,
            dynamicPricing: dynamicPricing,
            royaltyBps: royaltyBps
        });

        // optional verifier
        if (verifier != address(0)) {
            _eventVerifiers[eventId] = verifier;
        } else {
            _eventVerifiers[eventId] = address(0);
        }

        emit EventCreated(eventId, msg.sender, name, maxSupply, price);
        return eventId;
    }

    // ------------------------
    // Dynamic price (FIXED - safe math, no overflow)
    // ------------------------
    function getDynamicPrice(uint256 eventId) public view returns (uint256) {
        Event storage evt = _events[eventId];
        if (evt.organizer == address(0)) revert Err_EventNotExist();

        // if dynamic pricing disabled, return base price
        if (!evt.dynamicPricing) {
            return evt.price;
        }

        // if maxSupply is zero, return base price (avoid division by zero)
        if (evt.maxSupply == 0) {
            return evt.price;
        }

        // if nothing minted yet — early bird price
        if (evt.totalMinted == 0) {
            return evt.price;
        }

        // FIXED: Safe calculation to avoid overflow
        // Calculate demand ratio: (totalMinted / maxSupply) with proper scaling
        // Using basis points (10000) for precision
        uint256 demandBps = (evt.totalMinted * 10000) / evt.maxSupply;
        if (demandBps > 10000) demandBps = 10000; // Cap at 100%

        // Price increase: max 50% increase at full capacity
        // priceIncrease = (price * demandBps * 50) / (10000 * 100)
        // Simplified: (price * demandBps) / 20000
        uint256 priceIncrease = (evt.price * demandBps) / 20000;

        return evt.price + priceIncrease;
    }

    // ------------------------
    // Mint - optimized & safe payment transfers
    // ------------------------
    function mintTicket(uint256 eventId, uint256 quantity) external payable nonReentrant notBlacklisted {
        Event storage evt = _events[eventId];
        if (evt.organizer == address(0)) revert Err_EventNotExist();
        if (!evt.active) revert Err_EventNotActive();
        if (quantity == 0 || quantity > 10) revert Err_InvalidParams();
        if (evt.totalMinted + quantity > evt.maxSupply) revert Err_MaxSupplyExceeded();

        uint256 currentPrice = getDynamicPrice(eventId);
        uint256 totalPrice = currentPrice * quantity;
        if (msg.value < totalPrice) revert Err_InsufficientPayment();

        uint256 platformFee;
        uint256 organizerAmount;
        unchecked {
            platformFee = (totalPrice * platformFeeBps) / 10000;
            organizerAmount = totalPrice - platformFee;
        }

        // Batch update total minted
        evt.totalMinted += quantity;

        // CRITICAL OPTIMIZATION: Minimize storage operations
        uint256 startTicketId = _ticketIdCounter;
        _ticketIdCounter += quantity;

        // Use memory for temporary data
        uint256 timestamp = block.timestamp;
        address sender = msg.sender;

        unchecked {
            for (uint256 i = 0; i < quantity; ++i) {
                uint256 ticketId = startTicketId + i;

                bytes32 proofHash = keccak256(abi.encodePacked(eventId, ticketId, sender, timestamp));

                _ticketProofs[ticketId] = TicketProof({
                    eventId: eventId,
                    originalOwner: sender,
                    mintTimestamp: timestamp,
                    proofHash: proofHash,
                    isValid: true
                });

                _currentTicketOwner[ticketId] = sender;
                _userTickets[eventId][sender].push(ticketId);
            }
        }

        // Single ERC1155 mint for all tickets
        _mint(sender, eventId, quantity, "");

        // Pay platform fee (safe high-level call)
        if (platformFee > 0) {
            (bool okPf, ) = payable(platformFeeRecipient).call{value: platformFee}("");
            if (!okPf) revert Err_PaymentFailed();
        }

        // Pay organizer
        if (organizerAmount > 0) {
            (bool okOrg, ) = payable(evt.organizer).call{value: organizerAmount}("");
            if (!okOrg) revert Err_PaymentFailed();
        }

        // Refund excess payment
        unchecked {
            uint256 excess = msg.value - totalPrice;
            if (excess > 0) {
                (bool refundOk, ) = payable(sender).call{value: excess}("");
                if (!refundOk) revert Err_PaymentFailed();
            }
        }

        emit TicketMinted(eventId, sender, quantity, totalPrice);
    }

    // ------------------------
    // Ticket proof helpers
    // ------------------------
    function verifyTicket(uint256 ticketId, address owner) external view returns (bool, bytes32) {
        TicketProof storage p = _ticketProofs[ticketId];
        if (!p.isValid) return (false, p.proofHash);
        if (_currentTicketOwner[ticketId] != owner) return (false, p.proofHash);
        if (_usedTickets[p.eventId][ticketId]) return (false, p.proofHash);

        return (true, p.proofHash);
    }

    // ------------------------
    // Use tickets
    // ------------------------
    function useTicket(uint256 eventId, uint256 ticketId, address owner) external onlyOrganizer(eventId) {
        TicketProof storage p = _ticketProofs[ticketId];
        if (!p.isValid || p.eventId != eventId) revert Err_TicketInvalid();
        if (_usedTickets[eventId][ticketId]) revert Err_TicketUsed();
        if (_currentTicketOwner[ticketId] != owner) revert Err_NotTicketOwner();
        if (balanceOf[owner][eventId] == 0) revert Err_InvalidParams();

        _usedTickets[eventId][ticketId] = true;
        emit TicketUsed(eventId, owner, ticketId);
    }

    // ------------------------
    // Transfer with royalty - OPTIMIZED & safer
    // ------------------------
    function safeTransferFromWithRoyalty(
        address from,
        address to,
        uint256 eventId,
        uint256 quantity,
        uint256[] calldata ticketIds
    ) external payable nonReentrant notBlacklisted {
        Event storage evt = _events[eventId];
        if (!evt.transferable) revert Err_TransferNotAllowed();
        if (evt.organizer == address(0)) revert Err_EventNotExist();
        if (_blacklisted[to]) revert Err_Blacklisted();
        if (ticketIds.length != quantity) revert Err_InvalidParams();
        if (msg.sender != from && !isApprovedForAll[from][msg.sender]) revert Err_UnsafeTransfer();

        // Optimized validation loop
        unchecked {
            for (uint256 i = 0; i < quantity; ++i) {
                uint256 ticketId = ticketIds[i];
                TicketProof storage p = _ticketProofs[ticketId];

                if (!p.isValid || p.eventId != eventId) revert Err_TicketInvalid();
                if (_usedTickets[eventId][ticketId]) revert Err_TicketInvalid();
                if (_currentTicketOwner[ticketId] != from) revert Err_NotTicketOwner();

                // Update ownership
                _currentTicketOwner[ticketId] = to;
                
                // FIXED: Safe increment to prevent overflow
                if (_ticketTransferCount[ticketId] < type(uint8).max) {
                    _ticketTransferCount[ticketId]++;
                }

                // Update user tickets arrays
                _removeUserTicket(eventId, from, ticketId);
                _userTickets[eventId][to].push(ticketId);
            }
        }

        _safeTransferFrom(from, to, eventId, quantity, "");

        // Handle payments only if value sent
        if (msg.value > 0) {
            uint256 royaltyAmount;
            uint256 sellerAmount;

            unchecked {
                royaltyAmount = (msg.value * evt.royaltyBps) / 10000;
                sellerAmount = msg.value - royaltyAmount;
            }

            if (royaltyAmount > 0) {
                (bool okR, ) = payable(evt.organizer).call{value: royaltyAmount}("");
                if (!okR) revert Err_RoyaltyPaymentFailed();
                emit RoyaltyPaid(eventId, from, evt.organizer, royaltyAmount);
            }

            if (sellerAmount > 0) {
                (bool okS, ) = payable(from).call{value: sellerAmount}("");
                if (!okS) revert Err_PaymentFailed();
            }
        }
    }

    function _removeUserTicket(uint256 eventId, address user, uint256 ticketId) private {
        uint256[] storage tickets = _userTickets[eventId][user];
        uint256 len = tickets.length;
        unchecked {
            for (uint256 i = 0; i < len; ++i) {
                if (tickets[i] == ticketId) {
                    tickets[i] = tickets[len - 1];
                    tickets.pop();
                    return;
                }
            }
        }
    }

    // ------------------------
    // Admin / blacklist / fraud
    // ------------------------
    function invalidateTicket(uint256 ticketId, string calldata reason) external {
        TicketProof storage p = _ticketProofs[ticketId];
        uint256 eventId = p.eventId;
        if (!(msg.sender == admin || msg.sender == _events[eventId].organizer)) revert Err_NotAdmin();
        if (!p.isValid) revert Err_TicketInvalid();

        p.isValid = false;
        emit TicketInvalidated(eventId, ticketId, reason);
        emit FraudAttemptDetected(eventId, ticketId, address(0), reason);
    }

    function blacklistAddress(address user, bool blacklisted) external onlyAdmin {
        _blacklisted[user] = blacklisted;
    }

    function reportFraud(uint256 eventId, uint256 ticketId, address suspected, string calldata reason) external {
        emit FraudAttemptDetected(eventId, ticketId, suspected, reason);
    }

    // ------------------------
    // Helpers
    // ------------------------
    function getEvent(uint256 eventId) external view returns (Event memory) {
        return _events[eventId];
    }

    function getTicketProof(uint256 ticketId) external view returns (TicketProof memory) {
        return _ticketProofs[ticketId];
    }

    function getUserTickets(uint256 eventId, address user) external view returns (uint256[] memory) {
        return _userTickets[eventId][user];
    }

    function getAvailableTickets(uint256 eventId) external view returns (uint256) {
        Event storage evt = _events[eventId];
        unchecked {
            return evt.maxSupply - evt.totalMinted;
        }
    }

    function isTicketUsed(uint256 eventId, uint256 ticketId) external view returns (bool) {
        return _usedTickets[eventId][ticketId];
    }

    function isAddressBlacklisted(address user) external view returns (bool) {
        return _blacklisted[user];
    }

    // ------------------------
    // Receive ETH
    // ------------------------
    receive() external payable {}
    fallback() external payable {}
}