// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./interfaces/ERC1155.sol";
/**
 * @title ITicketMaster
 * @dev Interface for the TicketMaster contract
 */
interface ITicketMaster {
    struct Event {
        string name;
        string metadata; // IPFS hash for event details
        address organizer;
        uint256 maxSupply;
        uint256 totalMinted;
        uint256 price;
        uint256 startTime;
        uint256 endTime;
        bool active;
        bool transferable;
        uint16 royaltyBps; // Basis points (1/100th of a percent)
    }

    event EventCreated(
        uint256 indexed eventId,
        address indexed organizer,
        string name,
        uint256 maxSupply,
        uint256 price
    );
    event TicketMinted(
        uint256 indexed eventId,
        address indexed buyer,
        uint256 quantity,
        uint256 totalPrice
    );
    event TicketBurned(
        uint256 indexed eventId,
        address indexed owner,
        uint256 quantity
    );
    event TicketUsed(uint256 indexed eventId, address indexed owner, uint256 tokenId);
    event EventStatusChanged(uint256 indexed eventId, bool active);
    event RoyaltyPaid(
        uint256 indexed eventId,
        address indexed from,
        address indexed to,
        uint256 amount
    );
}

/**
 * @title TicketMaster
 * @dev World-class decentralized ticketing platform using ERC1155
 * @notice This contract manages event creation, ticket minting, burning, and secondary market royalties
 */
