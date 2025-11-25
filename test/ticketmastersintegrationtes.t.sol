// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/TicketMaster.sol";

contract TicketMasterTest is Test {
    TicketMaster public ticketMaster;
    address public organizer = address(0x1);
    address public buyer = address(0x2);
    address public feeRecipient = address(0x3);
    uint256 public eventId;

    function setUp() public {
        ticketMaster = new TicketMaster(feeRecipient);
        
        vm.prank(organizer);
        eventId = ticketMaster.createEvent(
            "Concert",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            true,  // dynamic pricing enabled
            500,   // 5% royalty
            address(0)
        );
    }

    // ============= FIXED: Dynamic Pricing Tests =============
    
    function testDynamicPricing_InitialPriceWhenNoTicketsMinted() public {
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        assertEq(price, 1 ether, "Initial price should be base price");
    }

    function testDynamicPricing_DisabledReturnsBasePrice() public {
        vm.prank(organizer);
        uint256 newEventId = ticketMaster.createEvent(
            "Concert2",
            "metadata",
            100,
            2 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,  // dynamic pricing disabled
            500,
            address(0)
        );

        uint256 price = ticketMaster.getDynamicPrice(newEventId);
        assertEq(price, 2 ether, "Price should remain constant when disabled");
    }

    function testDynamicPricing_EarlyBirdAdvantage() public {
        // Early bird should get base price
        uint256 initialPrice = ticketMaster.getDynamicPrice(eventId);
        assertEq(initialPrice, 1 ether, "Early bird price should be base price");
        
        // Now mint and verify it worked
        vm.prank(buyer);
        vm.deal(buyer, initialPrice);
        ticketMaster.mintTicket{value: initialPrice}(eventId, 1);
        
        uint256[] memory tickets = ticketMaster.getUserTickets(eventId, buyer);
        assertEq(tickets.length, 1, "Should have minted 1 ticket");
    }

    function testDynamicPricing_PriceIncreasesWithDemand() public {
    // The issue: we're trying to mint 10 tickets at priceAt0, but the actual cost
    // needs to account for dynamic pricing changes DURING the mint operation.
    // Solution: Get prices after each mint, and send sufficient funds each time.
    
    vm.deal(organizer, 200 ether);
    
    vm.prank(organizer);
    uint256 testEventId = ticketMaster.createEvent(
        "DemandTest",
        "data",
        100,  // Small supply for easy capacity tracking
        1 ether,
        block.timestamp,
        block.timestamp + 100000,
        true,
        true,  // dynamic pricing enabled
        500,
        address(0)
    );

    // Price at 0% capacity
    uint256 priceAt0 = ticketMaster.getDynamicPrice(testEventId);
    assertEq(priceAt0, 1 ether, "Initial price should be base price");
    
    // Mint 10 tickets (10% capacity)
    address minter = address(0x555);
    vm.deal(minter, 200 ether);
    vm.prank(minter);
    // Send extra funds to account for any price changes during minting
    ticketMaster.mintTicket{value: 20 ether}(testEventId, 10);
    
    // Price at 10% capacity
    uint256 priceAt10 = ticketMaster.getDynamicPrice(testEventId);
    
    // Mint 10 more tickets (20% capacity total)
    // Again, send extra to be safe
    vm.prank(minter);
    ticketMaster.mintTicket{value: 20 ether}(testEventId, 10);
    
    // Price at 20% capacity
    uint256 priceAt20 = ticketMaster.getDynamicPrice(testEventId);
    
    // Verify progression: price should increase or stay same as demand increases
    assertGe(priceAt10, priceAt0, "Price at 10% should be >= price at 0%");
    assertGe(priceAt20, priceAt10, "Price at 20% should be >= price at 10%");
    // Most importantly, final price should be higher than initial
    assertGt(priceAt20, priceAt0, "Price should increase with demand");
}
    function testDynamicPricing_MaxPriceIncrease() public {
        // Test that price caps at 50% increase
        vm.deal(organizer, 200 ether);
        
        vm.prank(organizer);
        uint256 testEventId = ticketMaster.createEvent(
            "MaxPriceTest",
            "data",
            100,  // 100 max supply
            1 ether,
            block.timestamp + 100,
            block.timestamp + 100000,
            true,
            true,
            500,
            address(0)
        );

        uint256 basePrice = 1 ether;
        
        // Mint to 80% capacity (80 out of 100)
        address minter = address(0x666);
        vm.deal(minter, 500 ether);
        
        uint256 currentPrice = ticketMaster.getDynamicPrice(testEventId);
        
        // Mint 8 times to get 80 tickets (8 * 10 = 80)
        for (uint256 i = 0; i < 8; i++) {
            vm.prank(minter);
            ticketMaster.mintTicket{value: currentPrice * 10}(testEventId, 10);
            currentPrice = ticketMaster.getDynamicPrice(testEventId);
        }

        // At 80% capacity, price should be capped at 50% increase max
        uint256 priceAt80 = ticketMaster.getDynamicPrice(testEventId);
        uint256 maxAllowed = basePrice + (basePrice / 2);  // 1.5 ether (50% increase)
        
        assertLe(priceAt80, maxAllowed, "Price at 80% should not exceed 50% increase");
        
        // Now mint to 90% (90 out of 100)
        vm.prank(minter);
        ticketMaster.mintTicket{value: currentPrice * 10}(testEventId, 10);
        
        uint256 priceAt90 = ticketMaster.getDynamicPrice(testEventId);
        assertLe(priceAt90, maxAllowed, "Price at 90% should not exceed 50% increase");
        
        // Verify price didn't go down
        assertGe(priceAt90, priceAt80, "Price should not decrease as demand increases");
    }

    function testFuzz_DynamicPricing(uint8 ticketsToMint) public {
        // Bound to prevent exceeding max supply and overflow
        ticketsToMint = uint8(bound(ticketsToMint, 1, 9));
        
        // Create a fresh event for each fuzz run
        vm.prank(organizer);
        vm.deal(organizer, 100 ether);
        uint256 fuzzEventId = ticketMaster.createEvent(
            string(abi.encodePacked("FuzzEvent", vm.toString(ticketsToMint))),
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            true,
            500,
            address(0)
        );
        
        uint256 price = ticketMaster.getDynamicPrice(fuzzEventId);
        uint256 totalPrice = price * ticketsToMint;

        address fuzzBuyer = address(uint160(0xABCD) + ticketsToMint);
        vm.deal(fuzzBuyer, 200 ether);
        vm.prank(fuzzBuyer);
        ticketMaster.mintTicket{value: totalPrice}(fuzzEventId, ticketsToMint);

        uint256[] memory tickets = ticketMaster.getUserTickets(fuzzEventId, fuzzBuyer);
        assertEq(tickets.length, ticketsToMint, "Ticket count should match");
    }

    // ============= FIXED: Mint Tests =============
    
    function testMintTickets() public {
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        
        vm.prank(buyer);
        vm.deal(buyer, price);
        ticketMaster.mintTicket{value: price}(eventId, 1);

        uint256[] memory tickets = ticketMaster.getUserTickets(eventId, buyer);
        assertEq(tickets.length, 1, "Should have minted 1 ticket");
    }

    function testFuzz_MintTickets(uint8 quantity) public {
        quantity = uint8(bound(quantity, 1, 9));
        
        // Use a fresh event to avoid state conflicts
        vm.prank(organizer);
        vm.deal(organizer, 100 ether);
        uint256 fuzzEventId = ticketMaster.createEvent(
            string(abi.encodePacked("MintEvent", vm.toString(quantity))),
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );

        uint256 price = ticketMaster.getDynamicPrice(fuzzEventId);
        uint256 totalPrice = price * quantity;

        address fuzzBuyer = address(uint160(0xBEEF) + quantity);
        vm.deal(fuzzBuyer, totalPrice + 1 ether);
        vm.prank(fuzzBuyer);
        ticketMaster.mintTicket{value: totalPrice}(fuzzEventId, quantity);

        uint256[] memory tickets = ticketMaster.getUserTickets(fuzzEventId, fuzzBuyer);
        assertEq(tickets.length, quantity, "Ticket count should match quantity");
    }

    function testMintTicketsWithExcessPayment() public {
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        uint256 excessPayment = price + 0.5 ether;

        vm.prank(buyer);
        vm.deal(buyer, excessPayment);
        ticketMaster.mintTicket{value: excessPayment}(eventId, 1);

        uint256[] memory tickets = ticketMaster.getUserTickets(eventId, buyer);
        assertEq(tickets.length, 1, "Should mint despite excess payment");
    }

    // ============= FIXED: Transfer Tests =============
    
    function testSafeTransferWithRoyalty() public {
        // First, mint tickets
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        uint256 totalPrice = price * 2;

        vm.prank(buyer);
        vm.deal(buyer, totalPrice);
        ticketMaster.mintTicket{value: totalPrice}(eventId, 2);

        // Get buyer's tickets
        uint256[] memory tickets = ticketMaster.getUserTickets(eventId, buyer);
        require(tickets.length >= 2, "Should have at least 2 tickets");

        // Prepare ticket IDs for transfer
        uint256[] memory ticketIds = new uint256[](2);
        ticketIds[0] = tickets[0];
        ticketIds[1] = tickets[1];

        address receiver = address(0x4);
        uint256 transferPrice = 0.5 ether;  // Price for resale

        // Transfer with royalty payment
        vm.prank(buyer);
        vm.deal(buyer, transferPrice);
        ticketMaster.safeTransferFromWithRoyalty{value: transferPrice}(
            buyer,
            receiver,
            eventId,
            2,
            ticketIds
        );

        uint256[] memory receiverTickets = ticketMaster.getUserTickets(eventId, receiver);
        assertEq(receiverTickets.length, 2, "Receiver should have 2 tickets");
    }

    // ============= Event Tests =============
    
    function testCreateEvent() public {
        uint256 newEventId = ticketMaster.createEvent(
            "Festival",
            "metadata",
            500,
            2 ether,
            block.timestamp,
            block.timestamp + 7 days,
            false,
            false,
            1000,
            address(0)
        );

        ITicketMaster.Event memory evt = ticketMaster.getEvent(newEventId);
        assertEq(evt.name, "Festival", "Event name should match");
        assertEq(evt.maxSupply, 500, "Max supply should match");
    }

    function testBlacklistAndInvalidate() public {
        // Mint a ticket
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        vm.prank(buyer);
        vm.deal(buyer, price);
        ticketMaster.mintTicket{value: price}(eventId, 1);

        uint256[] memory tickets = ticketMaster.getUserTickets(eventId, buyer);
        uint256 ticketId = tickets[0];

        // Blacklist the buyer
        ticketMaster.blacklistAddress(buyer, true);
        assertTrue(ticketMaster.isAddressBlacklisted(buyer), "Should be blacklisted");

        // Invalidate the ticket
        vm.prank(organizer);
        ticketMaster.invalidateTicket(ticketId, "Fraudulent ticket");
        
        (bool valid,) = ticketMaster.verifyTicket(ticketId, buyer);
        assertFalse(valid, "Ticket should be invalid");
    }

    // ============= Revert Tests =============
    
    function testRevert_CreateEventInvalidParams() public {
        vm.expectRevert();
        ticketMaster.createEvent(
            "",  // Empty name
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );
    }

    function testRevert_MintInsufficientPayment() public {
        uint256 price = ticketMaster.getDynamicPrice(eventId);
        uint256 insufficientPayment = price / 2;  // Half the price
        
        vm.prank(buyer);
        vm.deal(buyer, insufficientPayment);
        vm.expectRevert(TicketMaster.Err_InsufficientPayment.selector);
        ticketMaster.mintTicket{value: insufficientPayment}(eventId, 1);
    }

    function testRevert_MintExceedsMaxSupply() public {
        vm.prank(organizer);
        vm.deal(organizer, 100 ether);
        uint256 smallEventId = ticketMaster.createEvent(
            "SmallEvent",
            "metadata",
            5,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            true,
            false,
            500,
            address(0)
        );

        uint256 price = ticketMaster.getDynamicPrice(smallEventId);
        uint256 totalPrice = price * 10;  // Try to mint more than max supply

        vm.prank(buyer);
        vm.deal(buyer, totalPrice);
        vm.expectRevert(TicketMaster.Err_MaxSupplyExceeded.selector);
        ticketMaster.mintTicket{value: totalPrice}(smallEventId, 10);
    }

    function testRevert_TransferNotAllowed() public {
        // Create non-transferable event
        vm.prank(organizer);
        vm.deal(organizer, 100 ether);
        uint256 nonTransferableEventId = ticketMaster.createEvent(
            "NonTransferable",
            "metadata",
            100,
            1 ether,
            block.timestamp,
            block.timestamp + 1 days,
            false,  // Not transferable
            false,
            500,
            address(0)
        );

        // Mint ticket
        uint256 price = ticketMaster.getDynamicPrice(nonTransferableEventId);
        vm.prank(buyer);
        vm.deal(buyer, price);
        ticketMaster.mintTicket{value: price}(nonTransferableEventId, 1);

        uint256[] memory tickets = ticketMaster.getUserTickets(nonTransferableEventId, buyer);
        uint256[] memory ticketIds = new uint256[](1);
        ticketIds[0] = tickets[0];

        vm.prank(buyer);
        vm.expectRevert(TicketMaster.Err_TransferNotAllowed.selector);
        ticketMaster.safeTransferFromWithRoyalty(buyer, address(0x5), nonTransferableEventId, 1, ticketIds);
    }
}