contract TicketMaster is ERC1155, ITicketMaster {
    // State variables
    uint256 private _eventIdCounter;
    mapping(uint256 => Event) private _events;
    mapping(uint256 => mapping(uint256 => bool)) private _usedTickets; // eventId => tokenId => used
    mapping(address => uint256[]) private _organizerEvents;
    
    // Platform fee (in basis points, e.g., 250 = 2.5%)
    uint16 public platformFeeBps = 250;
    address public platformFeeRecipient;
    
    // Reentrancy guard
    uint256 private _locked = 1;
    
    modifier nonReentrant() {
        require(_locked == 1, "ReentrancyGuard: reentrant call");
        _locked = 2;
        _;
        _locked = 1;
    }
    
    modifier onlyOrganizer(uint256 eventId) {
        require(_events[eventId].organizer == msg.sender, "Not event organizer");
        _;
    }
    
    constructor(address _platformFeeRecipient) {
        require(_platformFeeRecipient != address(0), "Invalid fee recipient");
        platformFeeRecipient = _platformFeeRecipient;
    }

    /**
     * @dev Create a new event
     * @param name Event name
     * @param metadata IPFS hash containing event details
     * @param maxSupply Maximum number of tickets
     * @param price Price per ticket in wei
     * @param startTime Event start timestamp
     * @param endTime Event end timestamp
     * @param transferable Whether tickets can be transferred
     * @param royaltyBps Royalty percentage in basis points for secondary sales
     */
    function createEvent(
        string calldata name,
        string calldata metadata,
        uint256 maxSupply,
        uint256 price,
        uint256 startTime,
        uint256 endTime,
        bool transferable,
        uint16 royaltyBps
    ) external returns (uint256 eventId) {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(maxSupply > 0, "Max supply must be > 0");
        require(startTime < endTime, "Invalid time range");
        require(startTime > block.timestamp, "Start time must be in future");
        require(royaltyBps <= 5000, "Royalty too high (max 50%)");
        
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
            royaltyBps: royaltyBps
        });
        
        _organizerEvents[msg.sender].push(eventId);
        
        emit EventCreated(eventId, msg.sender, name, maxSupply, price);
        
        return eventId;
    }

    /**
     * @dev Mint tickets for an event (primary sale)
     * @param eventId The event ID
     * @param quantity Number of tickets to mint
     */


     // here is the func mint ticket
    function mintTicket(uint256 eventId, uint256 quantity)
        external
        payable
        nonReentrant
    {
        Event storage evt = _events[eventId];
        
        require(evt.organizer != address(0), "Event does not exist");
        require(evt.active, "Event is not active");
        require(evt.totalMinted + quantity <= evt.maxSupply, "Exceeds max supply");
        require(msg.value == evt.price * quantity, "Incorrect payment amount");
        require(quantity > 0, "Invalid quantity");
        
        // Calculate and distribute fees
        uint256 platformFee = (msg.value * platformFeeBps) / 10000;
        uint256 organizerAmount = msg.value - platformFee;
        
        // Update state before external calls
        evt.totalMinted += quantity;
        
        // Mint tickets
        _mint(msg.sender, eventId, quantity, "");
        
        // Transfer funds
        (bool success1, ) = platformFeeRecipient.call{value: platformFee}("");
        require(success1, "Platform fee transfer failed");
        
        (bool success2, ) = evt.organizer.call{value: organizerAmount}("");
        require(success2, "Organizer payment failed");
        
        emit TicketMinted(eventId, msg.sender, quantity, msg.value);
    }

    /**
     * @dev Batch mint tickets for multiple buyers (organizer only)
     * @param eventId The event ID
     * @param recipients Array of recipient addresses
     * @param quantities Array of quantities for each recipient
     */
    function batchMintTickets(
        uint256 eventId,
        address[] calldata recipients,
        uint256[] calldata quantities
    ) external onlyOrganizer(eventId) {
        require(recipients.length == quantities.length, "Length mismatch");
        require(recipients.length <= 50, "Too many recipients");
        
        Event storage evt = _events[eventId];
        require(evt.active, "Event is not active");
        
        uint256 totalQuantity = 0;
        for (uint256 i = 0; i < quantities.length; i++) {
            totalQuantity += quantities[i];
        }
        
        require(evt.totalMinted + totalQuantity <= evt.maxSupply, "Exceeds max supply");
        
        evt.totalMinted += totalQuantity;
        
        // Mint to each recipient
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(quantities[i] > 0, "Invalid quantity");
            _mint(recipients[i], eventId, quantities[i], "");
        }
    }

    /**
     * @dev Burn/use tickets (e.g., when entering the venue)
     * @param eventId The event ID
     * @param quantity Number of tickets to burn
     */
    function burnTicket(uint256 eventId, uint256 quantity) external {
        require(_events[eventId].organizer != address(0), "Event does not exist");
        require(balanceOf[msg.sender][eventId] >= quantity, "Insufficient balance");
        require(quantity > 0, "Invalid quantity");
        
        _burn(msg.sender, eventId, quantity);
        
        emit TicketBurned(eventId, msg.sender, quantity);
    }

    /**
     * @dev Mark a ticket as used without burning (for validation/check-in)
     * @param eventId The event ID
     * @param tokenId The specific token ID to mark as used
     */
    function useTicket(uint256 eventId, uint256 tokenId)
        external
        onlyOrganizer(eventId)
    {
        require(!_usedTickets[eventId][tokenId], "Ticket already used");
        _usedTickets[eventId][tokenId] = true;
        
        emit TicketUsed(eventId, msg.sender, tokenId);
    }

    /**
     * @dev Transfer tickets with royalty payment (secondary market)
     * @param from Sender address
     * @param to Recipient address
     * @param eventId Event ID
     * @param quantity Number of tickets
     */
    function safeTransferFromWithRoyalty(
        address from,
        address to,
        uint256 eventId,
        uint256 quantity
    ) external payable nonReentrant {
        Event storage evt = _events[eventId];
        require(evt.transferable, "Tickets are non-transferable");
        require(evt.organizer != address(0), "Event does not exist");
        
        // Calculate royalty
        uint256 royaltyAmount = (msg.value * evt.royaltyBps) / 10000;
        uint256 sellerAmount = msg.value - royaltyAmount;
        
        // Transfer the ticket
        require(
            msg.sender == from || isApprovedForAll[from][msg.sender],
            "Not approved"
        );
        require(to != address(0), "Invalid recipient");
        
        balanceOf[from][eventId] -= quantity;
        balanceOf[to][eventId] += quantity;
        
        emit TransferSingle(msg.sender, from, to, eventId, quantity);
        
        // Pay royalty to organizer
        if (royaltyAmount > 0) {
            (bool success1, ) = evt.organizer.call{value: royaltyAmount}("");
            require(success1, "Royalty payment failed");
            emit RoyaltyPaid(eventId, from, evt.organizer, royaltyAmount);
        }
        
        // Pay seller
        if (sellerAmount > 0) {
            (bool success2, ) = from.call{value: sellerAmount}("");
            require(success2, "Seller payment failed");
        }
        
        // Safe transfer check
        if (to.code.length > 0) {
            require(
                IERC1155TokenReceiver(to).onERC1155Received(
                    msg.sender, from, eventId, quantity, ""
                ) == IERC1155TokenReceiver.onERC1155Received.selector,
                "Unsafe transfer"
            );
        }
    }

    /**
     * @dev Set event active status
     * @param eventId The event ID
     * @param active New active status
     */
    function setEventStatus(uint256 eventId, bool active)
        external
        onlyOrganizer(eventId)
    {
        _events[eventId].active = active;
        emit EventStatusChanged(eventId, active);
    }

    /**
     * @dev Update event metadata
     * @param eventId The event ID
     * @param metadata New IPFS hash
     */
    function updateEventMetadata(uint256 eventId, string calldata metadata)
        external
        onlyOrganizer(eventId)
    {
        require(bytes(metadata).length > 0, "Invalid metadata");
        _events[eventId].metadata = metadata;
    }

    /**
     * @dev Update platform fee (owner only - you'd add Ownable pattern)
     * @param newFeeBps New fee in basis points
     */
    function updatePlatformFee(uint16 newFeeBps) external {
        require(msg.sender == platformFeeRecipient, "Not authorized");
        require(newFeeBps <= 1000, "Fee too high (max 10%)");
        platformFeeBps = newFeeBps;
    }

    /**
     * @dev Emergency withdraw for organizer (only before event starts)
     * @param eventId The event ID
     */
    function emergencyWithdraw(uint256 eventId)
        external
        onlyOrganizer(eventId)
    {
        Event storage evt = _events[eventId];
        require(block.timestamp < evt.startTime, "Event already started");
        require(evt.totalMinted == 0, "Tickets already sold");
        
        evt.active = false;
        emit EventStatusChanged(eventId, false);
    }

    // View functions
    
    function getEvent(uint256 eventId)
        external
        view
        returns (Event memory)
    {
        return _events[eventId];
    }

    function getEventsByOrganizer(address organizer)
        external
        view
        returns (uint256[] memory)
    {
        return _organizerEvents[organizer];
    }

    function isTicketUsed(uint256 eventId, uint256 tokenId)
        external
        view
        returns (bool)
    {
        return _usedTickets[eventId][tokenId];
    }

    function getAvailableTickets(uint256 eventId)
        external
        view
        returns (uint256)
    {
        Event storage evt = _events[eventId];
        return evt.maxSupply - evt.totalMinted;
    }

    function uri(uint256 eventId)
        public
        view
        override
        returns (string memory)
    {
        Event storage evt = _events[eventId];
        require(evt.organizer != address(0), "Event does not exist");
        return evt.metadata;
    }

    // ERC2981 Royalty Standard support
    function royaltyInfo(uint256 eventId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        Event storage evt = _events[eventId];
        receiver = evt.organizer;
        royaltyAmount = (salePrice * evt.royaltyBps) / 10000;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        pure
        override
        returns (bool)
    {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0xd9b67a26 // ERC1155
            || interfaceId == 0x0e89341c // ERC1155MetadataURI
            || interfaceId == 0x2a55205a; // ERC2981 Royalty
    }
}